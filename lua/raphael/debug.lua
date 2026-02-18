-- lua/raphael/debug.lua
-- Debug and diagnostics module for raphael.nvim
--
-- Provides:
--   - State inspection and validation
--   - History repair
--   - Backup/restore
--   - Diagnostic commands

local M = {}

local constants = require("raphael.constants")
local themes = require("raphael.themes")

local LOG_LEVELS = { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3 }
local current_log_level = LOG_LEVELS.WARN
local log_buffer = {}
local MAX_LOG_ENTRIES = 100

local function log(level, msg, data)
  if level < current_log_level then
    return
  end

  local entry = {
    time = os.date("%H:%M:%S"),
    level = level,
    msg = msg,
    data = data,
  }

  table.insert(log_buffer, entry)
  while #log_buffer > MAX_LOG_ENTRIES do
    table.remove(log_buffer, 1)
  end
end

function M.set_log_level(level)
  if type(level) == "string" then
    level = LOG_LEVELS[level:upper()] or LOG_LEVELS.WARN
  end
  current_log_level = level
end

function M.debug(msg, data)
  log(LOG_LEVELS.DEBUG, msg, data)
end

function M.info(msg, data)
  log(LOG_LEVELS.INFO, msg, data)
end

function M.warn(msg, data)
  log(LOG_LEVELS.WARN, msg, data)
end

function M.error(msg, data)
  log(LOG_LEVELS.ERROR, msg, data)
end

function M.get_logs()
  return log_buffer
end

function M.clear_logs()
  log_buffer = {}
end

function M.get_state_file_path()
  return constants.STATE_FILE
end

function M.get_backup_path()
  return constants.STATE_FILE .. ".backup"
end

function M.read_raw_state()
  local file = io.open(constants.STATE_FILE, "r")
  if not file then
    return nil, "File not found"
  end
  local content = file:read("*a")
  file:close()
  return content, nil
end

