-- lua/raphael/core/autocmds.lua
-- Global and picker-specific autocmds for raphael.nvim.
--
-- Responsibilities:
--   - Global:
--       * BufEnter / FileType auto-apply of themes based on filetype
--       * LspAttach highlights for LSP references
--   - Picker-specific:
--       * CursorMoved inside picker (update palette + preview + highlight)
--       * BufDelete on picker buffer (cleanup)
--       * TextChanged in search buffer (live search + match highlighting)

local M = {}

local themes = require("raphael.themes")

--- Setup global autocmds that depend on the core orchestrator.
---
--- Global behavior:
---   - BufEnter:
---       * If core.state.auto_apply is true:
---           - Look up filetype → theme via themes.filetype_themes[ft]
---           - If found and available: apply that theme
---           - Otherwise: fall back to core.config.default_theme
---   - FileType:
---       * Same as BufEnter, but triggered on FileType event
---       * Emits a warning if the configured theme for that ft is not available
---   - LspAttach:
---       * Set up default highlights for LspReference* groups
---
---@param core table  # usually require("raphael.core")
function M.setup(core)
  vim.api.nvim_create_autocmd("BufEnter", {
    callback = function(ev)
      if not core.state.auto_apply then
        return
      end

      local ft = vim.bo[ev.buf].filetype
      local theme = themes.filetype_themes[ft]
      if theme and themes.is_available(theme) then
        core.apply(theme, false)
      else
        core.apply(core.config.default_theme, false)
      end
    end,
  })

  vim.api.nvim_create_autocmd("LspAttach", {
    callback = function()
      vim.api.nvim_set_hl(0, "LspReferenceText", { link = "CursorLine" })
      vim.api.nvim_set_hl(0, "LspReferenceRead", { link = "CursorLine" })
      vim.api.nvim_set_hl(0, "LspReferenceWrite", { link = "Visual" })
    end,
  })

  vim.api.nvim_create_autocmd("FileType", {
    callback = function(ev)
      if not core.state.auto_apply then
        return
      end

      local ft = ev.match
      local theme_ft = themes.filetype_themes[ft]

      if theme_ft and themes.is_available(theme_ft) then
        core.apply(theme_ft, false)
      elseif theme_ft and not themes.is_available(theme_ft) then
        vim.notify(
          string.format("raphael: filetype theme '%s' for %s not available, using default", theme_ft, ft),
          vim.log.levels.WARN
        )
        if themes.is_available(core.config.default_theme) then
          core.apply(core.config.default_theme, false)
        end
      end
    end,
  })
end

--- Attach a CursorMoved autocmd to the picker buffer.
---
--- Each cursor movement inside the picker can:
---   - Parse the current line to extract a theme name (parse(line))
---   - Preview that theme (preview(theme))
---   - Re-apply visual highlight for the current line (highlight())
---   - Trigger a debounced preview update (e.g. code sample) (update_preview)
---
---@param picker_buf integer  # buffer number of the picker
---@param cbs table|nil       # callbacks table:
---   {
---     parse          = fun(line:string):string|nil,
---     preview        = fun(theme:string)|nil,
---     highlight      = fun()|nil,
---     update_preview = fun(opts:table)|nil,
---   }
function M.picker_cursor_autocmd(picker_buf, cbs)
  if type(picker_buf) ~= "number" then
    error("picker_cursor_autocmd: picker_buf must be a buffer number")
  end
  cbs = cbs or {}
  local parse = cbs.parse
  local preview = cbs.preview
  local highlight = cbs.highlight
  local update_preview = cbs.update_preview

  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = picker_buf,
    callback = function()
      local ok, line = pcall(vim.api.nvim_get_current_line)
      if not ok then
        return
      end

      local theme
      if type(parse) == "function" then
        theme = parse(line)
      end
      if theme and type(preview) == "function" then
        preview(theme)
      end
      if type(highlight) == "function" then
        highlight()
      end
      if type(update_preview) == "function" then
        update_preview({ debounced = true })
      end
    end,
  })
end

