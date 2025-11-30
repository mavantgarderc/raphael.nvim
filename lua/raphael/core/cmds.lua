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
    if not core.picker or not core.picker.picker_win or not vim.api.nvim_win_is_valid(core.picker.picker_win) then
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

    local apply_default = not bang -- :RaphaelProfile! name => don't apply default theme

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
end

return M
