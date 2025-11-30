-- lua/raphael/picker/render.lua
-- Rendering logic for Raphael's theme picker.
--
-- Responsibilities:
--   - Build the list of lines to show in the picker buffer
--   - Handle:
--       * grouped vs flat theme_map
--       * nested groups (tables inside tables) with headers
--       * bookmarks & recent sections
--       * sort modes: alpha, recent, usage, custom
--   - Track header_lines & last_cursor via ctx

local M = {}

local themes = require("raphael.themes")
local C = require("raphael.constants")

--- Parse a group header line of the form:
---   "<icon> <group_name> (N)"
---
---@param line string
---@return string|nil group_name
function M.parse_line_header(line)
  local captured = line:match("^%s*[^%s]+%s+(.+)%s*%(%d+%)%s*$")
  if not captured then
    return nil
  end
  captured = captured:gsub("^%s+", ""):gsub("%s+$", "")
  return captured ~= "" and captured or nil
end

--- Parse a theme name from a picker line, resolving aliases.
---
--- Rules:
--- - If line ends with "(N)" treat as header → nil
--- - Strip WARN icon
--- - Try last word as theme, stripping punctuation
--- - Resolve aliases via core.config.theme_aliases
---
---@param core table # require("raphael.core")
---@param line string
---@return string|nil theme
function M.parse_line_theme(core, line)
  if not line or line == "" then
    return nil
  end
  if line:match("%(%d+%)%s*$") then
    return nil
  end

  line = line:gsub("%s*" .. C.ICON.WARN, "")

  local cfg = core.config or {}
  local aliases = cfg.theme_aliases or {}
  local reverse_aliases = {}
  for alias, real in pairs(aliases) do
    reverse_aliases[alias] = real
  end

  local last = line:match("([%w_%-]+)%s*$")
  if last and last ~= "" then
    return reverse_aliases[last] or last
  end

  last = nil
  for token in line:gmatch("%S+") do
    last = token
  end

  if last then
    last = last:gsub("^[^%w_%-]+", ""):gsub("[^%w_%-]+$", "")
    if last ~= "" then
      return reverse_aliases[last] or last
    end
  end

  return nil
end

--- Debounce helper for render; ensures we don't over-render on fast events.
---
---@param ms integer
---@param fn fun(ctx:table)
---@return fun(ctx:table)
local function debounce(ms, fn)
  local timer = nil
  return function(ctx)
    if timer then
      local ok = pcall(function()
        if timer and not timer:is_closing() then
          timer:stop()
          vim.schedule(function()
            if timer and not timer:is_closing() then
              timer:close()
            end
          end)
        end
      end)
      if not ok then
      end
      timer = nil
    end
    timer = vim.defer_fn(function()
      pcall(fn, ctx)
      timer = nil
    end, ms)
  end
end

