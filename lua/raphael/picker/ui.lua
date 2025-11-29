local M = {}

local themes = require("raphael.themes")
local autocmds = require("raphael.core.autocmds")
local render = require("raphael.picker.render")
local search = require("raphael.picker.search")
local preview = require("raphael.picker.preview")
local keymaps = require("raphael.picker.keymaps")
local bookmarks_mod = require("raphael.picker.bookmarks")

local picker_instances = {
  configured = false,
  other = false,
}

local ctx = {
  core = nil,
  state = nil,
  buf = nil,
  win = nil,
  w = nil,
  h = nil,
  row = nil,
  col = nil,

  picker_type = nil,
  opts = {},
  base_title = "",

  collapsed = {},
  bookmarks = {},
  header_lines = {},
  last_cursor = {},

  search_query = "",
  search_buf = nil,
  search_win = nil,

  flags = {
    disable_sorting = false,
    reverse_sorting = false,
    debug = false,
  },

  instances = picker_instances,
}

local function log(level, msg, data)
  if not ctx.flags.debug and level ~= "ERROR" and level ~= "WARN" then
    return
  end
  local prefix = string.format("[Raphael:%s]", level)
  if data then
    vim.notify(string.format("%s %s: %s", prefix, msg, vim.inspect(data)), vim.log.levels[level])
  else
    vim.notify(string.format("%s %s", prefix, msg), vim.log.levels[level])
  end
end

local function save_previous_theme()
  local state = ctx.state
  state.previous = state.current or vim.g.colors_name or state.saved
  log("DEBUG", "Previous theme saved", state.previous)
end

local function close_picker_windows()
  for _, win in ipairs({ ctx.win, ctx.search_win }) do
    if win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  ctx.buf, ctx.win, ctx.search_buf, ctx.search_win = nil, nil, nil, nil
end

local function close_picker(revert)
  log("DEBUG", "Closing picker", { revert = revert })

  if revert and ctx.state and ctx.state.previous and themes.is_available(ctx.state.previous) then
    local ok, err = pcall(preview.load_theme, ctx.state.previous, true)
    if not ok then
      log("ERROR", "Failed to revert theme", err)
    end
  end

  preview.close_all()
  close_picker_windows()

  ctx.search_query = ""
  ctx.opts = {}
  ctx.header_lines = {}
  ctx.last_cursor = {}
  ctx.collapsed = {}
  ctx.bookmarks = {}
  ctx.flags.disable_sorting = false
  ctx.flags.reverse_sorting = false

  log("DEBUG", "Picker closed successfully")
end

local function update_state_collapsed()
  ctx.state.collapsed = vim.deepcopy(ctx.collapsed)
  if ctx.core and ctx.core.save_state then
    pcall(ctx.core.save_state)
  end
end

local function render_picker()
  render.render(ctx)
end

local function setup_autocmds_for_picker()
  autocmds.picker_cursor_autocmd(ctx.buf, {
    parse = function(line)
      return render.parse_line_theme(ctx.core, line)
    end,
    preview = function(theme)
      preview.preview_theme(ctx, theme)
    end,
    highlight = function()
      keymaps.highlight_current_line(ctx)
    end,
    update_preview = function()
      preview.update_code_preview(ctx)
    end,
  })

  autocmds.picker_bufdelete_autocmd(ctx.buf, {
    log = log,
    cleanup = function()
      preview.close_all()
    end,
  })
end

local function setup_search()
  search.open(ctx, {
    render = render_picker,
    highlight = function()
      keymaps.highlight_current_line(ctx)
    end,
  })
end

local function build_title()
  local state = ctx.state
  local core = ctx.core

  local sort = ctx.flags.disable_sorting and "off" or (state.sort_mode or core.config.sort_mode or "alpha")
  local suffix = sort .. (ctx.flags.reverse_sorting and " reverse " or "")
  ctx.base_title = ctx.opts.exclude_configured and "Raphael - Other Themes" or "Raphael - Configured Themes"
  return ctx.base_title .. " (Sort: " .. suffix .. ")"
end

local function open_picker_window()
  ctx.h = math.max(6, math.floor(vim.o.lines * 0.7))
  ctx.w = math.floor(vim.o.columns * 0.35)
  ctx.row = math.floor((vim.o.lines - ctx.h) / 2)
  ctx.col = math.floor(((vim.o.columns - ctx.w) / 2) - (ctx.w / 2))

  if not ctx.buf or not vim.api.nvim_buf_is_valid(ctx.buf) then
    ctx.buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = ctx.buf })
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = ctx.buf })
    vim.api.nvim_set_option_value("filetype", "raphael_picker", { buf = ctx.buf })
  end

  local title = build_title()

  ctx.win = vim.api.nvim_open_win(ctx.buf, true, {
    relative = "editor",
    width = ctx.w,
    height = ctx.h,
    row = ctx.row,
    col = ctx.col,
    style = "minimal",
    border = "rounded",
    title = title,
  })
end

local function init_context(core, opts)
  ctx.core = core
  ctx.state = core.state

  ctx.opts = opts or {}
  ctx.picker_type = ctx.opts.exclude_configured and "other" or "configured"

  ctx.collapsed = type(ctx.state.collapsed) == "table" and vim.deepcopy(ctx.state.collapsed) or {}
  ctx.collapsed["__bookmarks"] = ctx.collapsed["__bookmarks"] or false
  ctx.collapsed["__recent"] = ctx.collapsed["__recent"] or false

  ctx.bookmarks = bookmarks_mod.build_set(ctx.state)
  ctx.header_lines = {}
  ctx.last_cursor = {}
  ctx.search_query = ""

  ctx.flags.disable_sorting = false
  ctx.flags.reverse_sorting = false
end

function M.toggle_debug()
  ctx.flags.debug = not ctx.flags.debug
  vim.notify("raphael picker debug: " .. (ctx.flags.debug and "ON" or "OFF"), vim.log.levels.INFO)
end

function M.toggle_animations()
  local cfg = ctx.core and ctx.core.config or {}
  cfg.animate = cfg.animate or {}
  cfg.animate.enabled = not (cfg.animate.enabled == true)
  vim.notify("raphael picker animations: " .. (cfg.animate.enabled and "ON" or "OFF"), vim.log.levels.INFO)
end

function M.get_cache_stats()
  return preview.get_cache_stats()
end

function M.get_current_theme()
  if not ctx.win or not vim.api.nvim_win_is_valid(ctx.win) then
    return nil
  end
  local line = vim.api.nvim_get_current_line()
  return render.parse_line_theme(ctx.core, line)
end

function M.update_palette(theme)
  preview.update_palette(ctx, theme)
end

function M.open(core, opts)
  opts = opts or {}

  local picker_type = opts.exclude_configured and "other" or "configured"
  if picker_instances[picker_type] then
    log("DEBUG", "Picker already open, ignoring", { type = picker_type })
    return
  end
  picker_instances[picker_type] = true

  init_context(core, opts)
  log("DEBUG", "Opening picker", opts)

  open_picker_window()
  save_previous_theme()

  render_picker()
  keymaps.highlight_current_line(ctx)

  if ctx.state.current then
    preview.update_palette(ctx, ctx.state.current)
  end

  keymaps.attach(ctx, {
    close_picker = close_picker,
    render = render_picker,
    update_state_collapsed = update_state_collapsed,
    open_search = setup_search,
  })

  setup_autocmds_for_picker()

  log("DEBUG", "Picker opened successfully")
end

return M
