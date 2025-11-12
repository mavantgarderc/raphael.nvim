local M = {}

local history = require("raphael.theme_history")

local async_write = function(path, contents)
  ---@diagnostic disable-next-line: undefined-field
  vim.loop.fs_open(path, "w", 438, function(err, fd)
    if err then
      vim.schedule(function()
        vim.notify("raphael: failed to write state: " .. tostring(err), vim.log.levels.WARN)
      end)
      return
    end
    ---@diagnostic disable-next-line: undefined-field
    vim.loop.fs_write(fd, contents, -1, function(write_err)
      if write_err and write_err ~= 0 then
        vim.schedule(function()
          vim.notify("raphael: failed to write state (write): " .. tostring(write_err), vim.log.levels.WARN)
        end)
      end
      ---@diagnostic disable-next-line: undefined-field
      vim.loop.fs_close(fd)
    end)
  end)
end

function M.load(config)
  local state_file = config.state_file
  local d = vim.fn.fnamemodify(state_file, ":h")
  if vim.fn.isdirectory(d) == 0 then
    vim.fn.mkdir(d, "p")
  end

  local f = io.open(state_file, "r")
  if not f then
    local default_state = {
      current = config.default_theme,
      saved = config.default_theme,
      previous = nil,
      auto_apply = false,
      bookmarks = {},
      collapsed = {},
      history = {},
      sort_mode = config.sort_mode,
      usage = {},
      undo_history = nil,
    }
    local payload = vim.fn.json_encode(default_state)
    async_write(state_file, payload)
    return default_state
  end

  local content = f:read("*a")
  f:close()

  local ok, decoded = pcall(vim.fn.json_decode, content)
  if not ok or type(decoded) ~= "table" then
    local default_state = {
      current = config.default_theme,
      saved = config.default_theme,
      previous = nil,
      auto_apply = false,
      bookmarks = {},
      collapsed = {},
      history = {},
      sort_mode = config.sort_mode,
      usage = {},
      undo_history = nil,
    }
    local payload = vim.fn.json_encode(default_state)
    async_write(state_file, payload)
    return default_state
  end

  local state = {
    current = decoded.current or config.default_theme,
    saved = decoded.saved or decoded.current or config.default_theme,
    previous = decoded.previous,
    auto_apply = decoded.auto_apply == true,
    bookmarks = decoded.bookmarks or {},
    collapsed = decoded.collapsed or {},
    history = decoded.history or {},
    sort_mode = decoded.sort_mode or config.sort_mode,
    usage = decoded.usage or {},
    undo_history = decoded.undo_history,
  }

  if state.undo_history then
    history.deserialize(state.undo_history)
  end

  return state
end

function M.save(state, config)
  state.undo_history = history.serialize()
  local payload = vim.fn.json_encode(state)
  async_write(config.state_file, payload)
end

return M
