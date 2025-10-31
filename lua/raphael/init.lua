-- lua/raphael/init.lua
local M = {}

M.defaults = {
  leader = "<leader>t",
  mappings = { picker = "p", next = ">", previous = "<", random = "r" },
  default_theme = "kanagawa-paper-ink",
  state_file = vim.fn.stdpath("data") .. "/raphael/state.json",
  theme_map = nil,
  filetype_themes = {},
}

M.state = nil  -- Loaded in setup
M.manual_apply = false  -- Track if theme was manually applied

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
      saved = M.config.default_theme,
      previous = nil,
      auto_apply = false,
      bookmarks = {},
      collapsed = {},
      history = {},
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
      saved = M.config.default_theme,
      previous = nil,
      auto_apply = false,
      bookmarks = {},
      collapsed = {},
      history = {},
    }
    local payload = vim.fn.json_encode(M.state)
    async_write(M.config.state_file, payload)
    return
  end

  -- Merge with defaults to ensure all fields exist
  M.state = {
    current = decoded.current or M.config.default_theme,
    saved = decoded.saved or decoded.current or M.config.default_theme,
    previous = decoded.previous,
    auto_apply = decoded.auto_apply == true,
    bookmarks = decoded.bookmarks or {},
    collapsed = decoded.collapsed or {},
    history = decoded.history or {},
  }
end

function M.save_state()
  local payload = vim.fn.json_encode(M.state)
  async_write(M.config.state_file, payload)
end

function M.add_to_history(theme)
  if not theme then return end
  
  -- Remove theme if it already exists in history
  for i = #M.state.history, 1, -1 do
    if M.state.history[i] == theme then
      table.remove(M.state.history, i)
    end
  end
  
  -- Add to front of history
  table.insert(M.state.history, 1, theme)
  
  -- Keep only last 5
  while #M.state.history > 5 do
    table.remove(M.state.history)
  end
end

function M.apply(theme, from_manual)
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
  M.add_to_history(theme)
  
  -- Only update saved theme if manually applied (from picker)
  if from_manual then
    M.state.saved = theme
  end
  
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
  local themes = require("raphael.themes")
  themes.refresh()
  if M.state.current and themes.is_available(M.state.current) then
    M.apply(M.state.current, false)
  else
    vim.notify("raphael: current theme not available after refresh", vim.log.levels.WARN)
  end
end

function M.show_status()
  local auto_status = M.state.auto_apply and "ON" or "OFF"
  local saved_info = M.state.saved and M.state.saved ~= M.state.current 
    and string.format(" | saved: %s", M.state.saved)
    or ""
  
  vim.notify(
    string.format("raphael: current - %s%s | auto-apply: %s", 
      M.state.current or "none", 
      saved_info,
      auto_status
    ),
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
    "",
    "Theme Persistence:",
    "  - Manual selections saved for next session",
    "  - Auto-apply changes not saved",
    "  - Last 5 themes kept in history",
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
    height = math.floor(height * 0.6),
    col = math.floor((width - width * 0.6) / 2),
    row = math.floor((height - height * 0.6) / 2),
    style = "minimal",
    border = "rounded",
    title = "Raphael Help",
  })
  vim.keymap.set("n", "q", function() vim.api.nvim_win_close(win, true) end, { buffer = buf })
  vim.keymap.set("n", "<Esc>", function() vim.api.nvim_win_close(win, true) end, { buffer = buf })
end

-- Export theme info for session saving
function M.export_for_session()
  return string.format(
    [[
" Raphael theme persistence
let g:raphael_session_theme = '%s'
let g:raphael_session_saved = '%s'
let g:raphael_session_auto = %s
]],
    M.state.current or M.config.default_theme,
    M.state.saved or M.config.default_theme,
    M.state.auto_apply and "1" or "0"
  )
end

-- Restore from session
function M.restore_from_session()
  local session_theme = vim.g.raphael_session_theme
  local session_saved = vim.g.raphael_session_saved
  local session_auto = vim.g.raphael_session_auto
  
  if session_theme then
    M.state.current = session_theme
    M.state.saved = session_saved or session_theme
    M.state.auto_apply = session_auto == 1
    
    local themes = require("raphael.themes")
    if themes.is_available(session_theme) then
      pcall(vim.cmd.colorscheme, session_theme)
    end
  end
