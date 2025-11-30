-- lua/raphael/core/autocmds.lua
-- Global and picker-specific autocmds for raphael.nvim.
--
-- Responsibilities:
--   - Global:
--       * BufEnter / FileType auto-apply of themes based on project or filetype
--       * LspAttach highlights for LSP references
--   - Picker-specific:
--       * CursorMoved inside picker (update palette + preview + highlight)
--       * BufDelete on picker buffer (cleanup)
--       * TextChanged in search buffer (live search)

local M = {}

local themes = require("raphael.themes")

--- Setup global autocmds that depend on the core orchestrator.
---
--- Global behavior:
---   - BufEnter/FileType:
---       * If core.state.auto_apply is true:
---           1. Compute project theme (from core.config.project_themes, absolute path, longest prefix)
---           2. Compute filetype theme (from themes.filetype_themes[ft])
---           3. Use priority flags:
---                - if config.project_overrides_filetype  == true: try project, then filetype
---                - if config.filetype_overrides_project  == true: try filetype, then project
---                - if both false (default):              try project, then filetype
---           4. If neither works, fall back to core.config.default_theme
---   - LspAttach:
---       * Set up default highlights for LspReference* groups
---
---@param core table  # usually require("raphael.core")
function M.setup(core)
  local project_rules = {}
  local cfg_projects = core.config.project_themes or {}

  local function normalize_root(path)
    if not path or path == "" then
      return nil
    end
    local expanded = vim.fn.expand(path)
    if expanded == "" then
      return nil
    end
    local full = vim.fn.fnamemodify(expanded, ":p")
    full = full:gsub("\\", "/")
    if full:sub(-1) == "/" then
      full = full:sub(1, -2)
    end
    return full
  end

  for root, theme in pairs(cfg_projects) do
    if type(theme) == "string" and theme ~= "" then
      local norm = normalize_root(root)
      if norm then
        table.insert(project_rules, { root = norm, theme = theme })
      end
    end
  end

  table.sort(project_rules, function(a, b)
    return #a.root > #b.root
  end)

  local function buf_dir(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    local ft = vim.bo[bufnr].filetype

    if ft == "oil" then
      local ok, oil = pcall(require, "oil")
      if ok and type(oil.get_current_dir) == "function" then
        local dir = oil.get_current_dir()
        if dir and dir ~= "" then
          dir = vim.fn.fnamemodify(dir, ":p")
          dir = dir:gsub("\\", "/")
          if dir:sub(-1) == "/" then
            dir = dir:sub(1, -2)
          end
          return dir
        end
      end
      local cwd = vim.loop.cwd() or vim.fn.getcwd()
      cwd = cwd:gsub("\\", "/")
      if cwd:sub(-1) == "/" then
        cwd = cwd:sub(1, -2)
      end
      return cwd
    end

    if name == "" then
      local cwd = vim.loop.cwd() or vim.fn.getcwd()
      cwd = cwd:gsub("\\", "/")
      if cwd:sub(-1) == "/" then
        cwd = cwd:sub(1, -2)
      end
      return cwd
    end
    local dir = vim.fn.fnamemodify(name, ":p:h")
    dir = dir:gsub("\\", "/")
    if dir:sub(-1) == "/" then
      dir = dir:sub(1, -2)
    end
    return dir
  end

  local function project_theme_for(bufnr)
    local dir = buf_dir(bufnr)
    if not dir then
      return nil
    end
    for _, rule in ipairs(project_rules) do
      if dir:sub(1, #rule.root) == rule.root then
        return rule.theme, rule.root
      end
    end
    return nil
  end

  local function apply_auto(bufnr, ft)
    if not core.state.auto_apply then
      return
    end

    local cfg = core.config or {}

    local filetype_overrides_project = cfg.filetype_overrides_project
    local project_overrides_filetype = cfg.project_overrides_filetype

    if type(filetype_overrides_project) ~= "boolean" then
      filetype_overrides_project = false
    end
    if type(project_overrides_filetype) ~= "boolean" then
      project_overrides_filetype = false
    end

    if filetype_overrides_project and project_overrides_filetype then
      filetype_overrides_project = false
    end

    local proj_theme, proj_root = project_theme_for(bufnr)
    local ft_theme = themes.filetype_themes[ft]

    local selected_theme = nil

    local function try_theme(kind)
      local theme_name
      if kind == "project" then
        theme_name = proj_theme
      else
        theme_name = ft_theme
      end
      if not theme_name then
        return false
      end

      if themes.is_available(theme_name) then
        selected_theme = theme_name
        return true
      else
        if kind == "project" then
          vim.notify(
            string.format(
              "raphael: project theme '%s' for %s not available, falling back",
              theme_name,
              proj_root or "project"
            ),
            vim.log.levels.WARN
          )
        else
          vim.notify(
            string.format(
              "raphael: filetype theme '%s' for %s not available, falling back",
              theme_name,
              ft or "filetype"
            ),
            vim.log.levels.WARN
          )
        end
        return false
      end
    end

    local order
    if project_overrides_filetype then
      order = { "project", "filetype" }
    elseif filetype_overrides_project then
      order = { "filetype", "project" }
    else
      order = { "project", "filetype" }
    end

    for _, kind in ipairs(order) do
      if try_theme(kind) then
        break
      end
    end

    if not selected_theme and themes.is_available(core.config.default_theme) then
      selected_theme = core.config.default_theme
    end

    if selected_theme then
      core.apply(selected_theme, false)
    end
  end

  vim.api.nvim_create_autocmd("BufEnter", {
    callback = function(ev)
      local ft = vim.bo[ev.buf].filetype
      apply_auto(ev.buf, ft)
    end,
  })

  vim.api.nvim_create_autocmd("FileType", {
    callback = function(ev)
      local ft = ev.match
      apply_auto(ev.buf, ft)
    end,
  })

  vim.api.nvim_create_autocmd("LspAttach", {
    callback = function()
      vim.api.nvim_set_hl(0, "LspReferenceText", { link = "CursorLine" })
      vim.api.nvim_set_hl(0, "LspReferenceRead", { link = "CursorLine" })
      vim.api.nvim_set_hl(0, "LspReferenceWrite", { link = "Visual" })
    end,
  })
end

--- Attach a CursorMoved autocmd to the picker buffer.
---
---@param picker_buf integer
---@param cbs table|nil
function M.picker_cursor_autocmd(picker_buf, cbs)
  if type(picker_buf) ~= "number" then
    error("picker_cursor_autocmd: picker_buf must be a buffer number")
  end
  cbs = cbs or {}
  local parse = cbs.parse
  local preview = cbs.preview
  local highlight = cbs.highlight
  local update_preview = cbs.update_preview

  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = picker_buf,
    callback = function()
      local ok, line = pcall(vim.api.nvim_get_current_line)
      if not ok then
        return
      end

      local theme
      if type(parse) == "function" then
        theme = parse(line)
      end
      if theme and type(preview) == "function" then
        preview(theme)
      end
      if type(highlight) == "function" then
        highlight()
      end
      if type(update_preview) == "function" then
        update_preview({ debounced = true })
      end
    end,
  })
