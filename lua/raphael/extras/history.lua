-- lua/raphael/extras/history.lua
-- High-level history & undo/redo API for raphael.nvim.
--
-- Responsibilities:
--   - Track a stack of manually applied themes (max N entries)
--   - Provide undo/redo navigation
--   - Provide stats, jump, and introspection helpers
--
-- Storage model:
--   - On disk, all data lives inside core/cache.lua's persistent state:
--       state.undo_history = {
--         stack    = { "theme1", "theme2", ... },
--         index    = N,      -- current position
--         max_size = number, -- maximum stack length
--       }
--   - This module always:
--       1. Reads JSON from cache.read()
--       2. Normalizes undo_history
--       3. Mutates it
--       4. Writes back via cache.write()

local cache = require("raphael.core.cache")
local C = require("raphael.constants")

local M = {}

--- Get state + undo_history, ensuring structure is sane.
---
--- Guarantees:
---   - state.undo_history exists and has:
---       * stack    : table
---       * index    : integer
---       * max_size : integer (defaults to C.HISTORY_MAX_SIZE)
---
---@return table state  # full persistent state table
---@return table undo   # reference to state.undo_history
local function get_undo_state()
  local state = cache.read()
  local undo = state.undo_history or {}

  undo.stack = undo.stack or {}
  undo.index = undo.index or 0
  undo.max_size = undo.max_size or C.HISTORY_MAX_SIZE

  state.undo_history = undo
  return state, undo
end

--- Persist an updated undo_history back to disk.
---
--- @param state table
local function save_undo_state(state)
  cache.write(state)
end

-- ────────────────────────────────────────────────────────────────────────
-- Public API
-- ────────────────────────────────────────────────────────────────────────

--- Add a theme to the undo stack.
---
--- Semantics (mirrors old theme_history.add):
---   - If we've undone some steps (index < #stack), truncate forward history.
---   - Remove older duplicates of this theme.
---   - Append theme at the end and move index to the new tail.
---   - Enforce max_size by dropping from the front.
---
---@param theme string|nil
function M.add(theme)
  if not theme or theme == "" then
    return
  end

  local state, undo = get_undo_state()
  local stack = undo.stack
  local idx = undo.index or 0
  local max_size = undo.max_size or C.HISTORY_MAX_SIZE

  if idx < #stack then
    for i = #stack, idx + 1, -1 do
      table.remove(stack, i)
    end
  end

  for i = #stack, 1, -1 do
    if stack[i] == theme then
      table.remove(stack, i)
      if i <= idx then
        idx = idx - 1
      end
    end
  end

  table.insert(stack, theme)
  idx = #stack

  while #stack > max_size do
    table.remove(stack, 1)
    idx = idx - 1
  end

  undo.stack = stack
  undo.index = idx
  undo.max_size = max_size

  save_undo_state(state)
end

