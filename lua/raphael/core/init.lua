local cache = require("raphael.core.cache")
local history = require("raphael.extras.history")
local themes = require("raphael.themes")
local picker = require("raphael.picker.ui")

local M = {}

M.config = {}

M.state = {
  current = nil,
  saved = nil,
  previous = nil,
  auto_apply = false,
  bookmarks = {},
  history = {},
  usage = {},
  collapsed = {},
  sort_mode = "alpha",
  undo_history = {
    stack = {},
    index = 0,
    max_size = 0,
  },
}

M.picker = picker

local function reload_state_from_cache()
  local s = cache.read()
  M.state = s
end

local function save_state_to_cache()
  cache.write(M.state)
end

local function apply_colorscheme_raw(theme)
  vim.cmd("hi clear")
  if vim.fn.exists("syntax_on") == 1 then
    vim.cmd("syntax reset")
  end

  local ok, err = pcall(vim.cmd.colorscheme, theme)
  if not ok then
    vim.notify(
      string.format("raphael: failed to apply theme '%s': %s", tostring(theme), tostring(err)),
      vim.log.levels.ERROR
    )
    return false
  end

  return true
end

local function record_manual_change(theme)
  if not theme or theme == "" then
    return
  end

  M.state.usage = M.state.usage or {}
  M.state.usage[theme] = (M.state.usage[theme] or 0) + 1

  M.state.history = M.state.history or {}

  for i, name in ipairs(M.state.history) do
    if name == theme then
      table.remove(M.state.history, i)
      break
    end
  end

  table.insert(M.state.history, 1, theme)

  cache.add_to_history(theme)
  history.add(theme)
end

function M.setup(config)
  M.config = config or {}

  themes.filetype_themes = config.filetype_themes or {}
  themes.theme_map = config.theme_map or {}

  themes.refresh()

  M.state = cache.read()

  local startup_theme = M.state.saved or M.state.current or config.default_theme

  if startup_theme and themes.is_available(startup_theme) then
    if apply_colorscheme_raw(startup_theme) then
      M.state.current = startup_theme
      M.state.saved = startup_theme
      save_state_to_cache()
    end
  else
    vim.notify(string.format("raphael: startup theme '%s' not available", tostring(startup_theme)), vim.log.levels.WARN)
  end
end

function M.apply(theme, from_manual)
  if not theme or theme == "" then
    vim.notify("raphael: no theme specified", vim.log.levels.WARN)
    return
  end

  if not themes.is_available(theme) then
    vim.notify("raphael: theme not available: " .. tostring(theme), vim.log.levels.WARN)
    return
  end

  M.state.previous = M.state.current

  if not apply_colorscheme_raw(theme) then
    return
  end

  M.state.current = theme

  if from_manual then
    M.state.saved = theme
    record_manual_change(theme)
  else
    cache.increment_usage(theme)
  end

  save_state_to_cache()

  if type(M.config.on_apply) == "function" then
    M.config.on_apply(theme)
  end
end

function M.save_state()
  if not M.state then
    return
  end
  save_state_to_cache()
end

function M.toggle_auto()
  M.state.auto_apply = not (M.state.auto_apply == true)

  cache.set_auto_apply(M.state.auto_apply)
  vim.api.nvim_set_var("raphael_auto_theme", M.state.auto_apply)

  local msg = M.state.auto_apply and "raphael auto-theme: ON" or "raphael auto-theme: OFF"
  vim.notify(msg, vim.log.levels.INFO)
end

function M.toggle_bookmark(theme)
  if not theme or theme == "" then
    return
  end

  local is_bookmarked = cache.toggle_bookmark(theme)

  M.state.bookmarks = cache.get_bookmarks()

  if is_bookmarked then
    vim.notify("raphael: bookmarked " .. theme, vim.log.levels.INFO)
  else
    vim.notify("raphael: removed bookmark " .. theme, vim.log.levels.INFO)
  end
end

function M.refresh_and_reload()
  themes.refresh()

  local current = M.state.current
  if current and themes.is_available(current) then
    M.apply(current, false)
  else
    vim.notify("raphael: current theme not available after refresh", vim.log.levels.WARN)
  end
end

function M.show_status()
  local auto_status = M.state.auto_apply and "ON" or "OFF"
  local saved_info = ""
  if M.state.saved and M.state.saved ~= M.state.current then
    saved_info = string.format(" | saved: %s", M.state.saved)
  end

  vim.notify(
    string.format("raphael: current - %s%s | auto-apply: %s", M.state.current or "none", saved_info, auto_status),
    vim.log.levels.INFO
  )
end

function M.show_help()
  vim.notify("raphael.nvim: see README for usage and keybindings.", vim.log.levels.INFO)
end

function M.export_for_session()
  local current = M.state.current or M.config.default_theme
  local saved = M.state.saved or current
  local auto = M.state.auto_apply and "1" or "0"

  return string.format(
    [[
" Raphael theme persistence
let g:raphael_session_theme = '%s'
let g:raphael_session_saved = '%s'
let g:raphael_session_auto = %s
]],
    current,
    saved,
    auto
  )
end

function M.restore_from_session()
  local session_theme = vim.g.raphael_session_theme
  local session_saved = vim.g.raphael_session_saved
  local session_auto = vim.g.raphael_session_auto

  if not session_theme then
    return
  end

  M.state.current = session_theme
  M.state.saved = session_saved or session_theme
  M.state.auto_apply = (session_auto == 1)

  if themes.is_available(session_theme) then
    apply_colorscheme_raw(session_theme)
  end

  save_state_to_cache()
end

function M.add_to_history(theme)
  if not theme or theme == "" then
    return
  end
  cache.add_to_history(theme)
  M.state.history = cache.get_history()
end

function M.open_picker(opts)
  return picker.open(M, opts or {})
end

return M
