-- lua/raphael/core/cmds.lua
--- User commands: :RaphaelPicker, :RaphaelApply, :RaphaelToggleAuto, etc.

local M = {}

local cache = require("raphael.core.cache")
local utils = require("raphael.utils")
local config = require("raphael.config")

--- Setup all Raphael user commands
function M.setup()
  -- Toggle auto-apply by filetype
  vim.api.nvim_create_user_command("RaphaelToggleAuto", function()
    local enabled = cache.get_auto_apply()
    cache.set_auto_apply(not enabled)

    local status = not enabled and "enabled" or "disabled"
    utils.notify("Auto-apply " .. status, vim.log.levels.INFO, config.get())
  end, { desc = "Toggle auto-apply by filetype" })

  -- Open picker with configured themes
  vim.api.nvim_create_user_command("RaphaelPicker", function()
    require("raphael.picker.ui").open({ only_configured = true })
  end, { desc = "Open theme picker (configured themes)" })

  -- Open picker with all other themes
  vim.api.nvim_create_user_command("RaphaelPickerAll", function()
    require("raphael.picker.ui").open({ only_configured = false })
  end, { desc = "Open theme picker (all themes)" })

  -- Apply a theme by name
  vim.api.nvim_create_user_command("RaphaelApply", function(opts)
    local theme = opts.args
    if not theme or theme == "" then
      utils.notify("No theme name provided", vim.log.levels.WARN, config.get())
      return
    end

    if not utils.theme_exists(theme) then
      utils.notify(string.format("Theme '%s' not found", theme), vim.log.levels.WARN, config.get())
      return
    end

    local ok, err = utils.safe_colorscheme(theme)
    if ok then
      cache.set_current(theme, true) -- save as persistent theme
      cache.add_to_history(theme)
      cache.increment_usage(theme)
      cache.undo_push(theme)

      utils.notify("Applied: " .. theme, vim.log.levels.INFO, config.get())
    else
      utils.notify("Failed to apply: " .. err, vim.log.levels.ERROR, config.get())
    end
  end, {
    nargs = 1,
    complete = function(arg_lead)
      local all_themes = utils.get_all_themes()

      if arg_lead and arg_lead ~= "" then
        local filtered = {}
        local lower_lead = arg_lead:lower()
        for _, theme in ipairs(all_themes) do
          if theme:lower():find(lower_lead, 1, true) then
            table.insert(filtered, theme)
          end
        end
        return filtered
      end

      return all_themes
    end,
    desc = "Apply a theme by name",
  })

  -- Refresh and reload current theme
  vim.api.nvim_create_user_command("RaphaelRefresh", function()
    local current = cache.get_current()
    if current and utils.theme_exists(current) then
      utils.safe_colorscheme(current)
      utils.notify("Refreshed: " .. current, vim.log.levels.INFO, config.get())
    else
      utils.notify("No current theme to refresh", vim.log.levels.WARN, config.get())
    end
  end, { desc = "Refresh and reload current theme" })

  -- Show current status
  vim.api.nvim_create_user_command("RaphaelStatus", function()
    local current = cache.get_current()
    local saved = cache.get_saved()
    local auto_apply = cache.get_auto_apply()
    local bookmarks = cache.get_bookmarks()
    local history = cache.get_history()
    local sort_mode = cache.get_sort_mode()

    local lines = {
      "Raphael Status:",
      "  Current: " .. (current or "none"),
      "  Saved: " .. (saved or "none"),
      "  Auto-apply: " .. (auto_apply and "enabled" or "disabled"),
      "  Sort mode: " .. sort_mode,
      "  Bookmarks: " .. #bookmarks,
      "  History: " .. #history,
    }

    local msg = table.concat(lines, "\n")
    vim.notify(msg, vim.log.levels.INFO)
  end, { desc = "Show current theme status" })

  -- Show help
  vim.api.nvim_create_user_command("RaphaelHelp", function()
    local cfg = config.get()
    local leader = cfg.leader

    local help = {
      "Raphael.nvim - Theme Manager",
      "",
      "Commands:",
      "  :RaphaelPicker          Open configured themes",
      "  :RaphaelPickerAll       Open all themes",
      "  :RaphaelApply <theme>   Apply a theme",
      "  :RaphaelToggleAuto      Toggle auto-apply",
      "  :RaphaelRefresh         Refresh current theme",
      "  :RaphaelStatus          Show status",
      "",
      "Global Keymaps:",
      "  " .. leader .. "p         Open picker",
      "  " .. leader .. "/         Open all themes",
      "  " .. leader .. "a         Toggle auto-apply",
      "  " .. leader .. ">         Next theme",
      "  " .. leader .. "<         Previous theme",
      "  " .. leader .. "r         Random theme",
      "",
      "Picker Keymaps:",
      "  <CR>      Apply theme",
      "  /         Search",
      "  b         Toggle bookmark",
      "  c         Collapse/expand group",
      "  q/<Esc>   Close (revert)",
      "  u/<C-r>   Undo/redo",
      "  s         Cycle sort mode",
      "  r         Random theme",
      "  i/I       Cycle sample language",
      "  ?         Show this help",
    }

    local msg = table.concat(help, "\n")
    vim.notify(msg, vim.log.levels.INFO)
  end, { desc = "Show Raphael help" })

  -- Undo theme change
  vim.api.nvim_create_user_command("RaphaelUndo", function()
    local theme = cache.undo_pop()
    if theme then
      local ok, err = utils.safe_colorscheme(theme)
      if ok then
        cache.set_current(theme, false) -- don't overwrite saved
        utils.notify("Undo to: " .. theme, vim.log.levels.INFO, config.get())
      else
        utils.notify("Failed to undo: " .. err, vim.log.levels.ERROR, config.get())
      end
    else
      utils.notify("Nothing to undo", vim.log.levels.WARN, config.get())
    end
  end, { desc = "Undo last theme change" })

  -- Redo theme change
  vim.api.nvim_create_user_command("RaphaelRedo", function()
    local theme = cache.redo_pop()
    if theme then
      local ok, err = utils.safe_colorscheme(theme)
      if ok then
        cache.set_current(theme, false) -- don't overwrite saved
        utils.notify("Redo to: " .. theme, vim.log.levels.INFO, config.get())
      else
        utils.notify("Failed to redo: " .. err, vim.log.levels.ERROR, config.get())
      end
    else
      utils.notify("Nothing to redo", vim.log.levels.WARN, config.get())
    end
  end, { desc = "Redo last undone theme change" })

  -- Random theme
  vim.api.nvim_create_user_command("RaphaelRandom", function()
    local all_themes = utils.get_all_themes()
    if #all_themes == 0 then
      utils.notify("No themes available", vim.log.levels.WARN, config.get())
      return
    end

    local theme = utils.random_theme(all_themes)
    if theme then
      local ok, err = utils.safe_colorscheme(theme)
      if ok then
        cache.set_current(theme, true)
        cache.add_to_history(theme)
        cache.increment_usage(theme)
        cache.undo_push(theme)
        utils.notify("Random: " .. theme, vim.log.levels.INFO, config.get())
      else
        utils.notify("Failed to apply random theme: " .. err, vim.log.levels.ERROR, config.get())
      end
    end
  end, { desc = "Apply a random theme" })

  -- Show full history
  vim.api.nvim_create_user_command("RaphaelHistory", function()
    local history = cache.get_history()
    if #history == 0 then
      utils.notify("No history", vim.log.levels.INFO, config.get())
      return
    end

    local lines = { "Theme History (most recent first):" }
    for i, theme in ipairs(history) do
      local usage = cache.get_usage(theme)
      table.insert(lines, string.format("  %d. %s (used %d times)", i, theme, usage))
    end

    local msg = table.concat(lines, "\n")
    vim.notify(msg, vim.log.levels.INFO)
  end, { desc = "Show full theme history" })

  -- Clear state (for debugging)
  vim.api.nvim_create_user_command("RaphaelClear", function()
    vim.ui.select({ "Yes", "No" }, {
      prompt = "Clear all Raphael state (bookmarks, history, etc.)?",
    }, function(choice)
      if choice == "Yes" then
        cache.clear()
        utils.notify("State cleared", vim.log.levels.INFO, config.get())
      end
    end)
  end, { desc = "Clear all state (bookmarks, history, etc.)" })
end

return M
