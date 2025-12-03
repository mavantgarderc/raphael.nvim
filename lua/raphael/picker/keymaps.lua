-- lua/raphael/picker/keymaps.lua
-- Picker-local keymaps:
--   - Navigation (j/k, C-j/C-k, gg/G, zt/zz/zb, [g/]g, etc.)
--   - Actions (<CR>, c, s/S/R, /, b, random, help)
--   - History (u, <C-r>, H, J, T)
--   - Sections navigation ([b/ ]b, [r/ ]r, gb, gr, ga)
--   - Code preview (i, I, C)
--   - Quick slots (m0–m9 assign, 0–9 jump)
--
-- This module DOES NOT own state; it operates on `ctx` and callbacks.
-- It expects `ctx` to be the live picker context created in picker/ui.lua.

local M = {}

local map = vim.keymap.set
local themes = require("raphael.themes")
local history = require("raphael.extras.history")
local C = require("raphael.constants")
local preview = require("raphael.picker.preview")
local render = require("raphael.picker.render")

local HIGHLIGHT_NS = C.NS.PICKER_CURSOR

local help_lines = {
  "Raphael Picker - Keybindings:",
  "",
  "Navigation:",
  "  `j`/`k`         - Navigate (wraps around)",
  "  `gg`/`G`        - Jump to top/bottom",
  "  `<C-u>`/`<C-d>` - Page up/down (half-window)",
  "  `zt`/`zz`/`zb`  - Scroll current line to top/center/bottom",
  "  `ga`            - Jump to first theme (All)",
  "  `<C-l>`/`<C-h>` - Move into/out of group (header <-> items / previous header)",
  "  `<C-j>`/`<C-k>` - Jump to next/prev group header (wraps)",
  "  `gn`/`gp`       - Jump to next/prev group header (wraps, tracks last group)",
  "  `g.`            - Jump to last visited group (via gn/gp/<C-j>/<C-k>)",
  "  `[g`/`]g`       - Jump to prev/next group header (wraps)",
  "  `[b`/`]b`       - Jump to prev/next bookmark (skips Bookmarks group block)",
  "  `[r`/`]r`       - Jump to prev/next history entry (skips Recent group block)",
  "",
  "Sections:",
  "  `gb`            - Jump to Bookmarks section header",
  "  `gB`            - Jump to first bookmarked theme",
  "  `gr`            - Jump to Recent section header",
  "",
  "Actions:",
  "  `<CR>`          - Select theme (apply & close picker)",
  "  `x`/`<S-CR>`    - Apply theme (keep picker open)",
  "  `<C-A-k>`       - Collapse all groups",
  "  `<C-A-j>`       - Expand all groups",
  "  `c`             - Collapse/expand group under cursor",
  "  `s`             - Cycle sort mode",
  "  `S`             - Toggle sorting on/off",
  "  `R`             - Toggle reverse sorting (descending)",
  "  `F`             - Toggle only-bookmarked view",
  "  `v`             - Toggle flat/grouped view",
  "  `gf`            - Toggle configured/other picker",
  "  `/`             - Search themes",
  "  `a`             - Clear search / show all themes",
  "  `b`             - Toggle bookmark for theme under cursor",
  "  `dd`            - Jump to current theme (expands groups if needed)",
  "  `XB`            - Clear all bookmarks",
  "  `XR`            - Clear recent history",
  "  `<C-p>`         - Refresh picker contents",
  "",
  "History (picker-only):",
  "  `u`             - Undo theme change",
  "  `<C-r>`         - Redo theme change",
  "  `H`             - Show full history",
  "  `J`             - Jump to history position",
  "  `T`             - Show quick stats",
  "  `r`             - Apply random theme",
  "",
  "Preview:",
  "  `i`             - Show code sample / next language",
  "  `I`             - Previous code sample language",
  "  `C`             - Compare candidate with current theme (toggle)",
  "",
  "Quick slots:",
  "  `m0`..`m9`      - Map current theme to quick slot 0-9",
  "  `0`..`9`        - Jump to quick slot theme in picker & preview it",
  "",
  "Other:",
  "  `q`/`<Esc>`     - Quit (revert theme)",
  "  `?`             - Show this help",
}

--- Highlight the current line using Visual
---
--- Uses C.HL.PICKER_CURSOR (defaults to "Visual") and the PICKER_CURSOR
--- namespace to draw the highlight.
---
---@param ctx table  # picker context: expects ctx.buf, ctx.win
function M.highlight_current_line(ctx)
  local buf = ctx.buf
  local win = ctx.win

  if not buf or not vim.api.nvim_buf_is_valid(buf) or not win or not vim.api.nvim_win_is_valid(win) then
    return
  end

  local ok, cursor = pcall(vim.api.nvim_win_get_cursor, win)
  if not ok then
    return
  end

  local cur_line = cursor[1] - 1
  pcall(vim.api.nvim_buf_clear_namespace, buf, HIGHLIGHT_NS, 0, -1)

  -- highlight ALL lines, including headers
  pcall(
    vim.highlight.range,
    buf,
    HIGHLIGHT_NS,
    C.HL.PICKER_CURSOR,
    { cur_line, 0 },
    { cur_line, -1 },
    { inclusive = false, priority = 100 }
  )
end

