-- lua/raphael/picker/ui.lua
-- Main orchestrator for Raphael's picker:
--   - Owns picker context (buffers, windows, layout)
--   - Coordinates render, search, preview, keymaps
--   - Exposes public API used as require("raphael.picker")

local M = {}

local themes = require("raphael.themes")
local autocmds = require("raphael.core.autocmds")
local render = require("raphael.picker.render")
local search = require("raphael.picker.search")
local preview = require("raphael.picker.preview")
local keymaps = require("raphael.picker.keymaps")
local bookmarks_mod = require("raphael.picker.bookmarks")

-- Picker instances (to avoid multiple windows per type)
-- Used to prevent opening multiple pickers of the same "type".
---@type table<string, boolean>
local picker_instances = {
  configured = false,
  other = false,
}

--- Single context table for current picker session.
---
--- Fields:
---   core, state        : raphael.core + core.state table
---   buf, win           : picker buffer & window
---   w, h, row, col     : layout (dimensions + position)
---   picker_type        : "configured" or "other"
---   opts               : options passed from core.open_picker()
---   base_title         : base window title ("Raphael - Configured Themes"/"Other Themes")
---   collapsed          : map group -> boolean
---   bookmarks          : set of theme_name -> true
---   header_lines       : array of header line indices
---   last_cursor        : map group -> last line index
---   search_query       : current search query string
---   search_buf, search_win : search prompt buffer & window
---   flags              : { disable_sorting:boolean, reverse_sorting:boolean, debug:boolean }
---   instances          : reference to picker_instances
---@type table
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

--- Internal logger for picker-related events.
---
--- Logs if:
---   - ctx.flags.debug is true, OR
---   - level is "ERROR" or "WARN"
---
---@param level string  "DEBUG"|"INFO"|"WARN"|"ERROR"
---@param msg   string
---@param data  any|nil Additional data (shown via vim.inspect)
local function log(level, msg, data)
  if not ctx.flags.debug and level ~= "ERROR" and level ~= "WARN" then
    return
  end
  local prefix = string.format("[Raphael:%s]", level)
  local lvl = vim.log.levels[level] or vim.log.levels.INFO
  if data then
    vim.notify(string.format("%s %s: %s", prefix, msg, vim.inspect(data)), lvl)
  else
    vim.notify(string.format("%s %s", prefix, msg), lvl)
  end
end

--- Save the theme that should be restored when picker closes with revert=true.
---
--- Uses:
---   - ctx.state.current
---   - g:colors_name
---   - ctx.state.saved
local function save_previous_theme()
  local state = ctx.state
  state.previous = state.current or vim.g.colors_name or state.saved
  log("DEBUG", "Previous theme saved", state.previous)
end

--- Close all picker-related windows (picker + search).
local function close_picker_windows()
  for _, win in ipairs({ ctx.win, ctx.search_win }) do
    if win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  ctx.buf, ctx.win, ctx.search_buf, ctx.search_win = nil, nil, nil, nil
end

--- Close the picker and optionally revert to the previous theme.
---
--- This:
---   - reverts theme (if revert=true and previous theme is available)
---   - closes palette + code preview windows
---   - closes picker/search windows
---   - resets ctx fields (collapsed/bookmarks/flags/etc.)
---
---@param revert boolean
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

  if ctx.picker_type and ctx.instances then
    ctx.instances[ctx.picker_type] = false
  end

  log("DEBUG", "Picker closed successfully")
end

--- Persist ctx.collapsed into core.state.collapsed and call core.save_state() if present.
local function update_state_collapsed()
  ctx.state.collapsed = vim.deepcopy(ctx.collapsed)
  if ctx.core and ctx.core.save_state then
    pcall(ctx.core.save_state)
  end
end

--- Render the picker using the current ctx.
local function render_picker()
  render.render(ctx)
end

--- Setup autocmds specifically for the picker buffer.
---
--- Hooks:
---   - CursorMoved: parse line → preview theme → highlight → update code preview
---   - BufDelete: log + preview.close_all()
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

--- Open the search prompt window attached to the picker.
local function setup_search()
  search.open(ctx, {
    render = render_picker,
    highlight = function()
      keymaps.highlight_current_line(ctx)
    end,
  })
end

--- Build the picker window title based on picker type and sort flags.
---
---@return string title
local function build_title()
  local state = ctx.state
  local core = ctx.core

  local sort = ctx.flags.disable_sorting and "off" or (state.sort_mode or core.config.sort_mode or "alpha")
  local suffix = sort .. (ctx.flags.reverse_sorting and " reverse " or "")
  ctx.base_title = ctx.opts.exclude_configured and "Raphael - Other Themes" or "Raphael - Configured Themes"
  return ctx.base_title .. " (Sort: " .. suffix .. ")"
end

--- Open (or reuse) the main picker window and buffer.
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

--- Initialize the picker context from core and opts.
---
--- Sets:
---   - ctx.core, ctx.state
---   - ctx.opts, ctx.picker_type
---   - ctx.collapsed, ctx.bookmarks
---   - header_lines/last_cursor/search_query
---   - flags (disable_sorting, reverse_sorting)
---
---@param core table      # require("raphael.core")
---@param opts table|nil  # options passed to open_picker()
local function init_context(core, opts)
  ctx.core = core
  ctx.state = core.state

  ctx.opts = opts or {}
  ctx.picker_type = ctx.opts.exclude_configured and "other" or "configured"

  ctx.collapsed = type(ctx.state.collapsed) == "table" and vim.deepcopy(ctx.state.collapsed) or {}
  ctx.collapsed["__bookmarks"] = ctx.collapsed["__bookmarks"] or false
  ctx.collapsed["__recent"] = ctx.collapsed["__recent"] or false

  ctx.bookmarks = bookmarks_mod.build_set(ctx.state, core)

  ctx.header_lines = {}
  ctx.last_cursor = {}
  ctx.search_query = ""

  ctx.flags.disable_sorting = false
  ctx.flags.reverse_sorting = false
end

--- Toggle internal debug mode for the picker.
---
--- When enabled, more messages are logged with prefix [Raphael:DEBUG].
function M.toggle_debug()
  ctx.flags.debug = not ctx.flags.debug
  vim.notify("raphael picker debug: " .. (ctx.flags.debug and "ON" or "OFF"), vim.log.levels.INFO)
end

--- Get cache stats for :RaphaelCacheStats.
---
---@return table
function M.get_cache_stats()
  return preview.get_cache_stats()
end

--- Get the theme under cursor in the picker, or nil if not available.
---
---@return string|nil
function M.get_current_theme()
  if not ctx.win or not vim.api.nvim_win_is_valid(ctx.win) then
    return nil
  end
  local line = vim.api.nvim_get_current_line()
  return render.parse_line_theme(ctx.core, line)
end

--- Update palette preview for a given theme.
---
---@param theme string
function M.update_palette(theme)
  preview.update_palette(ctx, theme)
end

--- Open the picker UI.
---
--- This is the main entrypoint used by core.open_picker().
---
---@param core table      # require("raphael.core")
---@param opts table|nil  # { only_configured = bool, exclude_configured = bool }
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
