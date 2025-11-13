local themes = require("raphael.themes")

local M = {}

local function guard_state(fn)
  return function(...)
    local core = select(1, ...)
    if not core or not core.state then
      return
    end
    return fn(core, select(2, ...))
  end
end

---@diagnostic disable-next-line: unused-local
function M.setup(core) -- luacheck: ignore
  vim.api.nvim_create_autocmd("BufEnter", {
    callback = guard_state(function(inner_core)
      if not inner_core.state.auto_apply then
        return
      end
      local ft = vim.bo.filetype
      local theme = themes.filetype_themes[ft]
      if theme and themes.is_available(theme) then
        inner_core.apply(theme, false)
      else
        inner_core.apply(inner_core.config.default_theme, false)
      end
    end),
  })

  vim.api.nvim_create_autocmd("LspAttach", {
    callback = function()
      vim.api.nvim_set_hl(0, "LspReferenceText", { link = "CursorLine" })
      vim.api.nvim_set_hl(0, "LspReferenceRead", { link = "CursorLine" })
      vim.api.nvim_set_hl(0, "LspReferenceWrite", { link = "Visual" })
    end,
  })

  vim.api.nvim_create_autocmd("FileType", {
    callback = guard_state(function(inner_core, args)
      if not inner_core.state.auto_apply then
        return
      end

      local ft = args.match
      local theme_ft = themes.filetype_themes[ft]

      if theme_ft and themes.is_available(theme_ft) then
        inner_core.apply(theme_ft, false)
      elseif theme_ft and not themes.is_available(theme_ft) then
        vim.notify(
          string.format("raphael: filetype theme '%s' for %s not available, using default", theme_ft, ft),
          vim.log.levels.WARN
        )
        if themes.is_available(inner_core.config.default_theme) then
          inner_core.apply(inner_core.config.default_theme, false)
        end
      end
    end),
  })
end

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