--- Go from a group header to its first child, or from a child back into its
--- owning group (first non-header line after the header).
---
---@param ctx table
function M.go_in_group(ctx)
  local buf = ctx.buf
  local win = ctx.win

  if not buf or not vim.api.nvim_buf_is_valid(buf) or not win or not vim.api.nvim_win_is_valid(win) then
    return
  end

  local ok_cur, cursor = pcall(vim.api.nvim_win_get_cursor, win)
  if not ok_cur then
    return
  end

  local cur = cursor[1]
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if #lines == 0 then
    return
  end

  local function is_header(line)
    return line:match("^" .. C.ICON.GROUP_EXPANDED) or line:match("^" .. C.ICON.GROUP_COLLAPSED)
  end

  local target

  local line = lines[cur] or ""
  if is_header(line) then
    -- On header: go to first non-header line below
    for i = cur + 1, #lines do
      local l = lines[i] or ""
      if not is_header(l) then
        target = i
        break
      end
    end
  else
    local header_idx
    for i = cur, 1, -1 do
      local l = lines[i] or ""
      if is_header(l) then
        header_idx = i
        break
      end
    end
    if header_idx then
      for i = header_idx + 1, #lines do
        local l = lines[i] or ""
        if not is_header(l) then
          target = i
          break
        end
      end
    end
  end

  if target then
    vim.api.nvim_win_set_cursor(win, { target, 0 })
    M.highlight_current_line(ctx)
  end
end

--- Go out of a group: from a child line up to its header; if already on a
--- header, go to the previous header (if any).
---
---@param ctx table
function M.go_out_group(ctx)
  local buf = ctx.buf
  local win = ctx.win

  if not buf or not vim.api.nvim_buf_is_valid(buf) or not win or not vim.api.nvim_win_is_valid(win) then
    return
  end

  local ok_cur, cursor = pcall(vim.api.nvim_win_get_cursor, win)
  if not ok_cur then
    return
  end

  local cur = cursor[1]
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if #lines == 0 then
    return
  end

  local function is_header(line)
    return line:match("^" .. C.ICON.GROUP_EXPANDED) or line:match("^" .. C.ICON.GROUP_COLLAPSED)
  end

  local line = lines[cur] or ""
  local target

  if is_header(line) then
    -- On header: go to previous header (if any)
    for i = cur - 1, 1, -1 do
      local l = lines[i] or ""
      if is_header(l) then
        target = i
        break
      end
    end
  else
    -- On child: go up to its own header
    for i = cur - 1, 1, -1 do
      local l = lines[i] or ""
      if is_header(l) then
        target = i
        break
      end
    end
  end

  if target then
    vim.api.nvim_win_set_cursor(win, { target, 0 })
    M.highlight_current_line(ctx)
  end
end

--- Move cursor to the header line of the group under cursor (if any).
---
---@param ctx table
local function jump_to_current_group_header(ctx)
  local win = ctx.win
  local buf = ctx.buf
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local cur = vim.api.nvim_win_get_cursor(win)
  local row = cur[1]
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if #lines == 0 then
    return
  end

  local line = lines[row] or ""
  if render.parse_line_header(line) then
    return
  end

  for i = row, 1, -1 do
    local maybe = render.parse_line_header(lines[i] or "")
    if maybe then
      vim.api.nvim_win_set_cursor(win, { i, 0 })
      M.highlight_current_line(ctx)
      return
    end
  end
end

--- Jump to the currently applied theme (state.current) inside the picker.
---
---@param ctx table
---@return boolean found
local function jump_to_current_theme(ctx)
  local win = ctx.win
  local buf = ctx.buf
  local state = ctx.state

  if not win or not vim.api.nvim_win_is_valid(win) then
    return false
  end
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return false
  end

  local current = state.current
  if not current or current == "" then
    return false
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i, line in ipairs(lines) do
    local theme = render.parse_line_theme(ctx.core, line)
    if theme == current then
      vim.api.nvim_win_set_cursor(win, { i, 0 })
      vim.cmd("normal! zz")
      M.highlight_current_line(ctx)
      return true
    end
  end
  return false
end

