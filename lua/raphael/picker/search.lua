-- lua/raphael/picker/search.lua
-- Search window for Raphael's picker:
--   - Prompt at bottom of picker
--   - Live filtering via core.autocmds.search_textchange_autocmd
--   - Match highlighting using "Search" highlight group

local M = {}

local autocmds = require("raphael.core.autocmds")
local C = require("raphael.constants")
local keymaps = require("raphael.picker.keymaps")
local render = require("raphael.picker.render")

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
---   ctx.search_scope : string|nil
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

  local function update_prompt()
    vim.fn.prompt_setprompt(search_buf, C.ICON.SEARCH .. " ")
  end

  local function update_scope_visual()
    local title = nil
    if ctx.search_scope and ctx.search_scope ~= "" then
      title = string.format("[scope: %s]", ctx.search_scope)
    end
    pcall(vim.api.nvim_win_set_config, search_win, {
      title = title,
      title_pos = "center",
    })
  end

  update_prompt()
  update_scope_visual()

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

  local function current_group_header()
    local win = ctx.win
    local buf = ctx.buf
    if not win or not vim.api.nvim_win_is_valid(win) then
      return nil
    end
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
      return nil
    end
    local ok_cur, cursor = pcall(vim.api.nvim_win_get_cursor, win)
    if not ok_cur then
      return nil
    end
    local row = cursor[1]
    local all = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local line = all[row] or ""
    local hdr = render.parse_line_header(line)
    if not hdr then
      for i = row, 1, -1 do
        hdr = render.parse_line_header(all[i] or "")
        if hdr then
          break
        end
      end
    end
    if hdr == "Bookmarks" or hdr == "Recent" then
      return nil
    end
    return hdr
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
    local hdr = current_group_header()
    if hdr then
      ctx.search_scope = hdr
      update_scope_visual()
      fns.render()
    end
    keymaps.go_in_group(ctx)
  end, { buffer = search_buf })

  map("i", "<C-h>", function()
    if ctx.search_scope ~= nil then
      ctx.search_scope = nil
      update_scope_visual()
      fns.render()
    end
    keymaps.go_out_group(ctx)
  end, { buffer = search_buf })

  map("i", "<Esc>", function()
    ctx.search_query = ""
    ctx.search_scope = nil
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
