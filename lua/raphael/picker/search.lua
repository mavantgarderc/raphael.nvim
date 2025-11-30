-- lua/raphael/picker/search.lua
-- Search window for Raphael's picker:
--   - Prompt at bottom of picker
--   - Live filtering via core.autocmds.search_textchange_autocmd
--   - Match highlighting using "Search" highlight group

local M = {}

local autocmds = require("raphael.core.autocmds")
local C = require("raphael.constants")

local map = vim.keymap.set

local function trim(s)
  return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

--- Open search window attached to the picker.
---
--- This creates a 1-line prompt window just below the picker, with:
---   - prompt: ICON.SEARCH
---   - live updates:
---       * ctx.search_query updated via set_search_query
---       * full picker re-render via fns.render()
---       * match highlighting via SEARCH_MATCH namespace
---
---@param ctx table
---   ctx.buf, ctx.win, ctx.w, ctx.h, ctx.row, ctx.col
---   ctx.search_query : string
---   ctx.opts         : picker options
---   ctx.search_buf   : (will be set)
---   ctx.search_win   : (will be set)
---@param fns table
---   fns.render()      : re-render picker
---   fns.highlight()   : re-highlight current line
function M.open(ctx, fns)
  local picker_win = ctx.win
  local picker_buf = ctx.buf

  if not picker_win or not vim.api.nvim_win_is_valid(picker_win) then
    return
  end

  if ctx.search_win and vim.api.nvim_win_is_valid(ctx.search_win) then
    pcall(vim.api.nvim_set_current_win, ctx.search_win)
    return
  end

  local search_buf = vim.api.nvim_create_buf(false, true)
  ctx.search_buf = search_buf

  local s_row = ctx.row + ctx.h - 1
  local search_win = vim.api.nvim_open_win(search_buf, true, {
    relative = "editor",
    width = ctx.w,
    height = 1,
    row = s_row,
    col = ctx.col,
    style = "minimal",
    border = "rounded",
  })
  ctx.search_win = search_win

  pcall(vim.api.nvim_set_option_value, "buftype", "prompt", { buf = search_buf })
  vim.fn.prompt_setprompt(search_buf, C.ICON.SEARCH .. " ")
  pcall(vim.api.nvim_set_current_win, search_win)
  vim.cmd("startinsert")

  local ns = C.NS.SEARCH_MATCH

  autocmds.search_textchange_autocmd(search_buf, {
    trim = trim,
    ICON_SEARCH = C.ICON.SEARCH,
    render = function()
      fns.render()
    end,
    get_picker_buf = function()
      return picker_buf
    end,
    get_picker_opts = function()
      return ctx.opts
    end,
    ns = ns,
    set_search_query = function(val)
      ctx.search_query = val
    end,
  })

  local function restore_cursor_after_search()
    if
      not ctx.buf
      or not vim.api.nvim_buf_is_valid(ctx.buf)
      or not ctx.win
      or not vim.api.nvim_win_is_valid(ctx.win)
    then
      return
    end
    local lines = vim.api.nvim_buf_get_lines(ctx.buf, 0, -1, false)
    for i, line in ipairs(lines) do
      if not line:match("^" .. C.ICON.GROUP_EXPANDED) and not line:match("^" .. C.ICON.GROUP_COLLAPSED) then
        pcall(vim.api.nvim_win_set_cursor, ctx.win, { i, 0 })
        fns.highlight()
        break
      end
    end
  end

  map("i", "<C-w>", function()
    local ok_line, line = pcall(vim.api.nvim_buf_get_lines, search_buf, 0, 1, false)
    if not ok_line or not line or not line[1] then
      return
    end
    local text = line[1]
    if text == "" then
      return
    end
    local ok_pos, pos = pcall(vim.api.nvim_win_get_cursor, search_win)
    if not ok_pos or not pos then
      return
    end
    local col = pos[2] or 0
    local left = text:sub(1, col)
    local right = text:sub(col + 1)
    local new_left = left:gsub("%s*%S+$", "")
    if new_left == left then
      return
    end
    local new_text = new_left .. right
    pcall(vim.api.nvim_buf_set_lines, search_buf, 0, -1, false, { new_text })
    local new_col = #new_left
    pcall(vim.api.nvim_win_set_cursor, search_win, { 1, new_col })
  end, { buffer = search_buf })

  map("i", "<C-l>", function()
    keymaps.go_in_group(ctx)
  end, { buffer = search_buf })

  map("i", "<C-h>", function()
    keymaps.go_out_group(ctx)
  end, { buffer = search_buf })

  map("i", "<Esc>", function()
    ctx.search_query = ""
    fns.render()
    if ctx.search_win and vim.api.nvim_win_is_valid(ctx.search_win) then
      pcall(vim.api.nvim_win_close, ctx.search_win, true)
    end
    ctx.search_buf, ctx.search_win = nil, nil
    vim.cmd("stopinsert")
    if ctx.win and vim.api.nvim_win_is_valid(ctx.win) then
      pcall(vim.api.nvim_set_current_win, ctx.win)
      restore_cursor_after_search()
    end
  end, { buffer = search_buf })

  map("i", "<CR>", function()
    if ctx.search_win and vim.api.nvim_win_is_valid(ctx.search_win) then
      pcall(vim.api.nvim_win_close, ctx.search_win, true)
    end
    ctx.search_buf, ctx.search_win = nil, nil
    vim.cmd("stopinsert")
    if ctx.win and vim.api.nvim_win_is_valid(ctx.win) then
      pcall(vim.api.nvim_set_current_win, ctx.win)
    end
    fns.render()
  end, { buffer = search_buf })
end

return M