end

function M.setup(user_config)
  user_config = user_config or {}
  M.config = vim.tbl_deep_extend("force", M.defaults, user_config)

  -- Load dependencies
  local themes = require("raphael.themes")
  themes.refresh()  -- Detect installed on startup

  -- Set filetype_themes (user override replaces)
  themes.filetype_themes = user_config.filetype_themes or M.defaults.filetype_themes

  -- Set theme_map (user override or default to flattened installed)
  local all_installed = vim.tbl_keys(themes.installed)
  table.sort(all_installed)  -- Alphabetical
  themes.theme_map = user_config.theme_map or all_installed

  -- NO automatic extras/Other group - only show what's configured
  -- Validate configured themes and mark unavailable ones
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

  -- Validate filetype_themes and notify about unavailable ones
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

  -- Validate saved theme on load
  if M.state.saved and not themes.is_available(M.state.saved) then
    vim.notify(
      "raphael: Saved theme '" .. M.state.saved .. "' not available, falling back to default",
      vim.log.levels.WARN
    )
    M.state.saved = M.config.default_theme
    M.save_state()
  end

  vim.g.raphael_auto_theme = M.state.auto_apply == true

  -- Setup autocmds
  require("raphael.autocmds").setup(M)

  -- Setup commands
  require("raphael.commands").setup(M)

  -- Setup keymaps
  require("raphael.keymaps").setup(M)

  -- Track if first filetype event has occurred
  local first_ft_fired = false

  -- FileType autocmd for auto_apply
  vim.api.nvim_create_autocmd("FileType", {
    callback = function(args)
      if not M.state.auto_apply then
        return
      end
      
      local ft = args.match
      local theme = themes.filetype_themes[ft]
      
      if theme and themes.is_available(theme) then
        -- Auto-apply should not update saved theme
        M.apply(theme, false)
      else
        -- Fallback to default if filetype theme not available
        if theme and not themes.is_available(theme) then
          vim.notify(
            string.format("raphael: filetype theme '%s' for %s not available, using default", theme, ft),
            vim.log.levels.WARN
          )
          if themes.is_available(M.config.default_theme) then
            M.apply(M.config.default_theme, false)
          end
        end
      end
      
      first_ft_fired = true
    end,
  })

  -- Apply initial theme (scheduled for lazy loading)
  vim.schedule(function()
    local themes = require("raphael.themes")
    
    -- Check if opening with session
    if vim.g.raphael_session_theme then
      M.restore_from_session()
      return
    end
    
    -- Determine what theme to apply at startup
    local startup_theme = nil
    
    -- If auto-apply is ON and we're opening with a file, let FileType handle it
    if M.state.auto_apply and vim.fn.argc() > 0 then
      -- Get the filetype of the first buffer
      local first_buf = vim.fn.bufnr(vim.fn.argv(0))
      if first_buf ~= -1 then
        local ft = vim.api.nvim_buf_get_option(first_buf, "filetype")
        if ft and ft ~= "" and themes.filetype_themes[ft] then
          -- FileType autocmd will handle this, skip saved theme
          return
        end
      end
    end
    
    -- Opening with no file or no filetype theme: use saved theme
    if M.state.saved and themes.is_available(M.state.saved) then
      startup_theme = M.state.saved
    elseif themes.is_available(M.config.default_theme) then
      startup_theme = M.config.default_theme
      M.state.saved = M.config.default_theme
      M.save_state()
    else
      vim.notify("raphael: fallback theme not found", vim.log.levels.WARN)
      return
    end
    
    if startup_theme then
      M.state.current = startup_theme
      pcall(vim.cmd.colorscheme, startup_theme)
    end
  end)
  
  -- Hook into session saving
  vim.api.nvim_create_autocmd("SessionLoadPost", {
    callback = function()
      M.restore_from_session()
    end,
  })
end

return M
