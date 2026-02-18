-- tests/mock_cache.lua
-- A mock cache module for testing that doesn't affect the real cache

local M = {}

local test_state = {
  current = nil,
  saved = nil,
  previous = nil,
  auto_apply = false,
  bookmarks = { __global = {} },
  history = {},
  usage = {},
  collapsed = {},
  sort_mode = "alpha",
  undo_history = {
    stack = {},
    index = 0,
    max_size = 100,
  },
  quick_slots = { __global = {} },
  current_profile = nil,
}

--- Read state from test memory (or return defaults)
function M.read()
  return test_state
end

--- Write full state to test memory
function M.write(state)
  for k, v in pairs(state) do
    test_state[k] = v
  end

  test_state.bookmarks = test_state.bookmarks or { __global = {} }
  test_state.history = test_state.history or {}
  test_state.usage = test_state.usage or {}
  test_state.collapsed = test_state.collapsed or {}
  test_state.undo_history = test_state.undo_history or {
    stack = {},
    index = 0,
    max_size = 100,
  }
  test_state.quick_slots = test_state.quick_slots or { __global = {} }
  return true
end

--- For debugging only: return current state
function M.get_state()
  return test_state
end

--- Clear everything and reset to defaults
function M.clear()
  test_state = {
    current = nil,
    saved = nil,
    previous = nil,
    auto_apply = false,
    bookmarks = { __global = {} },
    history = {},
    usage = {},
    collapsed = {},
    sort_mode = "alpha",
    undo_history = {
      stack = {},
      index = 0,
      max_size = 100,
    },
    quick_slots = { __global = {} },
    current_profile = nil,
  }
end

--- Get current theme from test state
function M.get_current()
  return test_state.current
end

--- Get saved theme from test state
function M.get_saved()
  return test_state.saved
end

--- Set current theme in test state
function M.set_current(theme, save)
  test_state.previous = test_state.current
  test_state.current = theme

  if save then
    test_state.saved = theme
  end
end

--- Get bookmarks table
function M.get_bookmarks_table()
  return test_state.bookmarks or { __global = {} }
end

--- Get bookmarks list for given scope
function M.get_bookmarks(scope)
  scope = scope or "__global"
  local all = M.get_bookmarks_table()
  return all[scope] or {}
end

--- Toggle bookmark for a theme in a scope
function M.toggle_bookmark(theme, scope)
  scope = scope or "__global"
  test_state.bookmarks = test_state.bookmarks or { __global = {} }

  if type(test_state.bookmarks[scope]) ~= "table" then
    test_state.bookmarks[scope] = {}
  end

  local list = test_state.bookmarks[scope]
  local idx = nil
  for i, name in ipairs(list) do
    if name == theme then
      idx = i
      break
    end
  end

  if idx then
    table.remove(list, idx)
    return false, test_state.bookmarks
  else
    if #list >= 50 then
      return false, nil
    end
    table.insert(list, theme)

    return true, test_state.bookmarks
  end
end

--- Check if theme is bookmarked
function M.is_bookmarked(theme, scope)
  scope = scope or "__global"
  local list = M.get_bookmarks(scope)
  for _, name in ipairs(list) do
    if name == theme then
      return true
    end
  end
  return false
end

--- Add theme to history in test state
function M.add_to_history(theme)
  test_state.history = test_state.history or {}

  for i, name in ipairs(test_state.history) do
    if name == theme then
      table.remove(test_state.history, i)
      break
    end
  end

  table.insert(test_state.history, 1, theme)

  while #test_state.history > 12 do
    table.remove(test_state.history)
  end
end

--- Get history from test state
function M.get_history()
  return test_state.history or {}
end

--- Increment usage count for theme in test state
function M.increment_usage(theme)
  test_state.usage = test_state.usage or {}
  test_state.usage[theme] = (test_state.usage[theme] or 0) + 1
end

--- Get usage count for theme from test state
function M.get_usage(theme)
  return (test_state.usage or {})[theme] or 0
end

--- Get full usage map from test state
function M.get_all_usage()
  return test_state.usage or {}
end

