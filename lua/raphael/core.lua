local M = {}
local themes = require("raphael.themes")
local state_mod = require("raphael.state")
local history = require("raphael.theme_history")

-- Global state (set in setup)
M.state = nil
M.config = nil
M.manual_apply = false

function M.setup(config)
  M.config = config
  history.max_size = config.history_max_size or 13
  themes.filetype_themes = config.filetype_themes or {}
  local all_installed = vim.tbl_keys(themes.installed)
  table.sort(all_installed)
  themes.theme_map = config.theme_map or all_installed
  M.config.theme_aliases = config.theme_aliases or {}

  M.state = state_mod.load(config)

  vim.g.raphael_auto_theme = M.state.auto_apply == true

  -- Startup theme logic (scheduled for after init)
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
          return -- FileType autocmd will handle
        end
      end
    end

    if M.state.saved and themes.is_available(M.state.saved) then
      startup_theme = M.state.saved
    elseif themes.is_available(config.default_theme) then
      startup_theme = config.default_theme
      M.state.saved = config.default_theme
      state_mod.save(M.state, config)
    else
      vim.notify("raphael: fallback theme not found", vim.log.levels.WARN)
      return
    end

    if startup_theme then
      M.state.current = startup_theme
      pcall(vim.cmd.colorscheme, startup_theme)
    end
  end)

  -- Refresh and validation (as in original VimEnter)
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
        M.state.saved = config.default_theme
        state_mod.save(M.state, config)
      end
    end,
  })

  -- Session restore
  vim.api.nvim_create_autocmd("SessionLoadPost", {
    callback = function()
      M.restore_from_session()
    end,
  })
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
  state_mod.save(M.state, M.config)

  vim.notify("raphael: applied " .. theme)

  -- Extensibility hook
  if M.config.on_apply then
    M.config.on_apply(theme)
  end
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

function M.toggle_auto()
  M.state.auto_apply = not M.state.auto_apply
  vim.g.raphael_auto_theme = M.state.auto_apply
  state_mod.save(M.state, M.config)
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
  state_mod.save(M.state, M.config)
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

return M