--- Attach all picker-local keymaps to ctx.buf.
---
--- Context (`ctx`) is expected to have:
---   - buf, win             : picker buffer & window
---   - core, state          : require("raphael.core") + core.state
---   - base_title, opts     : base title string, options table
---   - collapsed, bookmarks : group collapse map, bookmark set
---   - header_lines, flags  : header line indices, flags.disable_sorting/reverse_sorting
---   - instances, picker_type : used to track open pickers (configured/other)
---
--- `fns` callbacks:
---   - fns.close_picker(revert:boolean)
---   - fns.render()
---   - fns.update_state_collapsed()
---   - fns.open_search()
---
---@param ctx table
---@param fns table
---@return nil
function M.attach(ctx, fns)
  local buf = ctx.buf
  local win = ctx.win
  local core = ctx.core
  local state = ctx.state

  local base_title = ctx.base_title
  -- local opts = ctx.opts

  --- Expand all groups that contain the given theme in themes.theme_map.
  ---
  --- @param theme string
  local function expand_groups_for_theme(theme)
    if not themes or not themes.theme_map then
      return
    end
    local found_path = nil
    local function dfs(node, path)
      if found_path then
        return
      end
      local t = type(node)
      if t == "string" then
        if node == theme then
          found_path = vim.deepcopy(path)
        end
      elseif t == "table" then
        if vim.islist(node) then
          for _, v in ipairs(node) do
            dfs(v, path)
            if found_path then
              return
            end
          end
        else
          for k, v in pairs(node) do
            if type(k) == "string" then
              table.insert(path, k)
              dfs(v, path)
              if found_path then
                return
              end
              path[#path] = nil
            else
              dfs(v, path)
              if found_path then
                return
              end
            end
          end
        end
      end
    end
    dfs(themes.theme_map, {})
    if not found_path or #found_path == 0 then
      return
    end
    for _, g in ipairs(found_path) do
      ctx.collapsed[g] = false
    end
    fns.update_state_collapsed()
  end

  local function set_all_groups_collapsed(collapsed)
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    for _, ln in ipairs(ctx.header_lines) do
      local line = lines[ln] or ""
      local hdr = render.parse_line_header(line)
      if hdr then
        if hdr == "Bookmarks" then
          hdr = "__bookmarks"
        elseif hdr == "Recent" then
          hdr = "__recent"
        end
        ctx.collapsed[hdr] = collapsed
      end
    end
    fns.update_state_collapsed()
    fns.render(true)
    M.highlight_current_line(ctx)
  end

  local function parse_current_theme()
    local line = vim.api.nvim_get_current_line()
    return render.parse_line_theme(core, line)
  end

  local function parse_current_header()
    local line = vim.api.nvim_get_current_line()
    return render.parse_line_header(line)
  end

  local function toggle_group(group)
    if not group then
      return
    end
    ctx.collapsed[group] = not ctx.collapsed[group]
    fns.update_state_collapsed()
    fns.render()
    jump_to_current_group_header(ctx)
  end

  local function update_title()
    local sort = ctx.flags.disable_sorting and "off" or (state.sort_mode or core.config.sort_mode or "alpha")
    local suffix = sort .. (ctx.flags.reverse_sorting and " reverse " or "")
    local title = base_title .. " (Sort: " .. suffix .. ")"
    vim.api.nvim_win_set_config(win, { title = title })
  end

  local function refresh_bookmarks_set()
    ctx.bookmarks = require("raphael.picker.bookmarks").build_set(state, core)
  end

  local function jump_to_theme(theme)
    if not theme or theme == "" then
      return false
    end
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    for i, line in ipairs(lines) do
      local t = render.parse_line_theme(core, line)
      if t == theme then
        vim.api.nvim_win_set_cursor(win, { i, 0 })
        M.highlight_current_line(ctx)
        preview.preview_theme(ctx, theme)
        return true
      end
    end
    return false
  end

  local function jump_to_quick_slot(slot)
    local theme = core.get_quick_slot and core.get_quick_slot(slot)
    if not theme then
      vim.notify(string.format("raphael: no theme assigned to quick slot %s", tostring(slot)), vim.log.levels.WARN)
      return
    end
    if not themes.is_available(theme) then
      vim.notify(
        string.format("raphael: quick slot %s theme '%s' not installed", tostring(slot), theme),
        vim.log.levels.WARN
      )
      return
    end
    if not jump_to_theme(theme) then
      vim.notify(
        string.format("raphael: quick slot %s theme '%s' not visible in this picker", tostring(slot), theme),
        vim.log.levels.WARN
      )
    end
  end

  --- Assign current line's theme to quick slot N (0–9).
  local function assign_quick_slot(slot)
    local hdr = parse_current_header()
    if hdr then
      vim.notify("Cannot assign a group header to quick slot", vim.log.levels.WARN)
      return
    end
    local theme = parse_current_theme()
    if not theme then
      vim.notify("No theme on this line to assign to quick slot", vim.log.levels.WARN)
      return
    end
    if not themes.is_available(theme) then
      vim.notify("Theme not installed: " .. theme, vim.log.levels.ERROR)
      return
    end
    if not core.set_quick_slot then
      vim.notify("raphael: quick slots API not available in core", vim.log.levels.ERROR)
      return
    end
    core.set_quick_slot(slot, theme)
  end

  --- Apply theme under cursor; optionally keep picker open.
  ---@param keep_open boolean
  local function apply_theme_at_cursor(keep_open)
    local hdr = parse_current_header()
    if hdr then
      vim.notify("Cannot select a group header", vim.log.levels.WARN)
      return
    end
    local theme = parse_current_theme()
    if not theme then
      vim.notify("No theme on this line", vim.log.levels.WARN)
      return
    end
    if not themes.is_available(theme) then
      vim.notify("Theme not installed: " .. theme, vim.log.levels.ERROR)
      return
    end
    local ok, err = pcall(core.apply, theme, true)
    if not ok then
      vim.notify("Failed to apply theme: " .. theme .. " (" .. tostring(err) .. ")", vim.log.levels.ERROR)
      return
    end
    if keep_open then
      fns.render()
      M.highlight_current_line(ctx)
    else
      preview.close_code_preview()
      ctx.instances[ctx.picker_type] = false
      fns.close_picker(false)
    end
  end

  map("n", "q", function()
    preview.close_code_preview()
    ctx.instances[ctx.picker_type] = false
    fns.close_picker(true)
  end, { buffer = buf, desc = "Quit and revert" })

  map("n", "<Esc>", function()
    preview.close_code_preview()
    ctx.instances[ctx.picker_type] = false
    fns.close_picker(true)
  end, { buffer = buf, desc = "Quit and revert" })

  map("n", "<CR>", function()
    apply_theme_at_cursor(false)
  end, { buffer = buf, desc = "Select theme" })

  map("n", "<S-CR>", function()
    apply_theme_at_cursor(true)
  end, { buffer = buf, desc = "Apply theme (keep picker open)" })

  map("n", "x", function()
    apply_theme_at_cursor(true)
  end, { buffer = buf, desc = "Apply theme (keep picker open)" })

  map("n", "j", function()
    local line_count = #vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local cur = vim.api.nvim_win_get_cursor(win)[1]
    local next_line = (cur >= line_count) and 1 or (cur + 1)
    vim.api.nvim_win_set_cursor(win, { next_line, 0 })
    M.highlight_current_line(ctx)
  end, { buffer = buf, desc = "Next line (wrap to top)" })

  map("n", "k", function()
    local line_count = #vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local cur = vim.api.nvim_win_get_cursor(win)[1]
    local prev_line = (cur <= 1) and line_count or (cur - 1)
    vim.api.nvim_win_set_cursor(win, { prev_line, 0 })
    M.highlight_current_line(ctx)
  end, { buffer = buf, desc = "Previous line (wrap to bottom)" })

  local last_group_name = nil

  local function set_last_group_from_line(line)
    local g = render.parse_line_header(line or "")
    if g then
      last_group_name = g
    end
  end

  map("n", "<C-j>", function()
    if #ctx.header_lines == 0 then
      return
    end
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local cur = vim.api.nvim_win_get_cursor(win)[1]
    for _, ln in ipairs(ctx.header_lines) do
      if ln > cur then
        vim.api.nvim_win_set_cursor(win, { ln, 0 })
        set_last_group_from_line(lines[ln] or "")
        M.highlight_current_line(ctx)
        return
      end
    end
    if #ctx.header_lines > 0 then
      local ln = ctx.header_lines[1]
      vim.api.nvim_win_set_cursor(win, { ln, 0 })
      set_last_group_from_line(lines[ln] or "")
      M.highlight_current_line(ctx)
    end
  end, { buffer = buf, desc = "Next group header" })

  map("n", "<C-k>", function()
    if #ctx.header_lines == 0 then
      return
    end
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local cur = vim.api.nvim_win_get_cursor(win)[1]
    for i = #ctx.header_lines, 1, -1 do
      if ctx.header_lines[i] < cur then
        local ln = ctx.header_lines[i]
        vim.api.nvim_win_set_cursor(win, { ln, 0 })
        set_last_group_from_line(lines[ln] or "")
        M.highlight_current_line(ctx)
        return
      end
    end
  end, { buffer = buf, desc = "Previous group header" })

  map("n", "gn", function()
    if #ctx.header_lines == 0 then
      return
    end
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local cur = vim.api.nvim_win_get_cursor(win)[1]
    local target
    for _, ln in ipairs(ctx.header_lines) do
      if ln > cur then
        target = ln
        break
      end
    end
    if not target then
      target = ctx.header_lines[1]
    end
    vim.api.nvim_win_set_cursor(win, { target, 0 })
    set_last_group_from_line(lines[target] or "")
    M.highlight_current_line(ctx)
  end, { buffer = buf, desc = "Next group header (gn)" })

  map("n", "gp", function()
    if #ctx.header_lines == 0 then
      return
    end
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local cur = vim.api.nvim_win_get_cursor(win)[1]
    local target
    for i = #ctx.header_lines, 1, -1 do
      if ctx.header_lines[i] < cur then
        target = ctx.header_lines[i]
        break
      end
    end
    if not target then
      target = ctx.header_lines[#ctx.header_lines]
    end
    vim.api.nvim_win_set_cursor(win, { target, 0 })
    set_last_group_from_line(lines[target] or "")
    M.highlight_current_line(ctx)
  end, { buffer = buf, desc = "Previous group header (gp)" })

  map("n", "g.", function()
    if not last_group_name or last_group_name == "" then
      return
    end
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    for _, ln in ipairs(ctx.header_lines) do
      local hdr = render.parse_line_header(lines[ln] or "")
      if hdr == last_group_name then
        vim.api.nvim_win_set_cursor(win, { ln, 0 })
        vim.cmd("normal! zz")
        M.highlight_current_line(ctx)
        return
      end
    end
  end, { buffer = buf, desc = "Jump to last visited group" })

  map("n", "gg", function()
    vim.api.nvim_win_set_cursor(win, { 1, 0 })
    M.highlight_current_line(ctx)
  end, { buffer = buf, desc = "Go to top" })

  map("n", "G", function()
    local line_count = #vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    vim.api.nvim_win_set_cursor(win, { line_count, 0 })
    M.highlight_current_line(ctx)
  end, { buffer = buf, desc = "Go to bottom" })

  map("n", "<C-u>", function()
    local height = vim.api.nvim_win_get_height(win)
    local cur = vim.api.nvim_win_get_cursor(win)[1]
    local target = math.max(1, cur - math.floor(height / 2))
    vim.api.nvim_win_set_cursor(win, { target, 0 })
    M.highlight_current_line(ctx)
  end, { buffer = buf, desc = "Page up (half-window)" })

  map("n", "<C-d>", function()
    local height = vim.api.nvim_win_get_height(win)
    local line_count = #vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local cur = vim.api.nvim_win_get_cursor(win)[1]
    local target = math.min(line_count, cur + math.floor(height / 2))
    vim.api.nvim_win_set_cursor(win, { target, 0 })
    M.highlight_current_line(ctx)
  end, { buffer = buf, desc = "Page down (half-window)" })

  map("n", "zt", function()
    local cur = vim.api.nvim_win_get_cursor(win)[1]
    vim.api.nvim_win_set_cursor(win, { cur, 0 })
    vim.cmd("normal! zt")
    M.highlight_current_line(ctx)
  end, { buffer = buf, desc = "Scroll line to top" })

  map("n", "zz", function()
    local cur = vim.api.nvim_win_get_cursor(win)[1]
    vim.api.nvim_win_set_cursor(win, { cur, 0 })
    vim.cmd("normal! zz")
    M.highlight_current_line(ctx)
  end, { buffer = buf, desc = "Scroll line to center" })

  map("n", "zb", function()
    local cur = vim.api.nvim_win_get_cursor(win)[1]
    vim.api.nvim_win_set_cursor(win, { cur, 0 })
    vim.cmd("normal! zb")
    M.highlight_current_line(ctx)
  end, { buffer = buf, desc = "Scroll line to bottom" })

  map("n", "ga", function()
    vim.api.nvim_win_set_cursor(win, { 1, 0 })
    M.highlight_current_line(ctx)
  end, { buffer = buf, desc = "Jump to first theme (All)" })

  map("n", "gb", function()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    for _, ln in ipairs(ctx.header_lines) do
      local line = lines[ln] or ""
      if line:find("Bookmarks") then
        vim.api.nvim_win_set_cursor(win, { ln, 0 })
        M.highlight_current_line(ctx)
        return
      end
    end
    vim.notify("Bookmarks section not found", vim.log.levels.WARN)
  end, { buffer = buf, desc = "Jump to Bookmarks" })

  map("n", "gr", function()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    for _, ln in ipairs(ctx.header_lines) do
      local line = lines[ln] or ""
      if line:find("Recent") then
        vim.api.nvim_win_set_cursor(win, { ln, 0 })
        M.highlight_current_line(ctx)
        return
      end
    end
    vim.notify("Recent section not found", vim.log.levels.WARN)
  end, { buffer = buf, desc = "Jump to Recent" })

  map("n", "<C-p>", function()
    fns.render()
    M.highlight_current_line(ctx)
    vim.notify("Picker refreshed", vim.log.levels.INFO)
  end, { buffer = buf, desc = "Refresh picker" })

  map("n", "c", function()
    local hdr = parse_current_header()
    if not hdr then
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local current_idx = vim.api.nvim_win_get_cursor(win)[1]
      for i = current_idx, 1, -1 do
        local possible_hdr = render.parse_line_header(lines[i])
        if possible_hdr then
          hdr = possible_hdr
          break
        end
      end
    end
    if hdr then
      if hdr == "Bookmarks" then
        hdr = "__bookmarks"
      elseif hdr == "Recent" then
        hdr = "__recent"
      end
      toggle_group(hdr)
    else
      vim.notify("No group detected for current line", vim.log.levels.WARN)
    end
  end, { buffer = buf, desc = "Collapse/expand group" })

  map("n", "s", function()
    local sort_modes = { "alpha", "recent", "usage" }
    local idx = vim.fn.index(sort_modes, state.sort_mode or "alpha") + 1
    state.sort_mode = sort_modes[(idx % #sort_modes) + 1]
    fns.update_state_collapsed()
    update_title()
    fns.render()
  end, { buffer = buf, desc = "Cycle sort mode" })

  map("n", "S", function()
    ctx.flags.disable_sorting = not ctx.flags.disable_sorting
    fns.update_state_collapsed()
    update_title()
    vim.notify(
      string.format("[Raphael] Sorting: %s", ctx.flags.disable_sorting and "DISABLED" or "ENABLED"),
      vim.log.levels.INFO
    )
    fns.render()
  end, { buffer = buf, desc = "Toggle sorting on/off" })

  map("n", "R", function()
    ctx.flags.reverse_sorting = not ctx.flags.reverse_sorting
    fns.update_state_collapsed()
    update_title()
    vim.notify(
      string.format("[Raphael] Reverse sort: %s", ctx.flags.reverse_sorting and "ON" or "OFF"),
      vim.log.levels.INFO
    )
    fns.render()
  end, { buffer = buf, desc = "Toggle reverse sorting" })

  map("n", "F", function()
    ctx.flags.only_bookmarks = not ctx.flags.only_bookmarks
    local msg = ctx.flags.only_bookmarks and "Only bookmarked: ON" or "Only bookmarked: OFF"
    vim.notify("raphael: " .. msg, vim.log.levels.INFO)
    fns.render()
    M.highlight_current_line(ctx)
  end, { buffer = buf, desc = "Toggle only-bookmarked view" })

  map("n", "v", function()
    ctx.flags.flat_view = not ctx.flags.flat_view
    local msg = ctx.flags.flat_view and "Flat view: ON" or "Flat view: OFF"
    vim.notify("raphael: " .. msg, vim.log.levels.INFO)
    fns.render()
    M.highlight_current_line(ctx)
  end, { buffer = buf, desc = "Toggle flat/grouped view" })

  map("n", "gf", function()
    local open_fn = core.open_picker or core.open
    if type(open_fn) ~= "function" then
      vim.notify("raphael: core.open_picker/open not available", vim.log.levels.WARN)
      return
    end
    local target_opts
    if ctx.picker_type == "configured" then
      target_opts = { exclude_configured = true }
    else
      target_opts = {}
    end
    preview.close_code_preview()
    ctx.instances[ctx.picker_type] = false
    fns.close_picker(false)
    local ok, err = pcall(open_fn, target_opts)
    if not ok then
      vim.notify("raphael: failed to toggle picker (gf): " .. tostring(err), vim.log.levels.ERROR)
    end
  end, { buffer = buf, desc = "Toggle configured/other picker" })

  map("n", "/", function()
    fns.open_search()
  end, { buffer = buf, desc = "Search themes" })

  map("n", "b", function()
    local theme = parse_current_theme()
    if theme then
      core.toggle_bookmark(theme)
      refresh_bookmarks_set()
      fns.render(true)
    end
  end, { buffer = buf, desc = "Toggle bookmark" })

  map("n", "dd", function()
    if jump_to_current_theme(ctx) then
      return
    end
    local current = state.current
    if not current or current == "" then
      return
    end
    expand_groups_for_theme(current)
    render.render(ctx, true)
    jump_to_current_theme(ctx)
  end, { buffer = buf, desc = "Jump to current theme" })

  map("n", "XB", function()
    vim.ui.input({ prompt = "Clear all bookmarks? (y/N): " }, function(input)
      if not input or input:lower():sub(1, 1) ~= "y" then
        return
      end
      state.bookmarks = {}
      ctx.bookmarks = {}
      if core.save_state then
        pcall(core.save_state)
      end
      fns.render(true)
      M.highlight_current_line(ctx)
      vim.notify("raphael: cleared all bookmarks", vim.log.levels.INFO)
    end)
  end, { buffer = buf, desc = "Clear all bookmarks" })

  map("n", "XR", function()
    vim.ui.input({ prompt = "Clear recent history? (y/N): " }, function(input)
      if not input or input:lower():sub(1, 1) ~= "y" then
        return
      end
      state.history = {}
      if core.save_state then
        pcall(core.save_state)
      end
      fns.render(true)
      M.highlight_current_line(ctx)
      vim.notify("raphael: cleared recent history", vim.log.levels.INFO)
    end)
  end, { buffer = buf, desc = "Clear recent history" })

  map("n", "]b", function()
    if not next(ctx.bookmarks) then
      return
    end
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local cur = vim.api.nvim_win_get_cursor(win)[1]
    local skip_start, skip_end = 0, 0
    if core.config.bookmark_group ~= false then
      for _, ln in ipairs(ctx.header_lines) do
        if (lines[ln] or ""):find("Bookmarks") then
          skip_start = ln
          for _, next_ln in ipairs(ctx.header_lines) do
            if next_ln > ln then
              skip_end = next_ln - 1
              break
            end
          end
          if skip_end == 0 then
            skip_end = #lines
          end
          break
        end
      end
    end

    local function is_in_skip(i)
      return i >= skip_start and i <= skip_end
    end

    for i = cur + 1, #lines do
      if is_in_skip(i) then
        i = skip_end + 1
      end
      local theme = render.parse_line_theme(core, lines[i])
      if theme and ctx.bookmarks[theme] then
        vim.api.nvim_win_set_cursor(win, { i, 0 })
        M.highlight_current_line(ctx)
        return
      end
    end

    for i = 1, cur - 1 do
      if is_in_skip(i) then
        goto continue
      end
      local theme = render.parse_line_theme(core, lines[i])
      if theme and ctx.bookmarks[theme] then
        vim.api.nvim_win_set_cursor(win, { i, 0 })
        M.highlight_current_line(ctx)
        return
      end
      ::continue::
    end
  end, { buffer = buf, desc = "Next bookmark (skip group)" })

  map("n", "[b", function()
    if not next(ctx.bookmarks) then
      return
    end
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local cur = vim.api.nvim_win_get_cursor(win)[1]
    local skip_start, skip_end = 0, 0
    if core.config.bookmark_group ~= false then
      for _, ln in ipairs(ctx.header_lines) do
        if (lines[ln] or ""):find("Bookmarks") then
          skip_start = ln
          for _, next_ln in ipairs(ctx.header_lines) do
            if next_ln > ln then
              skip_end = next_ln - 1
              break
            end
          end
          if skip_end == 0 then
            skip_end = #lines
          end
          break
        end
      end
    end

    local function is_in_skip(i)
      return i >= skip_start and i <= skip_end
    end

    for i = cur - 1, 1, -1 do
      if is_in_skip(i) then
        i = skip_start - 1
      end
      local theme = render.parse_line_theme(core, lines[i])
      if theme and ctx.bookmarks[theme] then
        vim.api.nvim_win_set_cursor(win, { i, 0 })
        M.highlight_current_line(ctx)
        return
      end
    end

    for i = #lines, cur + 1, -1 do
      if is_in_skip(i) then
        goto continue
      end
      local theme = render.parse_line_theme(core, lines[i])
      if theme and ctx.bookmarks[theme] then
        vim.api.nvim_win_set_cursor(win, { i, 0 })
        M.highlight_current_line(ctx)
        return
      end
      ::continue::
    end
  end, { buffer = buf, desc = "Prev bookmark (skip group)" })

  map("n", "]r", function()
    if not (state.history and #state.history > 0) then
      return
    end
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local cur = vim.api.nvim_win_get_cursor(win)[1]
    local skip_start, skip_end = 0, 0
    if core.config.recent_group ~= false then
      for _, ln in ipairs(ctx.header_lines) do
        if (lines[ln] or ""):find("Recent") then
          skip_start = ln
          for _, next_ln in ipairs(ctx.header_lines) do
            if next_ln > ln then
              skip_end = next_ln - 1
              break
            end
          end
          if skip_end == 0 then
            skip_end = #lines
          end
          break
        end
      end
    end

    local function is_in_skip(i)
      return i >= skip_start and i <= skip_end
    end

    for i = cur + 1, #lines do
      if is_in_skip(i) then
        i = skip_end + 1
      end
      local theme = render.parse_line_theme(core, lines[i])
      if theme and vim.tbl_contains(state.history, theme) then
        vim.api.nvim_win_set_cursor(win, { i, 0 })
        M.highlight_current_line(ctx)
        return
      end
    end

    for i = 1, cur - 1 do
      if is_in_skip(i) then
        goto continue
      end
      local theme = render.parse_line_theme(core, lines[i])
      if theme and vim.tbl_contains(state.history, theme) then
        vim.api.nvim_win_set_cursor(win, { i, 0 })
        M.highlight_current_line(ctx)
        return
      end
      ::continue::
    end
  end, { buffer = buf, desc = "Next recent (skip group)" })

  map("n", "[r", function()
    if not (state.history and #state.history > 0) then
      return
    end
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local cur = vim.api.nvim_win_get_cursor(win)[1]
    local skip_start, skip_end = 0, 0
    if core.config.recent_group ~= false then
      for _, ln in ipairs(ctx.header_lines) do
        if (lines[ln] or ""):find("Recent") then
          skip_start = ln
          for _, next_ln in ipairs(ctx.header_lines) do
            if next_ln > ln then
              skip_end = next_ln - 1
              break
            end
          end
          if skip_end == 0 then
            skip_end = #lines
          end
          break
        end
      end
    end

    local function is_in_skip(i)
      return i >= skip_start and i <= skip_end
    end

    for i = cur - 1, 1, -1 do
      if is_in_skip(i) then
        i = skip_start - 1
      end
      local theme = render.parse_line_theme(core, lines[i])
      if theme and vim.tbl_contains(state.history, theme) then
        vim.api.nvim_win_set_cursor(win, { i, 0 })
        M.highlight_current_line(ctx)
        return
      end
    end

    for i = #lines, cur + 1, -1 do
      if is_in_skip(i) then
        goto continue
      end
      local theme = render.parse_line_theme(core, lines[i])
      if theme and vim.tbl_contains(state.history, theme) then
        vim.api.nvim_win_set_cursor(win, { i, 0 })
        M.highlight_current_line(ctx)
        return
      end
      ::continue::
    end
  end, { buffer = buf, desc = "Prev recent (skip group)" })

  map("n", "]g", function()
    local cur = vim.api.nvim_win_get_cursor(win)[1]
    for _, ln in ipairs(ctx.header_lines) do
      if ln > cur then
        vim.api.nvim_win_set_cursor(win, { ln, 0 })
        M.highlight_current_line(ctx)
        return
      end
    end
    if #ctx.header_lines > 0 then
      vim.api.nvim_win_set_cursor(win, { ctx.header_lines[1], 0 })
      M.highlight_current_line(ctx)
    end
  end, { buffer = buf, desc = "Next group" })

  map("n", "[g", function()
    local cur = vim.api.nvim_win_get_cursor(win)[1]
    for i = #ctx.header_lines, 1, -1 do
      if ctx.header_lines[i] < cur then
        vim.api.nvim_win_set_cursor(win, { ctx.header_lines[i], 0 })
        M.highlight_current_line(ctx)
        return
      end
    end
    if #ctx.header_lines > 0 then
      vim.api.nvim_win_set_cursor(win, { ctx.header_lines[#ctx.header_lines], 0 })
      M.highlight_current_line(ctx)
    end
  end, { buffer = buf, desc = "Previous group" })

  map("n", "r", function()
    local all_themes = themes.get_all_themes()
    if #all_themes == 0 then
      vim.notify("No themes available", vim.log.levels.WARN)
      return
    end
    math.randomseed(os.time())
    local random_idx = math.random(#all_themes)
    local random_theme = all_themes[random_idx]
    if themes.is_available(random_theme) then
      local ok, err = pcall(core.apply, random_theme, true)
      if ok then
        preview.preview_theme(ctx, random_theme)
        fns.render()
        M.highlight_current_line(ctx)
        vim.notify("  Random: " .. random_theme, vim.log.levels.INFO)
      else
        vim.notify("Failed to apply random theme: " .. tostring(err), vim.log.levels.ERROR)
      end
    else
      vim.notify("Random theme not available", vim.log.levels.WARN)
    end
  end, { buffer = buf, desc = "Apply random theme" })

  map("n", "H", function()
    history.show()
  end, { buffer = buf, desc = "Show theme history" })

  map("n", "u", function()
    local theme = history.undo(function(t)
      pcall(core.apply, t, false)
    end)
    if theme then
      preview.preview_theme(ctx, theme)
      fns.render()
      M.highlight_current_line(ctx)
    end
  end, { buffer = buf, desc = "Undo theme change" })

  map("n", "<C-r>", function()
    local theme = history.redo(function(t)
      pcall(core.apply, t, false)
    end)
    if theme then
      preview.preview_theme(ctx, theme)
      fns.render()
      M.highlight_current_line(ctx)
    end
  end, { buffer = buf, desc = "Redo theme change" })

  map("n", "J", function()
    local stats = history.stats()
    if stats.total == 0 then
      vim.notify("No history data", vim.log.levels.INFO)
      return
    end

    vim.ui.input({
      prompt = string.format("Jump to position (1-%d): ", stats.total),
      default = tostring(stats.position),
    }, function(input)
      if not input then
        return
      end
      local pos = tonumber(input)
      if not pos then
        vim.notify("Invalid position", vim.log.levels.ERROR)
        return
      end

      local theme = history.jump(pos, function(t)
        pcall(core.apply, t, false)
      end)
      if theme then
        preview.preview_theme(ctx, theme)
        fns.render()
        M.highlight_current_line(ctx)
      end
    end)
  end, { buffer = buf, desc = "Jump to history position" })

  map("n", "T", function()
    local stats = history.stats()
    if stats.total == 0 then
      vim.notify("No history data", vim.log.levels.INFO)
      return
    end

    local lines = {
      C.ICON.STATS .. "Theme History:",
      "",
      string.format("Position: %d/%d", stats.position, stats.total),
      string.format("Unique: %d themes", stats.unique_themes),
      string.format("Most used: %s (%dx)", stats.most_used, stats.most_used_count),
    }

    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
  end, { buffer = buf, desc = "Show quick stats" })

  map("n", "a", function()
    if ctx.search_query ~= "" or ctx.search_scope ~= nil then
      ctx.search_query = ""
      ctx.search_scope = nil
      fns.render()
      M.highlight_current_line(ctx)
    end
  end, { buffer = buf, desc = "Clear search / show all themes" })

  map("n", "<C-l>", function()
    M.go_in_group(ctx)
  end, { buffer = buf, desc = "Go in group" })

  map("n", "<C-h>", function()
    M.go_out_group(ctx)
  end, { buffer = buf, desc = "Go out of group" })

  for d = 0, 9 do
    local slot = tostring(d)

    map("n", "m" .. slot, function()
      assign_quick_slot(slot)
    end, { buffer = buf, desc = "Assign theme to quick slot " .. slot })

    map("n", slot, function()
      jump_to_quick_slot(slot)
    end, { buffer = buf, desc = "Jump to quick slot " .. slot })
  end

  map("n", "?", function()
    vim.notify(table.concat(help_lines, "\n"), vim.log.levels.INFO)
  end, { buffer = buf, desc = "Show help" })

  if core.config.sample_preview and core.config.sample_preview.enabled then
    map("n", "i", function()
      preview.toggle_and_iterate_preview(ctx)
    end, { buffer = buf, silent = true, noremap = true, desc = "Toggle/next code sample preview" })

    map("n", "I", function()
      preview.iterate_backward_preview(ctx)
    end, { buffer = buf, silent = true, noremap = true, desc = "Previous code sample language" })

    map("n", "C", function()
      local hdr = parse_current_header()
      if hdr then
        vim.notify("Cannot compare on a group header", vim.log.levels.WARN)
        return
      end
      local theme = parse_current_theme()
      if not theme then
        vim.notify("No theme on this line to compare", vim.log.levels.WARN)
        return
      end
      if not core.state.current then
        vim.notify("No active theme to compare against", vim.log.levels.WARN)
        return
      end
      preview.toggle_compare(ctx, theme)
    end, { buffer = buf, silent = true, noremap = true, desc = "Compare with current theme" })
  end

  map("n", "<C-A-k>", function()
    set_all_groups_collapsed(true)
  end, { buffer = buf, desc = "Collapse all groups" })

  map("n", "<C-A-j>", function()
    set_all_groups_collapsed(false)
  end, { buffer = buf, desc = "Expand all groups" })

  map("n", "<C-i>", function() end, { buffer = buf, desc = "Disabled: jump forward" })
  map("n", "<C-o>", function() end, { buffer = buf, desc = "Disabled: jump backward" })
  map("n", "<C-w>", function() end, { buffer = buf, desc = "Disabled: window prefix" })
  map("n", "<C-w>h", function() end, { buffer = buf, desc = "Disabled: window left" })
  map("n", "<C-w>j", function() end, { buffer = buf, desc = "Disabled: window down" })
  map("n", "<C-w>k", function() end, { buffer = buf, desc = "Disabled: window up" })
  map("n", "<C-w>l", function() end, { buffer = buf, desc = "Disabled: window right" })
  map("n", "<C-w>c", function() end, { buffer = buf, desc = "Disabled: close window" })
  map("n", "<C-w>o", function() end, { buffer = buf, desc = "Disabled: only window" })
end

return M