--- Undo to previous theme.
---
--- Moves `index` one step back in the stack and optionally applies the theme.
---
---@param apply_fn fun(theme:string)|nil  Optional callback to actually apply the theme.
---@return string|nil theme  The undone-to theme, or nil if no more history.
function M.undo(apply_fn)
  local state, undo = get_undo_state()
  local stack = undo.stack
  local idx = undo.index or 0

  if idx <= 1 or #stack == 0 then
    vim.notify(C.ICON.UNDO_ICON .. " Undo: no more history", vim.log.levels.INFO)
    return nil
  end

  idx = idx - 1
  undo.index = idx
  save_undo_state(state)

  local theme = stack[idx]
  if apply_fn and theme then
    apply_fn(theme)
  end

  vim.notify(string.format("%s Undo: %s (%d/%d)", C.ICON.UNDO_ICON, theme, idx, #stack), vim.log.levels.INFO)

  return theme
end

--- Redo to next theme.
---
--- Moves `index` one step forward in the stack and optionally applies the theme.
---
---@param apply_fn fun(theme:string)|nil  Optional callback to actually apply the theme.
---@return string|nil theme  The redone-to theme, or nil if no more history.
function M.redo(apply_fn)
  local state, undo = get_undo_state()
  local stack = undo.stack
  local idx = undo.index or 0

  if idx >= #stack or #stack == 0 then
    vim.notify(C.ICON.REDO_ICON .. " Redo: no more history", vim.log.levels.INFO)
    return nil
  end

  idx = idx + 1
  undo.index = idx
  save_undo_state(state)

  local theme = stack[idx]
  if apply_fn and theme then
    apply_fn(theme)
  end

  vim.notify(string.format("%s Redo: %s (%d/%d)", C.ICON.REDO_ICON, theme, idx, #stack), vim.log.levels.INFO)

  return theme
end

--- Get the current theme from the undo stack's point of view.
---
---@return string|nil
function M.current()
  local _, undo = get_undo_state()
  local stack = undo.stack
  local idx = undo.index or 0

  if idx > 0 and idx <= #stack then
    return stack[idx]
  end
  return nil
end

--- Whether undo is possible (index > 1).
---
---@return boolean
function M.can_undo()
  local _, undo = get_undo_state()
  return (undo.index or 0) > 1
end

--- Whether redo is possible (index < #stack).
---
---@return boolean
function M.can_redo()
  local _, undo = get_undo_state()
  local stack = undo.stack
  return (undo.index or 0) < #stack
end

--- Show a compact notification with the tail of the history stack.
---
--- Shows up to the last 10 entries, marking the current one with "→".
function M.show()
  local _, undo = get_undo_state()
  local stack = undo.stack
  local idx = undo.index or 0

  if #stack == 0 then
    vim.notify(C.ICON.HISTORY .. " No theme history", vim.log.levels.INFO)
    return
  end

  local lines = { C.ICON.HISTORY .. " Theme History:", "" }

  local start_idx = math.max(1, #stack - 9)
  for i = start_idx, #stack do
    local marker = (i == idx) and "→ " or "  "
    local num = string.format("[%d]", i)
    table.insert(lines, string.format("%s%s %s", marker, num, stack[i]))
  end

  table.insert(lines, "")
  table.insert(
    lines,
    string.format(
      "Position: %d/%d | Can undo: %s | Can redo: %s",
      idx,
      #stack,
      M.can_undo() and "yes" or "no",
      M.can_redo() and "yes" or "no"
    )
  )

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

--- Jump to an arbitrary position in the undo stack.
---
--- Semantics:
---   - Validates that position is in [1, #stack]
---   - Sets undo.index = position
---   - Optionally applies the theme via apply_fn
---
---@param position integer 1-based index in the stack
---@param apply_fn fun(theme:string)|nil  Optional callback to apply the target theme
---@return string|nil theme  The jumped-to theme, or nil on error
function M.jump(position, apply_fn)
  local state, undo = get_undo_state()
  local stack = undo.stack

  if position < 1 or position > #stack then
    vim.notify(string.format("Invalid position: %d (valid: 1-%d)", position, #stack), vim.log.levels.ERROR)
    return nil
  end

  undo.index = position
  save_undo_state(state)

  local theme = stack[position]
  if apply_fn and theme then
    apply_fn(theme)
  end

  vim.notify(string.format("Jumped to: %s (%d/%d)", theme, undo.index, #stack), vim.log.levels.INFO)

  return theme
end

--- Compute statistics over the undo stack.
---
--- Returns a table:
---   {
---     total            = number,        -- total entries in stack
---     position         = number,        -- current index
---     can_undo         = boolean,
---     can_redo         = boolean,
---     unique_themes    = number,
---     most_used        = string|nil,
---     most_used_count  = number,
---     recent           = string|nil,    -- last entry in stack
---   }
---
---@return table stats
function M.stats()
  local _, undo = get_undo_state()
  local stack = undo.stack
  local idx = undo.index or 0

  if #stack == 0 then
    return {
      total = 0,
      position = 0,
      can_undo = false,
      can_redo = false,
      unique_themes = 0,
      most_used = nil,
      most_used_count = 0,
      recent = nil,
    }
  end

  local counts = {}
  for _, theme in ipairs(stack) do
    counts[theme] = (counts[theme] or 0) + 1
  end

  local most_used, max_count = nil, 0
  for theme, count in pairs(counts) do
    if count > max_count then
      max_count = count
      most_used = theme
    end
  end

  return {
    total = #stack,
    position = idx,
    can_undo = M.can_undo(),
    can_redo = M.can_redo(),
    unique_themes = vim.tbl_count(counts),
    most_used = most_used,
    most_used_count = max_count,
    recent = stack[#stack],
  }
end

--- Clear the undo stack entirely.
---
--- Preserves undo.max_size but resets:
---   - stack = {}
---   - index = 0
function M.reset()
  local state, undo = get_undo_state()
  undo.stack = {}
  undo.index = 0
  -- keep undo.max_size as-is
  save_undo_state(state)

  vim.notify("Theme history cleared", vim.log.levels.INFO)
end

--- Serialize undo_history for embedding into other structures.
---
--- Returns a shallow table suitable for persistence:
---   { stack = {...}, index = N, max_size = M }
---
---@return table
function M.serialize()
  local _, undo = get_undo_state()
  return {
    stack = vim.deepcopy(undo.stack),
    index = undo.index or 0,
    max_size = undo.max_size or C.HISTORY_MAX_SIZE,
  }
end

--- Restore undo_history from serialized data.
---
--- Does not apply any themes; it only updates the stored undo_history.
---
---@param data table|nil
function M.deserialize(data)
  if type(data) ~= "table" then
    return
  end

  local state = cache.read()
  local undo = {
    stack = data.stack or {},
    index = data.index or 0,
    max_size = data.max_size or C.HISTORY_MAX_SIZE,
  }

  if undo.index > #undo.stack then
    undo.index = #undo.stack
  elseif undo.index < 0 then
    undo.index = 0
  end

  state.undo_history = undo
  cache.write(state)
end

--- Get the last `count` entries as a slice, marking the current one.
---
--- Each entry in the slice is:
---   {
---     index      = integer,    -- absolute index in the full stack
---     theme      = string,
---     is_current = boolean,
---   }
---
---@param count integer|nil  # how many items from the end (default 10)
---@return table[]
function M.get_slice(count)
  count = count or 10
  local _, undo = get_undo_state()
  local stack = undo.stack
  local idx = undo.index or 0

  local start_idx = math.max(1, #stack - count + 1)
  local slice = {}

  for i = start_idx, #stack do
    table.insert(slice, {
      index = i,
      theme = stack[i],
      is_current = (i == idx),
    })
  end

  return slice
end

return M
