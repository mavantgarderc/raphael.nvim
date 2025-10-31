local M = {}

M.defaults = {
  leader = "<leader>t",
  mappings = { picker = "p", next = ">", previous = "<", random = "r" },
  default_theme = "kanagawa-paper-ink",
  state_file = vim.fn.stdpath("data") .. "/raphael/state.json",
  theme_map = nil,
  filetype_themes = {},
}

M.state = nil
local themes = require("raphael.themes")

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
    M.state = {
      current = M.config.default_theme,
      previous = nil,
      auto_apply = false,
      bookmarks = {},
      collapsed = {},
    }
    local payload = vim.fn.json_encode(M.state)
    async_write(M.config.state_file, payload)
    return
  end

  local content = f:read("*a")
  f:close()

  local ok, decoded = pcall(vim.fn.json_decode, content)
  if not ok or type(decoded) ~= "table" then
    M.state = {
      current = M.config.default_theme,
      previous = nil,
      auto_apply = false,
      bookmarks = {},
      collapsed = {},
    }
    local payload = vim.fn.json_encode(M.state)
    async_write(M.config.state_file, payload)
    return
  end

  -- merge with defaults to ensure all fields exist
  M.state = {
    current = decoded.current or M.config.default_theme,
    previous = decoded.previous,
    auto_apply = decoded.auto_apply == true,
    bookmarks = decoded.bookmarks or {},
    collapsed = decoded.collapsed or {},
  }
end

function M.save_state()
  local payload = vim.fn.json_encode(M.state)
  async_write(M.config.state_file, payload)
end

function M.apply(theme)
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

function M.open_picker(opts)
  require("raphael.picker").open(M, opts)
end

function M.refresh_and_reload()
  themes.refresh()
  if M.state.current and themes.is_available(M.state.current) then
    M.apply(M.state.current)
  else
    vim.notify("raphael: current theme not available after refresh", vim.log.levels.WARN)
  end
end

function M.show_status()
  local auto_status = M.state.auto_apply and "ON" or "OFF"
  vim.notify(
    string.format("raphael: current theme - %s | auto-apply: %s", M.state.current or "none", auto_status),
    vim.log.levels.INFO
  )
end

function M.show_help()
  local help_lines = {
    "=== Raphael Theme Manager ===",
    "",
    "Keymaps:",
    "  <leader>tp : Open picker (configured themes only)",
    "  <leader>t/ : Open picker (all other installed themes)",
    "  <leader>ta : Toggle auto-apply by filetype",
    "  <leader>tR : Refresh theme list and reload current",
    "  <leader>ts : Show current theme status",
    "  <leader>th : Show this help",
    "",
    "Inside Picker:",
    "  <CR>   : Apply theme",
    "  /      : Search themes",
    "  b      : Toggle bookmark",
    "  c      : Collapse/expand group",
    "  q/Esc  : Cancel (revert to previous)",
  }
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, help_lines)
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  local width = vim.o.columns
  local height = vim.o.lines
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = math.floor(width * 0.6),
    height = math.floor(height * 0.5),
    col = math.floor((width - width * 0.6) / 2),
    row = math.floor((height - height * 0.5) / 2),
    style = "minimal",
    border = "rounded",
    title = "Raphael Help",
  })
  vim.keymap.set("n", "q", function() vim.api.nvim_win_close(win, true) end, { buffer = buf })
  vim.keymap.set("n", "<Esc>", function() vim.api.nvim_win_close(win, true) end, { buffer = buf })
end

function M.setup(user_config)
  user_config = user_config or {}
  M.config = vim.tbl_deep_extend("force", M.defaults, user_config)

  themes.refresh()

  themes.filetype_themes = user_config.filetype_themes or M.defaults.filetype_themes

  local all_installed = vim.tbl_keys(themes.installed)
  table.sort(all_installed)
  themes.theme_map = user_config.theme_map or all_installed
  local all_configured = themes.get_all_themes()
  local unavailable = {}
  for _, theme in ipairs(all_configured) do
    if not themes.is_available(theme) then
      table.insert(unavailable, theme)
    end
  end

  if #unavailable > 0 then
    vim.notify(
      "raphael: Some themes in theme_map are not installed (marked with 󰝧 ): " .. table.concat(unavailable, ", "),
      vim.log.levels.WARN
    )
  end

  -- validate filetype_themes and notify about unavailable ones
  local invalid_ft = {}
  for ft, theme in pairs(themes.filetype_themes) do
    if not themes.is_available(theme) then
      table.insert(invalid_ft, string.format("%s=%s", ft, theme))
    end
  end
  if #invalid_ft > 0 then
    vim.notify(
      "raphael: Some filetype themes are not installed (will use default): " .. table.concat(invalid_ft, ", "),
      vim.log.levels.WARN
    )
  end

  M.load_state()

  -- validate current theme on load
  if M.state.current and not themes.is_available(M.state.current) then
    vim.notify("raphael: Current theme '" .. M.state.current .. "' not available, falling back to default", vim.log.levels.WARN)
    M.state.current = M.config.default_theme
    M.save_state()
  end

  vim.g.raphael_auto_theme = M.state.auto_apply == true

  require("raphael.autocmds").setup(M)

  require("raphael.commands").setup(M)

  require("raphael.keymaps").setup(M)

  -- fileType autocmd for auto_apply
  vim.api.nvim_create_autocmd("FileType", {
    callback = function(args)
      if not M.state.auto_apply then
        return
      end
      local ft = args.match
      local theme = themes.filetype_themes[ft]
      if theme and themes.is_available(theme) then
        M.apply(theme)
      else
        -- fallback to default if filetype theme not available
        if theme and not themes.is_available(theme) then
          vim.notify(
            string.format("raphael: filetype theme '%s' for %s not available, using default", theme, ft),
            vim.log.levels.WARN
          )
          if themes.is_available(M.config.default_theme) then
            M.apply(M.config.default_theme)
          end
        end
      end
    end,
  })

  -- apply initial theme (scheduled for lazy loading)
  vim.schedule(function()
    if M.state.current and themes.is_available(M.state.current) then
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
