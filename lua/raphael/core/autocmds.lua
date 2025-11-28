-- lua/raphael/core/autocmds.lua
--- Startup restore + BufEnter filetype auto-apply + session hooks

local M = {}

local cache = require("raphael.core.cache")
local utils = require("raphael.utils")
local config = require("raphael.config")

--- Setup auto-apply autocmds for filetype switching
function M.setup_auto_apply()
  vim.api.nvim_create_autocmd("BufEnter", {
    group = vim.api.nvim_create_augroup("RaphaelAutoApply", { clear = true }),
    callback = function(ev)
      if not cache.get_auto_apply() then
        return
      end

      local ft = vim.bo[ev.buf].filetype
      if not ft or ft == "" then
        return
      end

      local cfg = config.get()
      local theme = cfg.filetype_themes[ft]

      if theme and utils.theme_exists(theme) then
        -- Apply temporarily (don't save to cache)
        local ok, err = utils.safe_colorscheme(theme)
        if not ok then
          utils.notify("Failed to apply filetype theme: " .. err, vim.log.levels.ERROR, cfg)
        end
      elseif theme then
        utils.notify(string.format("Filetype theme '%s' for %s not found", theme, ft), vim.log.levels.WARN, cfg)
      end
    end,
  })
end

--- Setup CursorMoved autocmd for picker live preview
function M.setup_picker_cursor(picker_buf, on_cursor_moved)
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = picker_buf,
    callback = function()
      local ok, line = pcall(vim.api.nvim_get_current_line)
      if not ok then
        return
      end

      if type(on_cursor_moved) == "function" then
        pcall(on_cursor_moved, line)
      end
    end,
  })
end

--- Setup BufDelete autocmd for picker cleanup
function M.setup_picker_cleanup(picker_buf, on_cleanup)
  vim.api.nvim_create_autocmd("BufDelete", {
    buffer = picker_buf,
    once = true,
    callback = function()
      if type(on_cleanup) == "function" then
        pcall(on_cleanup)
      end
    end,
  })
end

--- Setup TextChanged autocmd for search input
function M.setup_search_input(search_buf, on_search_changed)
  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    buffer = search_buf,
    callback = function()
      local ok_lines, lines = pcall(vim.api.nvim_buf_get_lines, search_buf, 0, -1, false)
      if not ok_lines then
        return
      end

      local joined = table.concat(lines, "\n")

      if type(on_search_changed) == "function" then
        pcall(on_search_changed, joined)
      end
    end,
  })
end

--- Setup VimEnter autocmd to restore saved theme on startup
function M.setup_startup_restore()
  vim.api.nvim_create_autocmd("VimEnter", {
    group = vim.api.nvim_create_augroup("RaphaelStartup", { clear = true }),
    once = true,
    callback = function()
      local cfg = config.get()
      if not cfg.persistence.restore_on_startup then
        return
      end

      local saved = cache.get_saved()
      if saved and utils.theme_exists(saved) then
        utils.safe_colorscheme(saved)
      end
    end,
  })
end

return M
