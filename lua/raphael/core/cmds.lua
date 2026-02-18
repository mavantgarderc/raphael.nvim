-- lua/raphael/core/cmds.lua
-- User commands for raphael.nvim:
--   :RaphaelPicker, :RaphaelApply, :RaphaelToggleAuto, :RaphaelUndo, :RaphaelRedo, etc.
--
-- This module is intentionally thin:
--   - It defines Neovim :commands and delegates all logic to:
--       * raphael.core           (apply, toggle_auto, open_picker, etc.)
--       * raphael.themes         (theme discovery / availability)
--       * raphael.extras.history (undo/redo + stats)
--       * raphael.picker.ui      (picker UI, palette stats, debug toggles)
--   - It does NOT own any persistent state.

local M = {}

local themes = require("raphael.themes")
local picker = require("raphael.picker.ui")
local history = require("raphael.extras.history")

--- Setup user commands that depend on the core orchestrator.
---
--- Commands defined:
---   - :RaphaelToggleAuto
---   - :RaphaelPicker
---   - :RaphaelPickerAll
---   - :RaphaelApply {theme}
---   - :RaphaelRefresh
---   - :RaphaelStatus
---   - :RaphaelHelp
---   - :RaphaelDebug
---   - :RaphaelCacheStats
---   - :RaphaelHistory
---   - :RaphaelUndo
---   - :RaphaelRedo
---   - :RaphaelRandom
---   - :RaphaelBookmarkToggle
---   - :RaphaelProfile [name] [edit]
---   - :RaphaelProfileInfo [name]
---
---@param core table  # usually require("raphael.core")
function M.setup(core)
  vim.api.nvim_create_user_command("RaphaelToggleAuto", function()
    core.toggle_auto()
  end, { desc = "Toggle auto-apply by filetype/project" })

  vim.api.nvim_create_user_command("RaphaelPicker", function()
    core.open_picker({ only_configured = true })
  end, { desc = "Open theme picker (configured themes)" })

  vim.api.nvim_create_user_command("RaphaelPickerAll", function()
    core.open_picker({ exclude_configured = true })
  end, { desc = "Open theme picker (all except configured)" })

  vim.api.nvim_create_user_command("RaphaelApply", function(opts)
    local theme = opts.args
    if not theme or theme == "" then
      vim.notify("Raphael: No theme name provided", vim.log.levels.WARN)
      return
    end

    local resolved = core.config.theme_aliases[theme] or theme
    if not themes.is_available(resolved) then
      vim.notify(string.format("Raphael: Theme '%s' is not installed or available", resolved), vim.log.levels.WARN)
      return
    end

    core.apply(resolved, true)
  end, {
    nargs = 1,
    complete = function(ArgLead)
      local candidates = themes.get_all_themes()

      local alias_map = core.config.theme_aliases or {}
      local all_candidates = vim.deepcopy(candidates)

      for alias, real in pairs(alias_map) do
        if vim.tbl_contains(candidates, real) then
          table.insert(all_candidates, alias .. " → " .. real)
        end
      end

      if ArgLead and ArgLead ~= "" then
        return vim
          .iter(candidates)
          :filter(function(t)
            return t:lower():find(ArgLead:lower(), 1, true)
          end)
          :totable()
      end
      return candidates
    end,
    desc = "Apply a theme by name",
  })

  vim.api.nvim_create_user_command("RaphaelRefresh", function()
    core.refresh_and_reload()
  end, { desc = "Refresh theme list and reload current" })

  vim.api.nvim_create_user_command("RaphaelStatus", function()
    core.show_status()
  end, { desc = "Show current theme/profile status" })

  vim.api.nvim_create_user_command("RaphaelHelp", function()
    core.show_help()
  end, { desc = "Show Raphael help" })

  vim.api.nvim_create_user_command("RaphaelDebug", function()
    picker.toggle_debug()
  end, { desc = "Toggle picker debug mode" })

  vim.api.nvim_create_user_command("RaphaelCacheStats", function()
    local stats = picker.get_cache_stats()
    vim.notify(
      string.format(
        "Raphael Cache: %d palette entries | %d active timers",
        stats.palette_cache_size,
        stats.active_timers
      ),
      vim.log.levels.INFO
    )
  end, { desc = "Show picker palette-cache stats" })

  vim.api.nvim_create_user_command("RaphaelHistory", function()
    history.show()
  end, { desc = "Show full theme history" })

  vim.api.nvim_create_user_command("RaphaelUndo", function()
    local theme = history.undo(function(t)
      core.apply(t, false)
    end)
    if theme then
      vim.notify("Undid to: " .. theme, vim.log.levels.INFO)
    end
  end, { desc = "Undo last theme change" })

  vim.api.nvim_create_user_command("RaphaelRedo", function()
    local theme = history.redo(function(t)
      core.apply(t, false)
    end)
    if theme then
      vim.notify("Redid to: " .. theme, vim.log.levels.INFO)
    end
  end, { desc = "Redo last undone theme change" })

  vim.api.nvim_create_user_command("RaphaelRandom", function()
    local all = themes.get_all_themes()
    if #all == 0 then
      vim.notify("No themes available", vim.log.levels.WARN)
      return
    end
    math.randomseed(os.time())
    local theme = all[math.random(#all)]
    if themes.is_available(theme) then
      core.apply(theme, true)
      vim.notify("Random theme: " .. theme, vim.log.levels.INFO)
    else
      vim.notify("Random theme not installed", vim.log.levels.WARN)
    end
  end, { desc = "Apply a random theme" })

  vim.api.nvim_create_user_command("RaphaelBookmarkToggle", function()
    if not picker.is_open() then
      vim.notify("Picker not open – opening it first…", vim.log.levels.INFO)
      core.open_picker({ only_configured = true })
      vim.defer_fn(function()
        core.toggle_bookmark(picker.get_current_theme())
      end, 50)
    else
      core.toggle_bookmark(picker.get_current_theme())
    end
  end, { desc = "Toggle bookmark for the theme under the cursor" })

  local function list_profiles()
    local base_cfg = core.base_config or {}
    local profiles = base_cfg.profiles or {}
    local current = core.get_current_profile and core.get_current_profile() or nil

    local function has_nonempty_table(t)
      return type(t) == "table" and next(t) ~= nil
    end

    local function has_overrides_for(name)
      if name == "base" then
        return has_nonempty_table(base_cfg.filetype_themes)
          or has_nonempty_table(base_cfg.project_themes)
          or has_nonempty_table(base_cfg.theme_map)
      end
      local prof = profiles[name]
      if type(prof) ~= "table" then
        return false
      end
      return has_nonempty_table(prof.filetype_themes)
        or has_nonempty_table(prof.project_themes)
        or has_nonempty_table(prof.theme_map)
    end

    local names = {}
    for pname, _ in pairs(profiles) do
      table.insert(names, pname)
    end
    table.sort(names)

    local lines = { "raphael profiles:", "" }

    local base_mark_cur = current == nil and "*" or ""
    local base_mark_ovr = has_overrides_for("base") and "+" or ""
    table.insert(lines, string.format("  - base%s%s", base_mark_cur, base_mark_ovr))

    for _, pname in ipairs(names) do
      local marks = ""
      if pname == current then
        marks = marks .. "*"
      end
      if has_overrides_for(pname) then
        marks = marks .. "+"
      end
      table.insert(lines, string.format("  - %s%s", pname, marks))
    end

    table.insert(lines, "")
    table.insert(lines, "Legend: * current | + overrides (filetype/project/theme_map)")

    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
  end

  vim.api.nvim_create_user_command("RaphaelProfile", function(opts)
    local args = vim.trim(opts.args or "")
    local bang = opts.bang

    local base_cfg = core.base_config or {}
    local profiles = (base_cfg and base_cfg.profiles) or {}

    if args == "" then
      if not profiles or vim.tbl_isempty(profiles) then
        vim.notify("raphael: no profiles configured", vim.log.levels.INFO)
        return
      end
      list_profiles()
      return
    end

    local parts = vim.split(args, "%s+")
    local name = parts[1]
    local subcmd = parts[2]

    if name == "base" or name == "default" then
      name = nil
    end

    if subcmd == "edit" then
      if not core.get_profile_config then
        vim.notify("raphael: core.get_profile_config not available", vim.log.levels.ERROR)
        return
      end

      local cfg = core.get_profile_config(name)
      if not cfg then
        vim.notify("raphael: unknown profile for edit: " .. tostring(name or "base"), vim.log.levels.WARN)
        return
      end

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
      vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })

      local label = name or "base"
      vim.api.nvim_buf_set_name(buf, "RaphaelProfile:" .. label)

      local header = string.format("-- Raphael effective profile config: %s", label)
      local body = vim.split(vim.inspect(cfg), "\n")
      table.insert(body, 1, header)

      vim.api.nvim_buf_set_lines(buf, 0, -1, false, body)
      vim.api.nvim_set_option_value("filetype", "lua", { buf = buf })

      vim.api.nvim_win_set_buf(0, buf)
      return
    end

    local apply_default = not bang

    if name ~= nil and type(profiles[name]) ~= "table" then
      vim.notify(string.format("raphael: unknown profile '%s'", name), vim.log.levels.WARN)
      return
    end

    if core.set_profile then
      core.set_profile(name, apply_default)
    else
      vim.notify("raphael: core.set_profile not available", vim.log.levels.ERROR)
    end
  end, {
    nargs = "*",
    bang = true,
    complete = function(ArgLead)
      local base_cfg = core.base_config or {}
      local profiles = base_cfg.profiles or {}
      local names = {}

      for pname, _ in pairs(profiles) do
        table.insert(names, pname)
      end
      table.sort(names)
      table.insert(names, 1, "base")

      if not ArgLead or ArgLead == "" then
        return names
      end

      local res = {}
      local needle = ArgLead:lower()
      for _, n in ipairs(names) do
        if n:lower():find(needle, 1, true) then
          table.insert(res, n)
        end
      end
      return res
    end,
    desc = "Switch Raphael theme profile (:RaphaelProfile[!] [name] [edit])",
  })

  local function diff_table(base_tbl, prof_tbl, path, out)
    path = path or ""
    out = out or {}

    if type(base_tbl) ~= "table" or type(prof_tbl) ~= "table" then
      return out
    end

    local seen = {}

    for k, v in pairs(base_tbl) do
      seen[k] = true
      local new_path = path == "" and tostring(k) or (path .. "." .. tostring(k))
      local ov = prof_tbl[k]
      if ov == nil then
        table.insert(out, string.format("- %s: removed (base=%s)", new_path, vim.inspect(v)))
      else
        if type(v) == "table" and type(ov) == "table" then
          diff_table(v, ov, new_path, out)
        elseif vim.inspect(v) ~= vim.inspect(ov) then
          table.insert(out, string.format("~ %s: base=%s, profile=%s", new_path, vim.inspect(v), vim.inspect(ov)))
        end
      end
    end

    for k, v in pairs(prof_tbl) do
      if not seen[k] then
        local new_path = path == "" and tostring(k) or (path .. "." .. tostring(k))
        table.insert(out, string.format("+ %s: profile=%s", new_path, vim.inspect(v)))
      end
    end

    return out
  end

  vim.api.nvim_create_user_command("RaphaelProfileInfo", function(opts)
    local base_cfg = core.base_config or {}
    local profiles = base_cfg.profiles or {}
    local name = vim.trim(opts.args or "")

    if name == "" then
      name = core.get_current_profile and core.get_current_profile() or nil
    elseif name == "base" or name == "default" then
      name = nil
    end

    if name ~= nil and type(profiles[name]) ~= "table" then
      vim.notify(string.format("raphael: unknown profile '%s'", name), vim.log.levels.WARN)
      return
    end

    if not core.get_profile_config then
      vim.notify("raphael: core.get_profile_config not available", vim.log.levels.ERROR)
      return
    end

    local base_eff = core.get_profile_config(nil) or base_cfg
    local prof_eff = core.get_profile_config(name)
    if not prof_eff then
      vim.notify("raphael: no effective config for profile " .. tostring(name or "base"), vim.log.levels.WARN)
      return
    end

    local diff_lines = diff_table(base_eff, prof_eff)
    local label = name or "base"

    if #diff_lines == 0 then
      vim.notify(string.format("raphael: profile '%s' has no differences vs base", label), vim.log.levels.INFO)
      return
    end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })

    vim.api.nvim_buf_set_name(buf, "RaphaelProfileInfo:" .. label)

    local header = {
      string.format("-- Raphael profile diff vs base: %s", label),
      "-- Legend: + added | - removed | ~ changed",
      "",
    }

    local lines = {}
    vim.list_extend(lines, header)
    vim.list_extend(lines, diff_lines)

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_option_value("filetype", "lua", { buf = buf })
    vim.api.nvim_win_set_buf(0, buf)
  end, {
    nargs = "?",
    complete = function(ArgLead)
      local base_cfg = core.base_config or {}
      local profiles = base_cfg.profiles or {}
      local names = {}

      for pname, _ in pairs(profiles) do
        table.insert(names, pname)
      end
      table.sort(names)
      table.insert(names, 1, "base")

      if not ArgLead or ArgLead == "" then
        return names
      end

      local res = {}
      local needle = ArgLead:lower()
      for _, n in ipairs(names) do
        if n:lower():find(needle, 1, true) then
          table.insert(res, n)
        end
      end
      return res
    end,
    desc = "Show diff of profile vs base (:RaphaelProfileInfo [name])",
  })

  local config_manager = require("raphael.config_manager")

  vim.api.nvim_create_user_command("RaphaelConfigExport", function(opts)
    local export_path = opts.args ~= "" and opts.args
      or vim.fn.stdpath("config") .. "/raphael/configs/exported_config.json"
    local config_to_export = config_manager.export_config(core)

    if not config_to_export then
      vim.notify("raphael: failed to export configuration", vim.log.levels.ERROR)
      return
    end

    if config_manager.save_config_to_file(config_to_export, export_path) then
      vim.notify("raphael: configuration exported to " .. export_path, vim.log.levels.INFO)
    end
  end, {
    nargs = "?",
    desc = "Export current Raphael configuration to a file",
  })

  vim.api.nvim_create_user_command("RaphaelConfigImport", function(opts)
    if opts.args == "" then
      vim.notify("raphael: please specify a config file path to import", vim.log.levels.WARN)
      return
    end

    local imported_config = config_manager.import_config_from_file(opts.args)
    if not imported_config then
      vim.notify("raphael: failed to import configuration from " .. opts.args, vim.log.levels.ERROR)
      return
    end

    local is_valid, error_msg = config_manager.validate_config(imported_config)
    if not is_valid then
      vim.notify("raphael: imported config is invalid: " .. error_msg, vim.log.levels.ERROR)
      return
    end

    core.base_config = imported_config
    local profile_name = core.state.current_profile
    core.config = core.get_profile_config(profile_name) or imported_config

    vim.notify("raphael: configuration imported and applied from " .. opts.args, vim.log.levels.INFO)
  end, {
    nargs = 1,
    desc = "Import Raphael configuration from a file",
  })

  vim.api.nvim_create_user_command("RaphaelConfigValidate", function()
    local diagnostics = config_manager.get_config_diagnostics(core.base_config)
    local validation_results = config_manager.validate_config_sections(core.base_config)

    local lines = { "Raphael Configuration Validation:", "" }

    table.insert(lines, string.format("Total keys: %d", diagnostics.total_keys))
    table.insert(lines, string.format("Unknown keys: %d", #diagnostics.unknown_keys))
    if #diagnostics.unknown_keys > 0 then
      for _, key in ipairs(diagnostics.unknown_keys) do
        table.insert(lines, string.format("  - %s", key))
      end
    end
    table.insert(lines, string.format("Missing defaults: %d", #diagnostics.missing_defaults))
    if #diagnostics.missing_defaults > 0 then
      for _, key in ipairs(diagnostics.missing_defaults) do
        table.insert(lines, string.format("  - %s", key))
      end
    end

    table.insert(lines, "")
    table.insert(lines, "Section validation:")
    for section, is_valid in pairs(validation_results) do
      if type(is_valid) == "boolean" then
        local status = is_valid and "✓" or "✗"
        table.insert(lines, string.format("  %s %s", status, section))
      end
    end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
    vim.api.nvim_buf_set_name(buf, "RaphaelConfigValidate")

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_option_value("filetype", "text", { buf = buf })
    vim.api.nvim_win_set_buf(0, buf)
  end, {
    desc = "Validate current Raphael configuration",
  })

  vim.api.nvim_create_user_command("RaphaelConfigList", function()
    local config_files = config_manager.list_config_files()

    if #config_files == 0 then
      vim.notify("raphael: no config files found in ~/.config/nvim/raphael/configs/", vim.log.levels.INFO)
      return
    end

    local lines = { "Available Raphael configuration files:", "" }
    for _, file in ipairs(config_files) do
      table.insert(lines, file)
    end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
    vim.api.nvim_buf_set_name(buf, "RaphaelConfigList")

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_option_value("filetype", "text", { buf = buf })
    vim.api.nvim_win_set_buf(0, buf)
  end, {
    desc = "List available Raphael configuration files",
  })

  vim.api.nvim_create_user_command("RaphaelConfigPreset", function(opts)
    local preset_name = opts.args
    if preset_name == "" or not preset_name then
      local presets = config_manager.get_presets()
      local preset_names = {}
      for name, _ in pairs(presets) do
        table.insert(preset_names, name)
      end

      local lines = { "Available Raphael configuration presets:", "" }
      for _, name in ipairs(preset_names) do
        table.insert(lines, "- " .. name)
      end

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
      vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
      vim.api.nvim_buf_set_name(buf, "RaphaelConfigPreset")

      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.api.nvim_set_option_value("filetype", "text", { buf = buf })
      vim.api.nvim_win_set_buf(0, buf)
      return
    end

    config_manager.apply_preset(preset_name, core)
  end, {
    nargs = "?",
    complete = function(ArgLead)
      local presets = config_manager.get_presets()
      local names = {}
      for name, _ in pairs(presets) do
        table.insert(names, name)
      end

      if not ArgLead or ArgLead == "" then
        return names
      end

      local res = {}
      local needle = ArgLead:lower()
      for _, n in ipairs(names) do
        if n:lower():find(needle, 1, true) then
          table.insert(res, n)
        end
      end
      return res
    end,
    desc = "Apply a Raphael configuration preset (:RaphaelConfigPreset [preset_name])",
  })
end

return M
