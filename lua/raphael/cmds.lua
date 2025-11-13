local M = {}

local themes = require("raphael.themes")
local picker = require("raphael.picker")
local history = require("raphael.theme_history")

---@param core table The main Raphael core instance
function M.setup(core)
  vim.api.nvim_create_user_command("RaphaelToggleAuto", function()
    core.toggle_auto()
  end, { desc = "Toggle auto-apply by filetype" })

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

    core.apply(theme, true)
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
  end, { desc = "Show current theme status" })

  vim.api.nvim_create_user_command("RaphaelHelp", function()
    core.show_help()
  end, { desc = "Show Raphael help" })

  vim.api.nvim_create_user_command("RaphaelDebug", function()
    picker.toggle_debug()
  end, { desc = "Toggle picker debug mode" })

  vim.api.nvim_create_user_command("RaphaelAnim", function()
    picker.toggle_animations()
  end, { desc = "Toggle picker animations" })

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
        core.toggle_bookmark(core.picker.get_current_theme())
      end, 50)
    else
      core.toggle_bookmark(core.picker.get_current_theme())
    end
  end, { desc = "Toggle bookmark for the theme under the cursor" })
end

return M
