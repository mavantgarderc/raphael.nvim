-- lua/raphael/init.lua
local M = {}

M.defaults = {
  leader = "<leader>t",
  mappings = { picker = "p", next = "n", previous = "N", random = "r" },
  default_theme = "kanagawa-wave",
  state_file = vim.fn.stdpath("data") .. "/raphael/state.json",
}

M.state = nil  -- Loaded in setup

local function async_write(path, contents)
  vim.loop.fs_open(path, "w", 438, function(err, fd)
    if err then
      vim.schedule(function()
        vim.notify("raphael: failed to write state: " .. tostring(err), vim.log.levels.WARN)
      end)
      return
    end
    vim.loop.fs_write(fd, contents, -1, function(write_err)
      if write_err and write_err ~= 0 then
        vim.schedule(function()
          vim.notify("raphael: failed to write state (write): " .. tostring(write_err), vim.log.levels.WARN)
        end)
      end
      vim.loop.fs_close(fd)
    end)
  end)
end

function M.load_state()
  local d = vim.fn.fnamemodify(M.config.state_file, ":h")
  if vim.fn.isdirectory(d) == 0 then
    vim.fn.mkdir(d, "p")
  end

  local f = io.open(M.config.state_file, "r")
  if not f then
    M.state = vim.deepcopy(M.defaults.state or {
      current = M.config.default_theme,
      previous = nil,
      auto_apply = false,
      bookmarks = {},
      collapsed = {},
    })
    local payload = vim.fn.json_encode(M.state)
    async_write(M.config.state_file, payload)
    return
  end

  local content = f:read("*a")
  f:close()

  local ok, decoded = pcall(vim.fn.json_decode, content)
  if not ok or type(decoded) ~= "table" then
    M.state = vim.deepcopy(M.defaults.state or {})
    local payload = vim.fn.json_encode(M.state)
    async_write(M.config.state_file, payload)
    return
  end

  M.state = decoded
end

function M.save_state()
  local payload = vim.fn.json_encode(M.state)
  async_write(M.config.state_file, payload)
end

function M.apply(theme)
  local themes = require("raphael.themes")
  if not theme or not themes.is_available(theme) then
    vim.notify("raphael: theme not available: " .. tostring(theme), vim.log.levels.WARN)
    return
  end
  M.state.previous = M.state.current
  local ok, err = pcall(vim.cmd.colorscheme, theme)
  if not ok then
    vim.notify("raphael: failed to apply theme '" .. tostring(theme) .. "': " .. tostring(err), vim.log.levels.ERROR)
    if themes.is_available(M.config.default_theme) then
      pcall(vim.cmd.colorscheme, M.config.default_theme)
      M.state.current = M.config.default_theme
    end
    M.save_state()
    return
  end
  M.state.current = theme
  M.save_state()
  vim.notify("raphael: applied " .. theme)
end

function M.toggle_auto()
  M.state.auto_apply = not M.state.auto_apply
  vim.g.raphael_auto_theme = M.state.auto_apply
  M.save_state()
  vim.notify(M.state.auto_apply and "raphael auto-theme: ON" or "raphael auto-theme: OFF")
end

function M.toggle_bookmark(theme)
  if not theme or theme == "" then
    return
  end
  local idx = vim.fn.index(M.state.bookmarks or {}, theme)
  if idx >= 0 then
    table.remove(M.state.bookmarks, idx + 1)
    vim.notify("raphael: removed bookmark " .. theme)
  else
    table.insert(M.state.bookmarks, theme)
    vim.notify("raphael: bookmarked " .. theme)
  end
  M.save_state()
end

function M.open_picker()
  require("raphael.picker").open(M)
end

function M.setup(user_config)
  M.config = vim.tbl_deep_extend("force", M.defaults, user_config or {})

  -- Load dependencies
  local colors = require("raphael.colors")
  local themes = require("raphael.themes")
  themes.theme_map = colors.theme_map
  themes.filetype_themes = colors.filetype_themes
  if user_config and user_config.filetype_themes then
    themes.merge_user_config(user_config)
  end
  themes.refresh()

  M.load_state()

  vim.g.raphael_auto_theme = M.state.auto_apply == true

  -- Setup autocmds
  require("raphael.autocmds").setup(M)

  -- Setup commands
  require("raphael.commands").setup(M)

  -- Setup keymaps
  require("raphael.keymaps").setup(M)

  -- FileType autocmd for auto_apply
  vim.api.nvim_create_autocmd("FileType", {
    callback = function(args)
      if not M.state.auto_apply then
        return
      end
      local ft = args.match
      local theme = themes.filetype_themes[ft]
      if theme and themes.is_available(theme) then
        M.apply(theme)
      end
    end,
  })

  -- Apply initial theme (scheduled for lazy loading)
  vim.schedule(function()
    local themes = require("raphael.themes")
    if themes.is_available(M.state.current) then
      pcall(vim.cmd.colorscheme, M.state.current)
    else
      if themes.is_available(M.config.default_theme) then
        pcall(vim.cmd.colorscheme, M.config.default_theme)
        M.state.current = M.config.default_theme
        M.save_state()
      else
        vim.notify("raphael: fallback theme not found", vim.log.levels.WARN)
      end
    end
  end)
end

return M