--- Attach a BufDelete autocmd to the picker buffer.
---
--- Once the picker buffer is deleted, this:
---   - Optionally logs via cbs.log(level, msg)
---   - Calls cbs.cleanup() for any extra cleanup (timers, windows, etc.)
---
---@param picker_buf integer  # buffer number of the picker
---@param cbs table|nil       # callbacks table:
---   {
---     log     = fun(level:string, msg:string)|nil,
---     cleanup = fun()|nil,
---   }
function M.picker_bufdelete_autocmd(picker_buf, cbs)
  if type(picker_buf) ~= "number" then
    error("picker_bufdelete_autocmd: picker_buf must be a buffer number")
  end
  cbs = cbs or {}
  local log = cbs.log
  local cleanup = cbs.cleanup

  vim.api.nvim_create_autocmd("BufDelete", {
    buffer = picker_buf,
    once = true,
    callback = function()
      if type(log) == "function" then
        pcall(log, "DEBUG", "Picker buffer deleted, cleaning up")
      end
      if type(cleanup) == "function" then
        pcall(cleanup)
      end
    end,
  })
end

--- Attach TextChanged autocmds for the search buffer.
---
--- This handles:
---   - Reading the prompt + query from the search buffer
---   - Stripping the search icon prefix (ICON_SEARCH)
---   - Updating the search query in the picker state (set_search_query)
---   - Re-rendering the picker (render)
---   - Highlighting matches in the picker buffer using ns + "Search"
---
---@param search_buf integer  # buffer number of the search prompt
---@param cbs table|nil       # callbacks table:
---   {
---     trim           = fun(s:string):string|nil,
---     ICON_SEARCH    = string|nil,
---     render         = fun(opts:table|nil)|nil,
---     get_picker_buf = fun():integer|nil,
---     get_picker_opts= fun():table|nil,
---     ns             = integer,            -- extmark namespace for search matches
---     set_search_query = fun(q:string)|nil,
---   }
function M.search_textchange_autocmd(search_buf, cbs)
  if type(search_buf) ~= "number" then
    error("search_textchange_autocmd: search_buf must be a buffer number")
  end
  cbs = cbs or {}
  local trim = cbs.trim
  local ICON_SEARCH = cbs.ICON_SEARCH
  local render = cbs.render
  local get_picker_buf = cbs.get_picker_buf
  local get_picker_opts = cbs.get_picker_opts
  local ns = cbs.ns
  local set_search_query = cbs.set_search_query

  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    buffer = search_buf,
    callback = function()
      local ok_lines, lines = pcall(vim.api.nvim_buf_get_lines, search_buf, 0, -1, false)
      if not ok_lines then
        return
      end

      local joined = table.concat(lines, "\n")
      local new_query = joined:gsub("^" .. (ICON_SEARCH or ""), "")
      if type(trim) == "function" then
        new_query = trim(new_query)
      end

      if type(set_search_query) == "function" then
        pcall(set_search_query, new_query)
      end

      if type(render) == "function" then
        local opts = nil
        if type(get_picker_opts) == "function" then
          opts = get_picker_opts()
        end
        pcall(render, opts)
      end

      local pbuf = nil
      if type(get_picker_buf) == "function" then
        pbuf = get_picker_buf()
      end

      if pbuf and vim.api.nvim_buf_is_valid(pbuf) then
        pcall(vim.api.nvim_buf_clear_namespace, pbuf, ns, 0, -1)
        if new_query ~= "" and #new_query >= 2 then
          local ok_plines, picker_lines = pcall(vim.api.nvim_buf_get_lines, pbuf, 0, -1, false)
          if ok_plines and picker_lines then
            local query_lower = new_query:lower()
            for i, line in ipairs(picker_lines) do
              local start_idx = 1
              local match_count = 0
              while match_count < 10 do
                local s, e = line:lower():find(query_lower, start_idx, true)
                if not s then
                  break
                end
                pcall(vim.api.nvim_buf_set_extmark, pbuf, ns, i - 1, s - 1, {
                  end_col = e,
                  hl_group = "Search",
                  strict = false,
                })
                start_idx = e + 1
                match_count = match_count + 1
              end
            end
          end
        end
      end
    end,
  })
end

return M
