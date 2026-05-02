#!/usr/bin/env bash
#
# fedora-setup.sh - Post-install setup para Fedora Workstation
#
# Uso:
#   ./fedora-setup.sh           # Ejecuta todas las instalaciones
#   ./fedora-setup.sh --dry-run # Muestra qué haría sin ejecutarlo
#
# Requisitos: Fedora con dnf5 (Fedora 41+)

set -euo pipefail

# ---------- Config ----------
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

# ---------- Helpers ----------
log()   { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
ok()    { printf '\033[1;32m[ OK ]\033[0m  %s\n' "$*"; }
warn()  { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*"; }
err()   { printf '\033[1;31m[ERR ]\033[0m  %s\n' "$*" >&2; }

run() {
    if [[ $DRY_RUN -eq 1 ]]; then
        printf '\033[1;35m[DRY ]\033[0m  %s\n' "$*"
    else
        eval "$@"
    fi
}

is_installed() {
    rpm -q "$1" &>/dev/null
}

repo_enabled() {
    sudo dnf repo list --enabled 2>/dev/null | awk '{print $1}' | grep -qx "$1"
}

# ---------- Pre-flight ----------
require_dnf5() {
    if ! command -v dnf &>/dev/null; then
        err "dnf no encontrado"; exit 1
    fi
    if ! dnf --version 2>&1 | grep -q '^dnf5'; then
        warn "Este script asume dnf5 (Fedora 41+). Algunos comandos pueden fallar."
    fi
}

# ---------- Apps ----------

install_chrome() {
    log "Google Chrome"

    if is_installed google-chrome-stable; then
        ok "Chrome ya instalado, saltando"
        return 0
    fi

    # 1) Repos de workstation (incluye el .repo de google-chrome, deshabilitado por defecto)
    if ! is_installed fedora-workstation-repositories; then
        run "sudo dnf install -y fedora-workstation-repositories"
    fi

    # 2) Habilitar repo de Chrome (sintaxis dnf5)
    if ! repo_enabled google-chrome; then
        run "sudo dnf config-manager enable google-chrome"
    fi

    # 3) Instalar
    run "sudo dnf install -y google-chrome-stable"

    ok "Chrome instalado"
}

install_vscode() {
    log "Visual Studio Code"

    if is_installed code; then
        ok "VS Code ya instalado, saltando"
        return 0
    fi

    # 1) Importar clave GPG de Microsoft (idempotente, no falla si ya existe)
    run "sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc"

    # 2) Crear el .repo si no existe
    local repo_file="/etc/yum.repos.d/vscode.repo"
    if [[ ! -f "$repo_file" ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            printf '\033[1;35m[DRY ]\033[0m  Crear %s\n' "$repo_file"
        else
            sudo tee "$repo_file" > /dev/null <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
autorefresh=1
type=rpm-md
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
        fi
    fi

    # 3) Instalar (paquete: 'code', no 'vscode')
    run "sudo dnf install -y code"

    ok "VS Code instalado"
}

install_nerd_fonts() {
    log "Nerd Fonts (JetBrainsMono)"

    if fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd Font"; then
        ok "JetBrainsMono Nerd Font ya instalada, saltando"
        return 0
    fi

    local fonts_dir="$HOME/.local/share/fonts/JetBrainsMono"
    local tmp_file="/tmp/JetBrainsMono.tar.xz"
    local download_url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz"

    # Limpiar el COPR che/nerd-fonts si lo añadimos antes (ya no lo necesitamos)
    local old_repo="/etc/yum.repos.d/che-nerd-fonts.repo"
    if [[ -f "$old_repo" ]]; then
        run "sudo rm -f '$old_repo'"
    fi

    run "mkdir -p '$fonts_dir'"
    run "curl -fL --progress-bar '$download_url' -o '$tmp_file'"
    run "tar -xf '$tmp_file' -C '$fonts_dir'"
    run "rm -f '$tmp_file'"

    # Reconstruir caché de fuentes
    run "fc-cache -fv"

    ok "JetBrainsMono Nerd Font instalada"
}

configure_wezterm_lua() {
    log "Configuración de WezTerm (~/.wezterm.lua)"

    local config_file="$HOME/.wezterm.lua"
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local source_file="$script_dir/wezterm.lua"

    if [[ ! -f "$source_file" ]]; then
        warn "No se encuentra $source_file junto al script. Saltando config de WezTerm."
        return 0
    fi

    if [[ -f "$config_file" ]]; then
        warn "Ya existe $config_file. Se guardará backup en ${config_file}.bak"
        run "cp \"$config_file\" \"${config_file}.bak\""
    fi

    run "cp \"$source_file\" \"$config_file\""
    ok "~/.wezterm.lua desplegado"
}

configure_wezterm_default() {
    log "WezTerm como terminal por defecto"

    local wezterm_bin
    wezterm_bin="$(command -v wezterm || echo /usr/bin/wezterm)"
    local desktop="${XDG_CURRENT_DESKTOP:-unknown}"

    if [[ "$desktop" == *"KDE"* ]]; then
        # --- KDE Plasma ---

        # 1) Terminal por defecto del sistema (Dolphin, menús contextuales, etc.)
        run "kwriteconfig6 --file kdeglobals --group General --key TerminalApplication '${wezterm_bin}'"
        run "kwriteconfig6 --file kdeglobals --group General --key TerminalEmulator '${wezterm_bin}'"
        run "kbuildsycoca6 --noincremental 2>/dev/null"

        # 2) Reasignar Ctrl+Alt+T: quitar de Konsole en kglobalshortcutsrc
        local kglobal="$HOME/.config/kglobalshortcutsrc"
        if [[ $DRY_RUN -eq 1 ]]; then
            printf '\033[1;35m[DRY ]\033[0m  Quitar Ctrl+Alt+T de Konsole en %s\n' "$kglobal"
        else
            if [[ -f "$kglobal" ]]; then
                # Reemplaza la línea _launch de Konsole para eliminar el atajo
                sed -i '/^\[org\.kde\.konsole\.desktop\]/,/^\[/{
                    s/^_launch=Ctrl+Alt+T,.*/_launch=none,none,Konsole/
                }' "$kglobal"
            fi
            # Reiniciar el demonio de atajos globales para que lea el cambio
            kquitapp6 kglobalaccel 2>/dev/null || true
            sleep 1
            kstart6 kglobalaccel 2>/dev/null &
        fi

        warn "Ctrl+Alt+T eliminado de Konsole. Para asignarlo a WezTerm:"
        warn "  Sistema → Atajos → Atajos globales → Añadir aplicación → WezTerm"

    else
        # --- GNOME y compatibles ---
        run "gsettings set org.gnome.desktop.default-applications.terminal exec '${wezterm_bin}'"
        run "gsettings set org.gnome.desktop.default-applications.terminal exec-arg ''"
    fi

    # Sistema de alternativas de Fedora (agnóstico al DE)
    run "sudo alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator '${wezterm_bin}' 100"
    run "sudo alternatives --set x-terminal-emulator '${wezterm_bin}'"

    ok "WezTerm configurado como terminal por defecto"
}

install_zsh() {
    log "zsh"

    if is_installed zsh; then
        ok "zsh ya instalado"
    else
        run "sudo dnf install -y zsh"
    fi

    # Establecer zsh como shell por defecto del usuario
    local zsh_path
    zsh_path="$(command -v zsh || echo /usr/bin/zsh)"

    local current_shell
    current_shell="$(getent passwd "$USER" | cut -d: -f7)"

    if [[ "$current_shell" == "$zsh_path" ]]; then
        ok "zsh ya es el shell por defecto"
    else
        run "sudo chsh -s \"$zsh_path\" \"$USER\""
        ok "zsh configurado como shell por defecto (efectivo en el próximo login)"
    fi
}

install_oh_my_zsh() {
    log "oh-my-zsh"

    local OMZ_DIR="${ZSH:-$HOME/.oh-my-zsh}"

    if [[ -d "$OMZ_DIR" ]]; then
        ok "oh-my-zsh ya instalado en $OMZ_DIR, saltando"
        return 0
    fi

    # Requisito: git (suele estar, pero garantizamos)
    if ! is_installed git; then
        run "sudo dnf install -y git"
    fi

    # --unattended: no hace chsh (ya lo hicimos en install_zsh) ni lanza zsh al final.
    # Si existe un ~/.zshrc previo, el instalador lo backupea como ~/.zshrc.pre-oh-my-zsh
    run 'sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended'

    ok "oh-my-zsh instalado (tema por defecto: robbyrussell)"
}

install_nvm() {
    log "nvm (Node Version Manager)"

    # Versión fijada para reproducibilidad. Última estable a fecha del script.
    # Comprobar nuevas versiones en https://github.com/nvm-sh/nvm/releases
    local NVM_VERSION="v0.40.4"
    local NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

    if [[ -d "$NVM_DIR" && -s "$NVM_DIR/nvm.sh" ]]; then
        ok "nvm ya instalado en $NVM_DIR, saltando"
        return 0
    fi

    # nvm detecta el rc a modificar a partir de $SHELL. Como este script
    # corre bajo bash, $SHELL=/bin/bash aunque ya hayamos hecho chsh a zsh.
    # Forzamos PROFILE al rc del shell *por defecto* (lo que dice /etc/passwd),
    # no al del shell actual del script.
    local target_profile=""
    local default_shell
    default_shell="$(getent passwd "$USER" | cut -d: -f7)"
    case "$default_shell" in
        */zsh)  target_profile="$HOME/.zshrc"  ;;
        */bash) target_profile="$HOME/.bashrc" ;;
    esac

    local install_cmd="curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh | bash"
    if [[ -n "$target_profile" ]]; then
        install_cmd="PROFILE=\"$target_profile\" $install_cmd"
    fi

    # SIN sudo: nvm es per-user, va al $HOME del usuario actual.
    run "$install_cmd"

    ok "nvm instalado. Abre un nuevo shell (o 'source ${target_profile:-tu rc}') y luego: nvm install --lts"
}

install_wezterm() {
    log "WezTerm"

    # El paquete virtual 'wezterm' del COPR está roto en Fedora 43+
    # (instala cero binarios). Hay que instalar los subpaquetes directamente.
    # Bug: https://github.com/wezterm/wezterm/issues/7502
    if is_installed wezterm-common; then
        ok "WezTerm ya instalado, saltando"
        return 0
    fi

    # 1) Descargar el .repo del COPR oficial (más fiable que 'dnf copr enable',
    #    que requiere el plugin dnf5-plugins y puede no estar disponible)
    local fedora_ver
    fedora_ver="$(rpm -E '%fedora')"
    local copr_repo_url="https://copr.fedorainfracloud.org/coprs/wezfurlong/wezterm-nightly/repo/fedora-${fedora_ver}/wezfurlong-wezterm-nightly-fedora-${fedora_ver}.repo"
    local repo_file="/etc/yum.repos.d/wezterm-nightly.repo"

    if [[ ! -f "$repo_file" ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            printf '\033[1;35m[DRY ]\033[0m  Descargar %s\n' "$copr_repo_url"
        else
            sudo wget -q "$copr_repo_url" -O "$repo_file"
        fi
    fi

    # 2) Instalar subpaquetes (el metapaquete 'wezterm' está roto en Fedora 43+).
    #    wezterm-gui incluye el .desktop para que aparezca en GNOME.
    run "sudo dnf install -y wezterm-common wezterm-mux-server wezterm-gui"

    ok "WezTerm instalado"
}

install_zsh_plugins() {
    log "zsh plugins (autosuggestions, syntax-highlighting, nvm)"

    local zsh_custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        warn "oh-my-zsh no encontrado, saltando plugins. ¿Has ejecutado install_oh_my_zsh?"
        return 0
    fi

    # --- Plugins externos (hay que clonar su repo) ---
    local ext_plugins=(
        "zsh-users/zsh-autosuggestions"
        "zsh-users/zsh-syntax-highlighting"
    )

    for repo in "${ext_plugins[@]}"; do
        local name="${repo##*/}"
        local target="$zsh_custom/plugins/$name"
        if [[ -d "$target" ]]; then
            ok "$name ya clonado, saltando"
        else
            run "git clone --depth=1 https://github.com/${repo}.git \"$target\""
        fi
    done

    # --- Activar plugins en .zshrc (idempotente: no duplica) ---
    # Incluye 'nvm' para carga lazy y auto-switch al entrar en dirs con .nvmrc
    local zshrc="$HOME/.zshrc"
    local plugins_to_enable=(nvm zsh-autosuggestions zsh-syntax-highlighting)

    for plugin in "${plugins_to_enable[@]}"; do
        if grep -qE "^plugins=\(.*\b${plugin}\b.*\)" "$zshrc" 2>/dev/null; then
            ok "Plugin '$plugin' ya activo en .zshrc"
        else
            if [[ $DRY_RUN -eq 1 ]]; then
                printf '\033[1;35m[DRY ]\033[0m  Añadir plugin %s a .zshrc\n' "$plugin"
            else
                sed -i "s/^plugins=(\(.*\))/plugins=(\1 ${plugin})/" "$zshrc"
            fi
        fi
    done

    ok "Plugins zsh configurados. Recarga el shell para activarlos."
}

install_node_lts() {
    log "Node.js LTS (vía nvm)"

    local NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

    if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
        warn "nvm no disponible, saltando Node LTS. ¿Has ejecutado install_nvm?"
        return 0
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        printf '\033[1;35m[DRY ]\033[0m  nvm install --lts && nvm alias default lts/*\n'
        return 0
    fi

    # Subshell aislado: nvm.sh no es compatible con set -euo pipefail
    NVM_DIR="$NVM_DIR" bash -c '
        . "$NVM_DIR/nvm.sh"
        if nvm ls 2>/dev/null | grep -q "lts/"; then
            echo "Node LTS ya instalado, saltando"
        else
            nvm install --lts
            nvm alias default "lts/*"
        fi
    '

    ok "Node LTS instalado y configurado como default"
}

install_starship() {
    log "Starship"

    if command -v starship &>/dev/null; then
        ok "Starship ya instalado ($(starship --version | head -1)), saltando"
        return 0
    fi

    # Instalador oficial: descarga el binario a /usr/local/bin
    # SIN sudo en el comando principal; el instalador lo pide internamente si es necesario
    run 'curl -sS https://starship.rs/install.sh | sh -s -- --yes'

    ok "Starship instalado"
}

configure_starship() {
    log "Configuración de Starship"

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local source_toml="$script_dir/starship.toml"
    local zshrc="$HOME/.zshrc"
    local config_dir="$HOME/.config"
    local target_toml="$config_dir/starship.toml"

    # 1) Desplegar starship.toml
    if [[ ! -f "$source_toml" ]]; then
        warn "No se encuentra $source_toml junto al script. Saltando config de Starship."
    else
        run "mkdir -p '$config_dir'"
        if [[ -f "$target_toml" ]]; then
            warn "Ya existe $target_toml. Se guardará backup en ${target_toml}.bak"
            run "cp '$target_toml' '${target_toml}.bak'"
        fi
        run "cp '$source_toml' '$target_toml'"
        ok "~/.config/starship.toml desplegado"
    fi

    # 2) Desactivar tema de oh-my-zsh para que no compita con starship
    if [[ $DRY_RUN -eq 1 ]]; then
        printf '\033[1;35m[DRY ]\033[0m  Desactivar ZSH_THEME en .zshrc\n'
    else
        # Cambia cualquier ZSH_THEME="algo" por ZSH_THEME="" 
        sed -i 's/^ZSH_THEME="[^"]*"/ZSH_THEME=""/' "$zshrc"
    fi

    # 3) Añadir eval de starship al .zshrc (idempotente)
    local init_line='eval "$(starship init zsh)"'
    if grep -qF "$init_line" "$zshrc" 2>/dev/null; then
        ok "Starship ya inicializado en .zshrc"
    else
        if [[ $DRY_RUN -eq 1 ]]; then
            printf '\033[1;35m[DRY ]\033[0m  Añadir eval starship a .zshrc\n'
        else
            printf '\n# Starship prompt\n%s\n' "$init_line" >> "$zshrc"
        fi
    fi

    ok "Starship configurado"
}

# ---------- Plantilla para añadir nuevas apps ----------
#
# install_<app>() {
#     log "<App>"
#     if is_installed <paquete>; then
#         ok "<App> ya instalado, saltando"
#         return 0
#     fi
#     run "sudo dnf install -y <paquete>"
#     ok "<App> instalado"
# }
#
# Y luego añadir la llamada en main()

# ---------- Main ----------
main() {
    require_dnf5

    [[ $DRY_RUN -eq 1 ]] && warn "Modo dry-run: no se ejecutará nada"

    install_chrome
    install_vscode
    install_wezterm
    install_nerd_fonts
    configure_wezterm_lua
    configure_wezterm_default
    install_zsh
    install_oh_my_zsh
    install_nvm
    install_zsh_plugins   # después de nvm: activa el plugin nvm en .zshrc
    install_node_lts      # después de nvm: necesita nvm.sh disponible
    install_starship
    configure_starship    # después de oh-my-zsh: modifica .zshrc
    # install_<otra_app>

    ok "Setup completado"
}

main "$@"