--- Internal render function (not debounced).
---
--- Expects ctx with:
---   ctx.buf, ctx.win, ctx.core, ctx.state
---   ctx.collapsed, ctx.bookmarks (set: theme -> true)
---   ctx.search_query : string|nil
---   ctx.search_scope : string|nil
---   ctx.header_lines (out), ctx.last_cursor (in/out), ctx.last_line (in/out)
---   ctx.opts.only_configured / exclude_configured
---   ctx.flags.disable_sorting, ctx.flags.reverse_sorting
---
---@param ctx table
local function render_internal(ctx)
  local picker_buf = ctx.buf
  local picker_win = ctx.win
  local core = ctx.core
  local state = ctx.state

  if not picker_buf or not vim.api.nvim_buf_is_valid(picker_buf) then
    return
  end

  local opts = ctx.opts or {}
  local only_configured = opts.only_configured or false
  local exclude_configured = opts.exclude_configured or false

  local picker_ns = vim.api.nvim_create_namespace("raphael_picker_content")
  pcall(vim.api.nvim_buf_clear_namespace, picker_buf, picker_ns, 0, -1)

  if only_configured and exclude_configured then
    vim.notify("raphael: both only_configured and exclude_configured are true", vim.log.levels.WARN)
    return
  end

  local current_group
  local current_line = 1
  local current_theme

  if picker_win and vim.api.nvim_win_is_valid(picker_win) then
    local ok_cur, cursor = pcall(vim.api.nvim_win_get_cursor, picker_win)
    if ok_cur then
      current_line = cursor[1]
      ctx.last_line = current_line

      local before_lines = vim.api.nvim_buf_get_lines(picker_buf, 0, -1, false)
      local line = before_lines[current_line] or ""

      current_theme = M.parse_line_theme(core, line)

      local header_name = M.parse_line_header(line)
      if header_name then
        current_group = header_name
        ctx.last_cursor[current_group] = current_line
      else
        for i = current_line, 1, -1 do
          local maybe = M.parse_line_header(before_lines[i])
          if maybe then
            current_group = maybe
            break
          end
        end
      end
    end
  end

  local lines = {}
  ctx.header_lines = {}

  local cfg = core.config
  local show_bookmarks = cfg.bookmark_group ~= false
  local show_recent = cfg.recent_group ~= false

  local indent_width = tonumber(cfg.group_indent) or 2
  if indent_width < 0 then indent_width = 0 end
  if indent_width > 8 then indent_width = 8 end

  local function indent_for_level(level)
    return string.rep(" ", indent_width * level)
  end

  local display_map = vim.deepcopy(themes.theme_map)
  if exclude_configured then
    local all_installed = vim.tbl_keys(themes.installed)
    table.sort(all_installed)
    local all_configured = themes.get_all_themes()
    local extras = {}
    for _, theme in ipairs(all_installed) do
      if not vim.tbl_contains(all_configured, theme) then
        table.insert(extras, theme)
      end
    end
    display_map = extras
  end

  local is_display_grouped = not vim.islist(display_map)
  local sort_mode = state.sort_mode or cfg.sort_mode or "alpha"

  local disable_sorting = ctx.flags.disable_sorting
  local reverse_sorting = ctx.flags.reverse_sorting

  --- Sort a flat list of theme names according to current sort mode.
  --- Mutates `filtered` in-place.
  ---
  ---@param filtered string[]
  local function sort_filtered(filtered)
    if disable_sorting then
      return
    end

    local function cmp_alpha(a, b)
      if reverse_sorting then
        return a:lower() > b:lower()
      end
      return a:lower() < b:lower()
    end

    local function cmp_recent(a, b)
      local idx_a = vim.fn.index(state.history or {}, a) or -1
      local idx_b = vim.fn.index(state.history or {}, b) or -1
      if reverse_sorting then
        return idx_a < idx_b
      end
      return idx_a > idx_b
    end

    local function cmp_usage(a, b)
      local count_a = (state.usage or {})[a] or 0
      local count_b = (state.usage or {})[b] or 0
      if reverse_sorting then
        return count_a < count_b
      end
      return count_a > count_b
    end

    if sort_mode == "alpha" then
      table.sort(filtered, cmp_alpha)
    elseif sort_mode == "recent" then
      table.sort(filtered, cmp_recent)
    elseif sort_mode == "usage" then
      table.sort(filtered, cmp_usage)
    end

    local custom_sorts = cfg.custom_sorts or {}
    local custom_func = custom_sorts[sort_mode]
    if custom_func then
      table.sort(filtered, custom_func)
      if reverse_sorting then
        for i = 1, math.floor(#filtered / 2) do
          filtered[i], filtered[#filtered - i + 1] = filtered[#filtered - i + 1], filtered[i]
        end
      end
    end
  end

  local search_query = ctx.search_query or ""
  local search_scope = ctx.search_scope
  local has_search = (search_query ~= "") or (search_scope ~= nil)
  local collapsed = ctx.collapsed
  local bookmarks = ctx.bookmarks or {}

  if show_bookmarks then
    local bookmark_themes = {}
    for t, is_marked in pairs(bookmarks) do
      if is_marked then
        table.insert(bookmark_themes, t)
      end
    end

    table.sort(bookmark_themes, function(a, b)
      return a:lower() < b:lower()
    end)

    local bookmark_filtered = {}
    for _, t in ipairs(bookmark_themes) do
      if search_query == "" or t:lower():find(search_query:lower(), 1, true) then
        table.insert(bookmark_filtered, t)
      end
    end

    if #bookmark_filtered > 0 then
      local group = "__bookmarks"
      local bookmark_icon = collapsed[group] and C.ICON.GROUP_COLLAPSED or C.ICON.GROUP_EXPANDED
      table.insert(lines, bookmark_icon .. " Bookmarks (" .. #bookmark_themes .. ")")
      table.insert(ctx.header_lines, #lines)

      if not collapsed[group] then
        local prefix = indent_for_level(1)
        for _, t in ipairs(bookmark_filtered) do
          local display = cfg.theme_aliases[t] or t
          local warning = themes.is_available(t) and "" or C.ICON.WARN
          local b = C.ICON.BOOKMARK
          local s = (state.current == t) and C.ICON.CURRENT_ON or C.ICON.CURRENT_OFF
          table.insert(lines, prefix .. warning .. b .. s .. display)
        end
      end
    end
  end

  if show_recent then
    local recent_filtered = {}
    for _, t in ipairs(state.history or {}) do
      if search_query == "" or t:lower():find(search_query:lower(), 1, true) then
        table.insert(recent_filtered, t)
      end
    end

    if #recent_filtered > 0 then
      local group = "__recent"
      local recent_icon = collapsed[group] and C.ICON.GROUP_COLLAPSED or C.ICON.GROUP_EXPANDED
      table.insert(lines, recent_icon .. " Recent (" .. #state.history .. ")")
      table.insert(ctx.header_lines, #lines)

      if not collapsed[group] then
        local prefix = indent_for_level(1)
        for _, t in ipairs(recent_filtered) do
          local display = cfg.theme_aliases[t] or t
          local warning = themes.is_available(t) and "" or C.ICON.WARN
          local b = bookmarks[t] and C.ICON.BOOKMARK or " "
          local s = (state.current == t) and C.ICON.CURRENT_ON or C.ICON.CURRENT_OFF
          table.insert(lines, prefix .. warning .. b .. s .. display)
        end
      end
    end
  end

  local function render_group(group_name, node, depth)
    if node == nil then
      return
    end

    local list_items = {}
    local map_items = {}

    if type(node) == "table" then
      if vim.islist(node) then
        list_items = vim.deepcopy(node)
      else
        for k, v in pairs(node) do
          if type(k) == "number" then
            table.insert(list_items, v)
          else
            map_items[k] = v
          end
        end
      end
    elseif type(node) == "string" then
      list_items = { node }
    else
      return
    end

    local leaf_themes = {}
    local function collect_leaves(n)
      local t = type(n)
      if t == "string" then
        table.insert(leaf_themes, n)
      elseif t == "table" then
        if vim.islist(n) then
          for _, v in ipairs(n) do
            collect_leaves(v)
          end
        else
          for _, v in pairs(n) do
            collect_leaves(v)
          end
        end
      end
    end
    collect_leaves(node)
    if #leaf_themes == 0 then
      return
    end

    local indent = indent_for_level(depth)
    local header_key = group_name
    local is_collapsed = ctx.collapsed[header_key] == true
    local header_icon = is_collapsed and C.ICON.GROUP_COLLAPSED or C.ICON.GROUP_EXPANDED
    local summary = string.format("(%d)", #leaf_themes)

    table.insert(lines, string.format("%s%s %s %s", indent, header_icon, group_name, summary))
    table.insert(ctx.header_lines, #lines)

    if is_collapsed then
      return
    end

    if #list_items > 0 then
      sort_filtered(list_items)
      local line_indent = indent_for_level(depth + 1)
      for _, t in ipairs(list_items) do
        local display = cfg.theme_aliases[t] or t
        local warning = themes.is_available(t) and "" or C.ICON.WARN
        local b = bookmarks[t] and C.ICON.BOOKMARK or " "
        local s = (state.current == t) and C.ICON.CURRENT_ON or C.ICON.CURRENT_OFF
        table.insert(lines, string.format("%s%s%s %s %s", line_indent, warning, b, s, display))
      end
    end

    for subname, subnode in pairs(map_items) do
      render_group(subname, subnode, depth + 1)
    end
  end

  if has_search then
    local flat_candidates
    if is_display_grouped then
      flat_candidates = {}
      local seen = {}

      local function path_has_scope(path)
        if not search_scope or search_scope == "" then
          return true
        end
        for _, name in ipairs(path) do
          if name == search_scope then
            return true
          end
        end
        return false
      end

      local function collect_flat(node, path)
        local t = type(node)
        if t == "string" then
          if path_has_scope(path) and not seen[node] then
            table.insert(flat_candidates, node)
            seen[node] = true
          end
        elseif t == "table" then
          if vim.islist(node) then
            for _, v in ipairs(node) do
              collect_flat(v, path)
            end
          else
            for k, v in pairs(node) do
              if type(k) == "string" then
                table.insert(path, k)
                collect_flat(v, path)
                path[#path] = nil
              else
                collect_flat(v, path)
              end
            end
          end
        end
      end

      collect_flat(display_map, {})
    else
      flat_candidates = display_map
    end

    local flat_filtered
    if search_query == "" then
      flat_filtered = flat_candidates
    else
      flat_filtered = vim.fn.matchfuzzy(flat_candidates, search_query, { text = true })
    end

    sort_filtered(flat_filtered)

    local header_label = "Results"
    if search_scope and search_scope ~= "" then
      header_label = string.format("Results [%s]", search_scope)
    end
    local results_count = #flat_filtered
    table.insert(lines, string.format("%s (%d)", header_label, results_count))

    for _, t in ipairs(flat_filtered) do
      local display = cfg.theme_aliases[t] or t
      local warning = themes.is_available(t) and "" or C.ICON.WARN
      local b = bookmarks[t] and C.ICON.BOOKMARK or " "
      local s = (state.current == t) and C.ICON.CURRENT_ON or C.ICON.CURRENT_OFF
      table.insert(lines, string.format("%s%s %s %s", warning, b, s, display))
    end
  else
    if not is_display_grouped then
      local flat_candidates = display_map
      local flat_filtered = flat_candidates
      sort_filtered(flat_filtered)
      for _, t in ipairs(flat_filtered) do
        local display = cfg.theme_aliases[t] or t
        local warning = themes.is_available(t) and "" or C.ICON.WARN
        local b = bookmarks[t] and C.ICON.BOOKMARK or " "
        local s = (state.current == t) and C.ICON.CURRENT_ON or C.ICON.CURRENT_OFF
        table.insert(lines, string.format("%s%s %s %s", warning, b, s, display))
      end
    else
      for group, node in pairs(display_map) do
        render_group(group, node, 0)
      end
    end
  end

  if #lines == 0 then
    table.insert(lines, " No themes found")
  end

  pcall(vim.api.nvim_set_option_value, "modifiable", true, { buf = picker_buf })
  pcall(vim.api.nvim_buf_set_lines, picker_buf, 0, -1, false, lines)
  pcall(vim.api.nvim_set_option_value, "modifiable", false, { buf = picker_buf })

  do
    local query = ctx.search_query or ""
    local ns_search = C.NS.SEARCH_MATCH

    pcall(vim.api.nvim_buf_clear_namespace, picker_buf, ns_search, 0, -1)

    if query ~= "" then
      local q_lower = query:lower()

      local function fuzzy_positions(line, q)
        local l = line:lower()
        local positions = {}
        local i = 1
        for j = 1, #q do
          local c = q:sub(j, j)
          local found = l:find(c, i, true)
          if not found then
            return nil
          end
          positions[#positions + 1] = found
          i = found + 1
        end
        return positions
      end

      for i, line in ipairs(lines) do
        if line ~= "" then
          local pos = (#query >= 2) and fuzzy_positions(line, query) or nil

          if pos and #pos > 0 then
            local start_col_1
            local last_col_1

            for _, col_1 in ipairs(pos) do
              if not start_col_1 then
                start_col_1 = col_1
                last_col_1 = col_1
              elseif col_1 == last_col_1 + 1 then
                last_col_1 = col_1
              else
                pcall(vim.api.nvim_buf_set_extmark, picker_buf, ns_search, i - 1, start_col_1 - 1, {
                  end_col = last_col_1,
                  hl_group = "Search",
                  strict = false,
                })
                start_col_1 = col_1
                last_col_1 = col_1
              end
            end

            if start_col_1 then
              pcall(vim.api.nvim_buf_set_extmark, picker_buf, ns_search, i - 1, start_col_1 - 1, {
                end_col = last_col_1,
                hl_group = "Search",
                strict = false,
              })
            end
          else
            local lline = line:lower()
            local s, e = lline:find(q_lower, 1, true)
            if s and e then
              pcall(vim.api.nvim_buf_set_extmark, picker_buf, ns_search, i - 1, s - 1, {
                end_col = e,
                hl_group = "Search",
                strict = false,
              })
            end
          end
        end
      end
    end
  end

  if picker_win and vim.api.nvim_win_is_valid(picker_win) and #lines > 0 then
    local restore_line

    if current_theme then
      if current_group then
        for i, line in ipairs(lines) do
          local t = M.parse_line_theme(core, line)
          if t == current_theme then
            -- find this line's group in the new buffer
            local line_group
            for j = i, 1, -1 do
              local maybe = M.parse_line_header(lines[j] or "")
              if maybe then
                line_group = maybe
                break
              end
            end
            if line_group == current_group then
              restore_line = i
              break
            end
          end
        end
      end

      if not restore_line then
        for i, line in ipairs(lines) do
          local t = M.parse_line_theme(core, line)
          if t == current_theme then
            restore_line = i
            break
          end
        end
      end
    end

    if not restore_line and ctx.last_line then
      restore_line = math.max(1, math.min(ctx.last_line, #lines))
    end

    if not restore_line and current_group and ctx.last_cursor[current_group] then
      restore_line = math.max(1, math.min(ctx.last_cursor[current_group], #lines))
    end

    if not restore_line then
      restore_line = 1
    end

    pcall(vim.api.nvim_win_set_cursor, picker_win, { restore_line, 0 })
  end
end

local render_debounced = debounce(50, render_internal)

--- Render the picker contents (possibly debounced).
---
---@param ctx table
---@param immediate boolean|nil  If true, do not debounce
function M.render(ctx, immediate)
  if immediate then
    render_internal(ctx)
  else
    render_debounced(ctx)
  end
end

return M
