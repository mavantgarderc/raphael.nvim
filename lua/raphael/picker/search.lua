local M = {}

local autocmds = require("raphael.core.autocmds")
local C = require("raphael.constants")

local ICON = C.ICON

local map = vim.keymap.set

local function trim(s)
  return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

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
  vim.fn.prompt_setprompt(search_buf, ICON.SEARCH .. " ")
  pcall(vim.api.nvim_set_current_win, search_win)
  vim.cmd("startinsert")

  local ns = C.NS.SEARCH_MATCH

  autocmds.search_textchange_autocmd(search_buf, {
    trim = trim,
    ICON_SEARCH = ICON.SEARCH,
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
      if not line:match("^" .. ICON.GROUP_EXPANDED) and not line:match("^" .. ICON.GROUP_COLLAPSED) then
        pcall(vim.api.nvim_win_set_cursor, ctx.win, { i, 0 })
        fns.highlight()
        break
      end
    end
  end

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