--- Get or set collapsed state
function M.collapsed(group_key, collapsed)
  test_state.collapsed = test_state.collapsed or {}

  if collapsed ~= nil then
    test_state.collapsed[group_key] = collapsed
  end

  return test_state.collapsed[group_key] or false
end

--- Get current sort mode
function M.get_sort_mode()
  local mode = test_state.sort_mode or "alpha"
  if mode == "alphabetical" then
    mode = "alpha"
  end
  return mode
end

--- Set current sort mode
function M.set_sort_mode(mode)
  test_state.sort_mode = mode
end

--- Get auto-apply flag
function M.get_auto_apply()
  return test_state.auto_apply or false
end

--- Set auto-apply flag
function M.set_auto_apply(enabled)
  test_state.auto_apply = enabled and true or false
end

--- Get quick slots table
function M.get_quick_slots_table()
  return test_state.quick_slots or { __global = {} }
end

--- Get quick slots map for a scope
function M.get_quick_slots(scope)
  scope = scope or "__global"
  local all = M.get_quick_slots_table()
  if type(all[scope]) ~= "table" then
    return {}
  end
  return all[scope]
end

--- Set a quick slot
function M.set_quick_slot(slot, theme, scope)
  local normalize_slot = function(s)
    if type(s) == "number" then
      s = tostring(s)
    end
    if type(s) ~= "string" then
      return nil
    end
    if not s:match("^[0-9]$") then
      return nil
    end
    return s
  end

  slot = normalize_slot(slot)
  scope = scope or "__global"
  if not slot then
    return
  end
  if not theme or theme == "" then
    return
  end

  test_state.quick_slots = test_state.quick_slots or { __global = {} }
  if type(test_state.quick_slots[scope]) ~= "table" then
    test_state.quick_slots[scope] = {}
  end
  test_state.quick_slots[scope][slot] = theme
  return theme
end

--- Clear a quick slot
function M.clear_quick_slot(slot, scope)
  local normalize_slot = function(s)
    if type(s) == "number" then
      s = tostring(s)
    end
    if type(s) ~= "string" then
      return nil
    end
    if not s:match("^[0-9]$") then
      return nil
    end
    return s
  end

  slot = normalize_slot(slot)
  scope = scope or "__global"
  if not slot then
    return
  end
  test_state.quick_slots = test_state.quick_slots or { __global = {} }
  if type(test_state.quick_slots[scope]) ~= "table" then
    return
  end
  test_state.quick_slots[scope][slot] = nil
end

--- Get a single quick slot theme
function M.get_quick_slot(slot, scope)
  local normalize_slot = function(s)
    if type(s) == "number" then
      s = tostring(s)
    end
    if type(s) ~= "string" then
      return nil
    end
    if not s:match("^[0-9]$") then
      return nil
    end
    return s
  end

  slot = normalize_slot(slot)
  scope = scope or "__global"
  if not slot then
    return nil
  end
  local slots = M.get_quick_slots(scope)
  return slots[slot]
end

--- Push theme onto undo stack in test state
function M.undo_push(theme)
  local undo = test_state.undo_history or {
    stack = {},
    index = 0,
    max_size = 100,
  }

  while #undo.stack > undo.index do
    table.remove(undo.stack)
  end

  for i = #undo.stack, 1, -1 do
    if undo.stack[i] == theme then
      table.remove(undo.stack, i)
      if i <= undo.index then
        undo.index = undo.index - 1
      end
    end
  end

  table.insert(undo.stack, theme)
  undo.index = #undo.stack

  local max_size = undo.max_size or 100
  while #undo.stack > max_size do
    table.remove(undo.stack, 1)
    undo.index = undo.index - 1
  end

  test_state.undo_history = undo
end

--- Undo to previous theme in test state
function M.undo_pop()
  local undo = test_state.undo_history
  if not undo or undo.index <= 1 then
    return nil
  end

  undo.index = undo.index - 1
  test_state.undo_history = undo

  return undo.stack[undo.index]
end

--- Redo to next theme in test state
function M.redo_pop()
  local undo = test_state.undo_history
  if not undo or undo.index >= #undo.stack then
    return nil
  end

  undo.index = undo.index + 1
  test_state.undo_history = undo

  return undo.stack[undo.index]
end

return M