end

--- Attach a BufDelete autocmd to the picker buffer.
---
---@param picker_buf integer
---@param cbs table|nil
function M.picker_bufdelete_autocmd(picker_buf, cbs)
  if type(picker_buf) ~= "number" then
    error("picker_bufdelete_autocmd: picker_buf must be a buffer number")
  end
  cbs = cbs or {}
  local log = cbs.log
  local cleanup = cbs.cleanup

  vim.api.nvim_create_autocmd("BufDelete", {
    buffer = picker_buf,
    once = true,
    callback = function()
      if type(log) == "function" then
        pcall(log, "DEBUG", "Picker buffer deleted, cleaning up")
      end
      if type(cleanup) == "function" then
        pcall(cleanup)
      end
    end,
  })
end

--- Attach TextChanged autocmds for the search buffer.
---
--- This handles:
---   - Reading the prompt + query from the search buffer
---   - Stripping the search icon prefix (ICON_SEARCH)
---   - Updating the search query in the picker state (set_search_query)
---   - Re-rendering the picker (render)
---
---@param search_buf integer  # buffer number of the search prompt
---@param cbs table|nil
function M.search_textchange_autocmd(search_buf, cbs)
  if type(search_buf) ~= "number" then
    error("search_textchange_autocmd: search_buf must be a buffer number")
  end
  cbs = cbs or {}
  local trim = cbs.trim
  local ICON_SEARCH = cbs.ICON_SEARCH
  local render = cbs.render
  local get_picker_opts = cbs.get_picker_opts
  local set_search_query = cbs.set_search_query

  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    buffer = search_buf,
    callback = function()
      local ok_lines, lines = pcall(vim.api.nvim_buf_get_lines, search_buf, 0, -1, false)
      if not ok_lines then
        return
      end

      local joined = table.concat(lines, "\n")
      local new_query = joined:gsub("^" .. (ICON_SEARCH or ""), "")
      if type(trim) == "function" then
        new_query = trim(new_query)
      end

      if type(set_search_query) == "function" then
        pcall(set_search_query, new_query)
      end

      if type(render) == "function" then
        local opts = nil
        if type(get_picker_opts) == "function" then
          opts = get_picker_opts()
        end
        pcall(render, opts)
      end
    end,
  })
end

return M
