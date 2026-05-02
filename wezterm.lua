-- ~/.wezterm.lua
-- Config orientada a workflow con agentes (Claude Code, OpenCode, etc.)
-- Filosofía: tabs por proyecto, splits por agente dentro de cada tab

local wezterm = require("wezterm")
local act = wezterm.action
local config = wezterm.config_builder()

-- ─────────────────────────────────────────────
-- LEADER KEY
-- Ctrl+A (al estilo tmux). Espera 1s el siguiente comando.
-- ─────────────────────────────────────────────
config.leader = {
  key = "a",
  mods = "CTRL",
  timeout_milliseconds = 1000,
}

-- ─────────────────────────────────────────────
-- SHELL
-- ─────────────────────────────────────────────
config.default_prog = { "/usr/bin/zsh", "-l" }

-- ─────────────────────────────────────────────
-- RENDIMIENTO Y SCROLLBACK
-- 100k líneas: agentes generan mucho output
-- ─────────────────────────────────────────────
config.scrollback_lines = 100000
config.scroll_to_bottom_on_input = true

-- ─────────────────────────────────────────────
-- APARIENCIA
-- ─────────────────────────────────────────────
config.color_scheme = "Tokyo Night"

config.font = wezterm.font_with_fallback({
  { family = "JetBrainsMono Nerd Font", weight = "Regular" },
  { family = "FiraCode Nerd Font",      weight = "Regular" },
  "Noto Color Emoji",
})
config.font_size = 12.0

-- Sin barra de título nativa: más espacio para contenido
config.window_decorations = "RESIZE"

-- Padding interior
config.window_padding = { left = 8, right = 8, top = 8, bottom = 8 }

-- Tab bar en la parte superior
config.tab_bar_at_bottom = false
config.use_fancy_tab_bar = true
config.hide_tab_bar_if_only_one_tab = false

-- Renombra la tab con el título del proceso activo
config.tab_max_width = 32

-- ─────────────────────────────────────────────
-- KEYBINDINGS
-- Convención:
--   LEADER + <key>  →  acciones de splits/paneles
--   CTRL+SHIFT+<k>  →  acciones de tabs y ventana
-- ─────────────────────────────────────────────
config.keys = {

  -- ── Splits ──────────────────────────────────
  -- LEADER + | → split vertical (panel a la derecha)
  {
    key = "|", mods = "LEADER",
    action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }),
  },
  -- LEADER + - → split horizontal (panel debajo)
  {
    key = "-", mods = "LEADER",
    action = act.SplitVertical({ domain = "CurrentPaneDomain" }),
  },

  -- ── Navegación entre paneles (estilo vim) ───
  { key = "h", mods = "LEADER", action = act.ActivatePaneDirection("Left")  },
  { key = "l", mods = "LEADER", action = act.ActivatePaneDirection("Right") },
  { key = "k", mods = "LEADER", action = act.ActivatePaneDirection("Up")    },
  { key = "j", mods = "LEADER", action = act.ActivatePaneDirection("Down")  },

  -- ── Zoom (focus en un panel) ─────────────────
  -- LEADER + z → zoom toggle al panel activo
  {
    key = "z", mods = "LEADER",
    action = act.TogglePaneZoomState,
  },

  -- ── Redimensionar paneles ────────────────────
  { key = "H", mods = "LEADER|SHIFT", action = act.AdjustPaneSize({ "Left",  5 }) },
  { key = "L", mods = "LEADER|SHIFT", action = act.AdjustPaneSize({ "Right", 5 }) },
  { key = "K", mods = "LEADER|SHIFT", action = act.AdjustPaneSize({ "Up",    5 }) },
  { key = "J", mods = "LEADER|SHIFT", action = act.AdjustPaneSize({ "Down",  5 }) },

  -- ── Tabs ────────────────────────────────────
  { key = "c", mods = "LEADER",       action = act.SpawnTab("CurrentPaneDomain") },
  { key = "w", mods = "LEADER",       action = act.ShowTabNavigator               },
  { key = "n", mods = "LEADER",       action = act.ActivateTabRelative(1)          },
  { key = "p", mods = "LEADER",       action = act.ActivateTabRelative(-1)         },
  -- Renombrar tab actual
  {
    key = "r", mods = "LEADER",
    action = act.PromptInputLine({
      description = "Renombrar tab:",
      action = wezterm.action_callback(function(win, _, line)
        if line then win:active_tab():set_title(line) end
      end),
    }),
  },

  -- ── Workspaces (sesiones persistentes) ──────
  -- LEADER + S → selector de workspaces
  { key = "S", mods = "LEADER", action = act.ShowLauncherArgs({ flags = "WORKSPACES" }) },
  -- LEADER + N → crear nuevo workspace con nombre
  {
    key = "N", mods = "LEADER",
    action = act.PromptInputLine({
      description = "Nombre del workspace:",
      action = wezterm.action_callback(function(win, _, line)
        if line and line ~= "" then
          win:perform_action(
            act.SwitchToWorkspace({ name = line }),
            win:active_pane()
          )
        end
      end),
    }),
  },

  -- ── Utilidades ──────────────────────────────
  -- Copiar selección al portapapeles
  { key = "c", mods = "CTRL|SHIFT", action = act.CopyTo("Clipboard") },
  -- Pegar
  { key = "v", mods = "CTRL|SHIFT", action = act.PasteFrom("Clipboard") },
  -- Buscar en scrollback
  { key = "f", mods = "CTRL|SHIFT", action = act.Search({ CaseSensitiveString = "" }) },
  -- Aumentar/reducir fuente
  { key = "+", mods = "CTRL",       action = act.IncreaseFontSize },
  { key = "-", mods = "CTRL",       action = act.DecreaseFontSize },
  { key = "0", mods = "CTRL",       action = act.ResetFontSize    },
}

-- ─────────────────────────────────────────────
-- MOUSE
-- ─────────────────────────────────────────────
-- Clic derecho pega (cómodo cuando el agente produce texto copiable)
config.mouse_bindings = {
  {
    event  = { Down = { streak = 1, button = "Right" } },
    mods   = "NONE",
    action = act.PasteFrom("Clipboard"),
  },
}

-- ─────────────────────────────────────────────
-- HIPERLINKS
-- Detecta URLs y referencias de GitHub automáticamente
-- ─────────────────────────────────────────────
config.hyperlink_rules = wezterm.default_hyperlink_rules()
-- Rutas de archivo absolutas también son clickables
table.insert(config.hyperlink_rules, {
  regex = [[\b(/[a-zA-Z0-9_./-]+)\b]],
  format = "file://$1",
})

-- ─────────────────────────────────────────────
-- COMPORTAMIENTO
-- ─────────────────────────────────────────────
-- Confirmación antes de cerrar si hay procesos corriendo
config.window_close_confirmation = "AlwaysPrompt"
-- Audible bell desactivado (los agentes generan muchos)
config.audible_bell = "Disabled"
-- Visual bell también
config.visual_bell = {
  fade_in_duration_ms  = 0,
  fade_out_duration_ms = 0,
  target               = "CursorColor",
}

return config
