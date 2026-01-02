-- lua/raphael/init.lua
-- Public entrypoint for raphael.nvim:
--   - setup() with user configuration
--   - wires global autocmds, commands, and keymaps
--   - exposes a small public API that forwards to raphael.core

local M = {}

local core = require("raphael.core")
local config = require("raphael.config")

--- Validated configuration (after config.validate()).
---
--- This is set during M.setup() and then used by M.open_picker()
--- to decide whether the picker is enabled.
---@type table|nil
M.config = nil

--- Apply a theme by name.
---
--- This is a thin wrapper over core.apply().
--- `from_manual` controls whether the change participates in history,
--- saved theme, etc.
---
---@param theme string
---@param from_manual boolean|nil
function M.apply(theme, from_manual)
  return core.apply(theme, from_manual)
end

--- Toggle auto-apply for BufEnter/FileType.
---
--- Delegates to core.toggle_auto().
function M.toggle_auto()
  return core.toggle_auto()
end

--- Toggle bookmark for a theme.
---
--- Delegates to core.toggle_bookmark().
---
---@param theme string
function M.toggle_bookmark(theme)
  return core.toggle_bookmark(theme)
end

--- Refresh theme list and re-apply current theme.
---
--- Delegates to core.refresh_and_reload().
function M.refresh_and_reload()
  return core.refresh_and_reload()
end

--- Show current theme status.
---
--- Delegates to core.show_status().
function M.show_status()
  return core.show_status()
end

--- Export session snippet for Raphael theme persistence.
---
--- Delegates to core.export_for_session().
---
---@return string
function M.export_for_session()
  return core.export_for_session()
end

--- Restore theme from session variables (if present).
---
--- Delegates to core.restore_from_session().
function M.restore_from_session()
  return core.restore_from_session()
end

--- Add a theme to "recent" history (mostly kept for compatibility).
---
--- Delegates to core.add_to_history().
---
---@param theme string
function M.add_to_history(theme)
  return core.add_to_history(theme)
end

--- Open the theme picker, if enabled in config.
---
--- If `enable_picker` is false in the validated config, this emits a
--- warning and does nothing.
---
---@param opts table|nil
function M.open_picker(opts)
  if not M.config or not M.config.enable_picker then
    vim.notify("raphael: picker disabled in config", vim.log.levels.WARN)
    return
  end
  return core.open_picker(opts or {})
end

--- Get the currently active theme name (or nil).
---
---@return string|nil
function M.get_current_theme()
  return core.get_current_theme()
end

--- Get the currently active profile name (or nil).
---
---@return string|nil
function M.get_current_profile()
  return core.get_current_profile()
end

--- Get information about the current profile (for statusline, etc.).
---
--- @return table  See core.get_profile_info() for structure.
function M.get_profile_info()
  return core.get_profile_info()
end

--- Small helper for statusline components.
---
--- Returns a short string like:
---   "󰉼 kanagawa-paper-edo [work]"
--- or, if no profile:
---   "󰉼 kanagawa-paper-edo"
---
---@return string
function M.statusline()
  local theme = core.get_current_theme() or "none"
  local profile = core.get_current_profile()
  if profile then
    return string.format("󰉼 %s [%s]", theme, profile)
  end
  return "󰉼 " .. theme
end

--- Export current configuration to a file.
---
--- @param file_path string|nil Path to export configuration to (optional)
--- @return boolean success Whether the export was successful
function M.export_config(file_path)
  local config_manager = require("raphael.config_manager")
  local config_to_export = config_manager.export_config(core)

  if not config_to_export then
    return false
  end

  return config_manager.save_config_to_file(
    config_to_export,
    file_path or vim.fn.stdpath("config") .. "/raphael/configs/exported_config.json"
  )
end

--- Import configuration from a file and apply it.
---
--- @param file_path string Path to import configuration from
--- @return boolean success Whether the import was successful
function M.import_config(file_path)
  local config_manager = require("raphael.config_manager")
  local imported_config = config_manager.import_config_from_file(file_path)

  if not imported_config then
    return false
  end

  local is_valid, error_msg = config_manager.validate_config(imported_config)
  if not is_valid then
    vim.notify("raphael: imported config is invalid: " .. error_msg, vim.log.levels.ERROR)
    return false
  end

  core.base_config = imported_config
  local profile_name = core.state.current_profile
  core.config = core.get_profile_config(profile_name) or imported_config

  return true
end

--- Apply a configuration preset.
---
--- @param preset_name string Name of the preset to apply
--- @return boolean success Whether the preset was applied successfully
function M.apply_preset(preset_name)
  local config_manager = require("raphael.config_manager")
  return config_manager.apply_preset(preset_name, core)
end

--- Validate current configuration.
---
--- @return table results Validation results
function M.validate_config()
  local config_manager = require("raphael.config_manager")
  return config_manager.validate_config_sections(M.config or {})
end

-- ────────────────────────────────────────────────────────────────────────
-- Setup
-- ────────────────────────────────────────────────────────────────────────

--- Setup raphael.nvim with user configuration.
---
--- Responsibilities:
---   1. Validate and normalize user config via raphael.config.validate()
---   2. Initialize core orchestrator (raphael.core.setup)
---   3. Attach:
---        - core.autocmds (if enable_autocmds)
---        - core.cmds     (if enable_commands)
---        - core.keymaps_global (if enable_keymaps)
---
--- Typical usage:
---   require("raphael").setup({
---     default_theme = "kanagawa-paper-edo",
---     theme_map     = { ... },
---     icons         = { BOOKMARK = "★ " },
---   })
---
---@param user_config table|nil
function M.setup(user_config)
  M.config = config.validate(user_config or {})

  core.setup(M.config)

  if M.config.enable_autocmds ~= false then
    local autocmds = require("raphael.core.autocmds")
    autocmds.setup(core)
  end

  if M.config.enable_commands ~= false then
    local cmds = require("raphael.core.cmds")
    cmds.setup(core)
  end

  if M.config.enable_keymaps ~= false then
    local keymaps = require("raphael.core.keymaps_global")
    keymaps.setup(core)
  end
end

return M
