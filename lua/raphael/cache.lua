local M = {}

local state_file = vim.fn.stdpath("data") .. "/raphael/state.json"

local function ensure_dir()
  local dir = vim.fn.fnamemodify(state_file, ":h")
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
end

-- default state generator
local function default_state()
  return {
    enabled = false,
    current = "kanagawa-paper-ink",
    previous = nil,
    history = {},
    bookmarks = {},
  }
end

function M.load_state(state)
  ensure_dir()
  local fd = io.open(state_file, "r")
  if not fd then
    -- create default file asynchronously
    local payload = vim.fn.json_encode(default_state())
    -- write async
    vim.loop.fs_open(state_file, "w", 438, function(err, fdw)
      if err then
        return
      end
      vim.loop.fs_write(fdw, payload, -1, function()
        vim.loop.fs_close(fdw)
      end)
    end)
    -- merge defaults into provided state
    local d = default_state()
    for k, v in pairs(d) do
      state[k] = v
    end
    return
  end

  local content = fd:read("*a")
  fd:close()
  local ok, decoded = pcall(vim.fn.json_decode, content)
  if ok and type(decoded) == "table" then
    -- merge with defaults to ensure keys exist
    local d = default_state()
    for k, v in pairs(d) do
      state[k] = decoded[k] ~= nil and decoded[k] or v
    end
  else
    -- failed decode: write defaults back
    local payload = vim.fn.json_encode(default_state())
    vim.loop.fs_open(state_file, "w", 438, function(err, fdw)
      if err then
        return
      end
      vim.loop.fs_write(fdw, payload, -1, function()
        vim.loop.fs_close(fdw)
      end)
    end)
    local d = default_state()
    for k, v in pairs(d) do
      state[k] = v
    end
  end
end

function M.save_state(state)
  ensure_dir()
  local payload = vim.fn.json_encode(state)
  vim.loop.fs_open(state_file, "w", 438, function(err, fd)
    if err then
      return
    end
    vim.loop.fs_write(fd, payload, -1, function()
      vim.loop.fs_close(fd)
    end)
  end)
end

function M.add_history(theme, state)
  table.insert(state.history, 1, theme)
  if #state.history > 5 then
    table.remove(state.history)
  end
end

function M.toggle_bookmark(theme, state)
  if not theme or theme == "" then
    return
  end
  local idx = vim.fn.index(state.bookmarks, theme)
  if idx >= 0 then
    table.remove(state.bookmarks, idx + 1)
    vim.notify("Raphael: removed bookmark " .. theme)
  else
    table.insert(state.bookmarks, theme)
    vim.notify("Raphael: bookmarked " .. theme)
  end
  M.save_state(state)
end

return M