function M.validate_state(state)
  local issues = {}
  local warnings = {}

  if type(state) ~= "table" then
    return { fatal = "State is not a table" }, {}
  end

  if state.current and not themes.is_available(state.current) then
    table.insert(warnings, "current theme '" .. tostring(state.current) .. "' not available")
  end

  if state.saved and not themes.is_available(state.saved) then
    table.insert(warnings, "saved theme '" .. tostring(state.saved) .. "' not available")
  end

  if state.previous and not themes.is_available(state.previous) then
    table.insert(warnings, "previous theme '" .. tostring(state.previous) .. "' not available")
  end

  if type(state.history) ~= "table" then
    table.insert(issues, "history is not a table, resetting")
  else
    local invalid = {}
    for i, theme in ipairs(state.history) do
      if type(theme) ~= "string" or theme == "" then
        table.insert(invalid, i)
      elseif not themes.is_available(theme) then
        table.insert(warnings, "history[" .. i .. "] theme '" .. theme .. "' not available")
      end
    end
    if #invalid > 0 then
      table.insert(issues, "history has " .. #invalid .. " invalid entries")
    end
  end

  if type(state.bookmarks) ~= "table" then
    table.insert(issues, "bookmarks is not a table, resetting")
  else
    for scope, list in pairs(state.bookmarks) do
      if type(list) ~= "table" then
        table.insert(issues, "bookmarks[" .. scope .. "] is not a list")
      else
        for i, theme in ipairs(list) do
          if type(theme) ~= "string" or theme == "" then
            table.insert(issues, "bookmarks[" .. scope .. "][" .. i .. "] is invalid")
          end
        end
      end
    end
  end

  if type(state.undo_history) ~= "table" then
    table.insert(issues, "undo_history is not a table, resetting")
  else
    if type(state.undo_history.stack) ~= "table" then
      table.insert(issues, "undo_history.stack is not a table")
    end
    if type(state.undo_history.index) ~= "number" then
      table.insert(issues, "undo_history.index is not a number")
    end
    if state.undo_history.index < 0 then
      table.insert(issues, "undo_history.index is negative")
    end
    if state.undo_history.stack and state.undo_history.index > #state.undo_history.stack then
      table.insert(warnings, "undo_history.index exceeds stack size")
    end
  end

  if type(state.quick_slots) ~= "table" then
    table.insert(issues, "quick_slots is not a table, resetting")
  end

  if type(state.usage) ~= "table" then
    table.insert(issues, "usage is not a table, resetting")
  end

  if state.current_profile ~= nil and type(state.current_profile) ~= "string" then
    table.insert(issues, "current_profile is not a string or nil")
  end

  if state.sort_mode ~= nil and type(state.sort_mode) ~= "string" then
    table.insert(issues, "sort_mode is not a string")
  end

  return issues, warnings
end

function M.repair_state(state)
  local repaired = vim.deepcopy(state)
  local repairs = {}

  local function fix(key, default)
    if repaired[key] == nil or type(repaired[key]) ~= type(default) then
      repaired[key] = default
      table.insert(repairs, "Fixed: " .. key)
    end
  end

  fix("current", nil)
  fix("saved", nil)
  fix("previous", nil)
  fix("auto_apply", false)

  if type(repaired.history) ~= "table" then
    repaired.history = {}
    table.insert(repairs, "Reset: history")
  else
    local clean = {}
    for _, theme in ipairs(repaired.history) do
      if type(theme) == "string" and theme ~= "" then
        table.insert(clean, theme)
      end
    end
    if #clean ~= #repaired.history then
      repaired.history = clean
      table.insert(repairs, "Cleaned: removed invalid history entries")
    end
  end

  if type(repaired.bookmarks) ~= "table" then
    repaired.bookmarks = { __global = {} }
    table.insert(repairs, "Reset: bookmarks")
  else
    for scope, list in pairs(repaired.bookmarks) do
      if vim.islist(list) then
        local clean = {}
        for _, theme in ipairs(list) do
          if type(theme) == "string" and theme ~= "" then
            table.insert(clean, theme)
          end
        end
        if #clean ~= #list then
          repaired.bookmarks[scope] = clean
          table.insert(repairs, "Cleaned: bookmarks[" .. scope .. "]")
        end
      end
    end
    if not repaired.bookmarks.__global then
      repaired.bookmarks.__global = {}
      table.insert(repairs, "Added: bookmarks.__global")
    end
  end

  if
    type(repaired.undo_history) ~= "table"
    or type(repaired.undo_history.stack) ~= "table"
    or type(repaired.undo_history.index) ~= "number"
  then
    repaired.undo_history = {
      stack = {},
      index = 0,
      max_size = constants.HISTORY_MAX_SIZE,
    }
    table.insert(repairs, "Reset: undo_history")
  else
    repaired.undo_history.index = math.max(0, math.min(repaired.undo_history.index, #repaired.undo_history.stack))
    if repaired.undo_history.index ~= state.undo_history.index then
      table.insert(repairs, "Fixed: undo_history.index clamped")
    end
  end

  if type(repaired.quick_slots) ~= "table" then
    repaired.quick_slots = { __global = {} }
    table.insert(repairs, "Reset: quick_slots")
  else
    if not repaired.quick_slots.__global then
      repaired.quick_slots.__global = {}
      table.insert(repairs, "Added: quick_slots.__global")
    end
  end

  fix("usage", {})
  fix("collapsed", {})

  if repaired.current_profile ~= nil and type(repaired.current_profile) ~= "string" then
    repaired.current_profile = nil
    table.insert(repairs, "Fixed: current_profile set to nil")
  end

  if repaired.sort_mode ~= nil and type(repaired.sort_mode) ~= "string" then
    repaired.sort_mode = "alpha"
    table.insert(repairs, "Fixed: sort_mode set to alpha")
  end

  return repaired, repairs
end

function M.backup_state()
  local content, err = M.read_raw_state()
  if not content then
    return false, err
  end

  local backup_path = M.get_backup_path()
  local file, ferr = io.open(backup_path, "w")
  if not file then
    return false, ferr
  end

  file:write(content)
  file:close()
  return true, nil
end

function M.restore_backup()
  local backup_path = M.get_backup_path()
  local file = io.open(backup_path, "r")
  if not file then
    return false, "No backup file found"
  end

  local content = file:read("*a")
  file:close()

  local ok, _ = pcall(vim.json.decode, content)
  if not ok then
    return false, "Backup file is corrupted"
  end

  local main_file = io.open(constants.STATE_FILE, "w")
  if not main_file then
    return false, "Cannot write state file"
  end

  main_file:write(content)
  main_file:close()
  return true, nil
end

function M.health_check()
  local results = {
    status = "ok",
    state_file = "unknown",
    backup = "unknown",
    validation = {},
    warnings = {},
    repairs_needed = {},
  }

  local dir = vim.fn.fnamemodify(constants.STATE_FILE, ":h")
  if vim.fn.isdirectory(dir) == 0 then
    results.state_file = "directory missing"
    results.status = "error"
    return results
  end

  local file = io.open(constants.STATE_FILE, "r")
  if not file then
    results.state_file = "not found (will be created)"
    results.status = "ok"
    return results
  end
  file:close()
  results.state_file = "exists"

  local content, err = M.read_raw_state()
  if not content then
    results.state_file = "cannot read: " .. tostring(err)
    results.status = "error"
    return results
  end

  local ok, _ = pcall(vim.json.decode, content)
  if not ok then
    results.state_file = "invalid JSON"
    results.status = "error"
    results.validation = { fatal = "JSON decode failed" }
    return results
  end

  local cache = require("raphael.core.cache")
  local state = cache.read()
  local issues, warnings = M.validate_state(state)

  results.validation = issues
  results.warnings = warnings

  if #issues > 0 then
    results.status = "needs_repair"
    results.repairs_needed = issues
  elseif #warnings > 0 then
    results.status = "warnings"
  end

  local backup_file = io.open(M.get_backup_path(), "r")
  if backup_file then
    backup_file:close()
    results.backup = "exists"
  else
    results.backup = "none"
  end

  return results
end

function M.show_diagnostics()
  local health = M.health_check()

  local lines = {
    "╔════════════════════════════════════════╗",
    "║       Raphael Diagnostics              ║",
    "╚════════════════════════════════════════╝",
    "",
    "State file: " .. constants.STATE_FILE,
    "Status:     " .. health.status,
    "Backup:     " .. health.backup,
    "",
  }

  if health.validation and #health.validation > 0 then
    table.insert(lines, "Issues:")
    for _, issue in ipairs(health.validation) do
      table.insert(lines, "  - " .. issue)
    end
    table.insert(lines, "")
  end

  if health.warnings and #health.warnings > 0 then
    table.insert(lines, "Warnings:")
    for _, warning in ipairs(health.warnings) do
      table.insert(lines, "  - " .. warning)
    end
    table.insert(lines, "")
  end

  local cache = require("raphael.core.cache")
  local state = cache.read()

  table.insert(lines, "Current state:")
  table.insert(lines, "  current:  " .. tostring(state.current))
  table.insert(lines, "  saved:    " .. tostring(state.saved))
  table.insert(lines, "  previous: " .. tostring(state.previous))
  table.insert(lines, "  history:  " .. #state.history .. " entries")
  table.insert(lines, "  bookmarks: " .. vim.tbl_count(state.bookmarks) .. " scopes")
  table.insert(
    lines,
    "  undo_stack: " .. #state.undo_history.stack .. " entries (index: " .. state.undo_history.index .. ")"
  )

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
  return health
end

function M.repair_and_save()
  local cache = require("raphael.core.cache")

  M.backup_state()

  local state = cache.read()
  local repaired, repairs = M.repair_state(state)

  if #repairs > 0 then
    vim.notify("Raphael: Repaired " .. #repairs .. " issues:\n" .. table.concat(repairs, "\n"), vim.log.levels.INFO)
  else
    vim.notify("Raphael: State is healthy, no repairs needed", vim.log.levels.INFO)
  end

  cache.write(repaired)
  return repaired, repairs
end

function M.export_state(path)
  local content, err = M.read_raw_state()
  if not content then
    return false, err
  end

  path = path or vim.fn.stdpath("config") .. "/raphael/state_export.json"
  local file, ferr = io.open(path, "w")
  if not file then
    return false, ferr
  end

  file:write(content)
  file:close()
  vim.notify("State exported to: " .. path, vim.log.levels.INFO)
  return true, path
end

function M.get_stats()
  local cache = require("raphael.core.cache")
  local state = cache.read()

  return {
    state_file = constants.STATE_FILE,
    backup_file = M.get_backup_path(),
    has_backup = vim.fn.filereadable(M.get_backup_path()) == 1,
    current = state.current,
    saved = state.saved,
    history_count = #(state.history or {}),
    bookmarks_count = vim.tbl_count(state.bookmarks or {}),
    undo_stack_size = #(state.undo_history and state.undo_history.stack or {}),
    undo_index = state.undo_history and state.undo_history.index or 0,
    quick_slots_count = vim.tbl_count(state.quick_slots or {}),
    log_entries = #log_buffer,
  }
end

return M
