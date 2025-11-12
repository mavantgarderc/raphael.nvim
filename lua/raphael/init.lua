local M = {}

local themes = require("raphael.themes")
local history = require("raphael.theme_history")
local autocmds = require("raphael.autocmds")
local cmds = require("raphael.cmds")
local keymaps = require("raphael.keymaps")
local picker = require("raphael.picker")

M.defaults = {
  leader = "<leader>t",
  mappings = {
    picker = "p",
    next = ">",
    previous = "<",
    others = "/",
    auto = "a",
    refresh = "R",
    status = "s",
  },
  default_theme = "kanagawa-paper-ink",
  state_file = vim.fn.stdpath("data") .. "/raphael/state.json",
  theme_map = nil,
  filetype_themes = {},
  animate = { enabled = false, duration = 200, steps = 10 },
  sort_mode = "alpha",
  custom_sorts = {},
  theme_aliases = {},
  history_max_size = 13,
  sample_preview = {
    enabled = true,
    relative_size = 0.5,
  },
}

M.state = nil
M.manual_apply = false

local function async_write(path, contents)
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
      sort_mode = M.config.sort_mode,
      usage = {},
      undo_history = nil,
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
      sort_mode = M.config.sort_mode,
      usage = {},
      undo_history = nil,
    }
    local payload = vim.fn.json_encode(M.state)
    async_write(M.config.state_file, payload)
    return
  end

  M.state = {
    current = decoded.current or M.config.default_theme,
    saved = decoded.saved or decoded.current or M.config.default_theme,
    previous = decoded.previous,
    auto_apply = decoded.auto_apply == true,
    bookmarks = decoded.bookmarks or {},
    collapsed = decoded.collapsed or {},
    history = decoded.history or {},
    sort_mode = decoded.sort_mode or M.config.sort_mode,
    usage = decoded.usage or {},
    undo_history = decoded.undo_history,
  }

  if M.state.undo_history then
    history.deserialize(M.state.undo_history)
  end
end

function M.save_state()
  M.state.undo_history = history.serialize()
  local payload = vim.fn.json_encode(M.state)
  async_write(M.config.state_file, payload)
end

function M.add_to_history(theme)
  if not theme then
    return
  end

  table.insert(M.state.history, 1, theme)

  while #M.state.history > 10 do
    table.remove(M.state.history)
  end
end

function M.apply(theme, from_manual)
  if not theme or not themes.is_available(theme) then
    vim.notify("raphael: theme not available: " .. tostring(theme), vim.log.levels.WARN)
    return
  end

  if vim.g.colors_name == theme then
    return
  end

  M.state.previous = M.state.current

  vim.cmd("hi clear")
  if vim.fn.exists("syntax_on") then
    vim.cmd("syntax reset")
  end

  local ok, err = pcall(vim.cmd.colorscheme, theme)
  if not ok then
    vim.notify("raphael: failed to apply theme '" .. tostring(theme) .. "': " .. tostring(err), vim.log.levels.ERROR)
    return
  end

  M.state.current = theme
  M.state.usage = M.state.usage or {}
  M.state.usage[theme] = (M.state.usage[theme] or 0) + 1

  if from_manual then
    history.add(theme)
    M.state.saved = theme
  end

  M.add_to_history(theme)
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
  picker.open(M, opts)
end

function M.refresh_and_reload()
  themes.refresh()
  if M.state.current and themes.is_available(M.state.current) then
    M.apply(M.state.current, false)
  else
    vim.notify("raphael: current theme not available after refresh", vim.log.levels.WARN)
  end
end

function M.show_status()
  local auto_status = M.state.auto_apply and "ON" or "OFF"
  local saved_info = M.state.saved and M.state.saved ~= M.state.current and string.format(" | saved: %s", M.state.saved)
    or ""

  vim.notify(
    string.format("raphael: current - %s%s | auto-apply: %s", M.state.current or "none", saved_info, auto_status),
    vim.log.levels.INFO
  )
end

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

function M.restore_from_session()
  local session_theme = vim.g.raphael_session_theme
  local session_saved = vim.g.raphael_session_saved
  local session_auto = vim.g.raphael_session_auto

  if session_theme then
    M.state.current = session_theme
    M.state.saved = session_saved or session_theme
    M.state.auto_apply = session_auto == 1

    if themes.is_available(session_theme) then
      pcall(vim.cmd.colorscheme, session_theme)
    end
  end
end

function M.setup(user_config)
  user_config = user_config or {}
  M.config = vim.tbl_deep_extend("force", M.defaults, user_config)

  if M.config.history_max_size then
    history.max_size = M.config.history_max_size
  end

  themes.filetype_themes = user_config.filetype_themes or M.defaults.filetype_themes

  local all_installed = vim.tbl_keys(themes.installed)
  table.sort(all_installed)
  themes.theme_map = user_config.theme_map or all_installed
  M.config.theme_aliases = user_config.theme_aliases or M.defaults.theme_aliases

  M.load_state()

  vim.g.raphael_auto_theme = M.state.auto_apply == true

  autocmds.setup(M)

  cmds.setup(M)

  keymaps.setup(M)

  vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
      themes.refresh()

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

      if M.state.saved and not themes.is_available(M.state.saved) then
        vim.notify(
          "raphael: Saved theme '" .. M.state.saved .. "' not available, falling back to default",
          vim.log.levels.WARN
        )
        M.state.saved = M.config.default_theme
        M.save_state()
      end
    end,
  })

  vim.api.nvim_create_autocmd("FileType", {
    callback = function(args)
      if not M.state.auto_apply then
        return
      end

      local ft = args.match
      local theme_ft = themes.filetype_themes[ft]

      if theme_ft and themes.is_available(theme_ft) then
        M.apply(theme_ft, false)
      else
        if theme_ft and not themes.is_available(theme_ft) then
          vim.notify(
            string.format("raphael: filetype theme '%s' for %s not available, using default", theme_ft, ft),
            vim.log.levels.WARN
          )
          if themes.is_available(M.config.default_theme) then
            M.apply(M.config.default_theme, false)
          end
        end
      end

      ---@diagnostic disable-next-line: lowercase-global
      first_ft_fired = true
    end,
  })

  vim.schedule(function()
    if vim.g.raphael_session_theme then
      M.restore_from_session()
      return
    end

    local startup_theme = nil

    if M.state.auto_apply and vim.fn.argc() > 0 then
      ---@diagnostic disable-next-line: param-type-mismatch
      local first_buf = vim.fn.bufnr(vim.fn.argv(0))
      if first_buf ~= -1 then
        local ft = vim.api.nvim_get_option_value("filetype", { buf = first_buf })
        if ft and ft ~= "" and themes.filetype_themes[ft] then
          return
        end
      end
    end

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

  vim.api.nvim_create_autocmd("SessionLoadPost", {
    callback = function()
      M.restore_from_session()
    end,
  })
end

return M
