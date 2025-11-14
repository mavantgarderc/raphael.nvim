local M = {}

local themes = require("raphael.themes")
local history = require("raphael.theme_history")
local samples = require("raphael.samples")
local autocmds = require("raphael.autocmds")

local map = vim.keymap.set

local picker_instances = {
  configured = false,
  all = false,
}

local picker_buf, picker_win
local palette_buf, palette_win
local search_buf, search_win

local picker_w, picker_h, picker_row, picker_col

---@diagnostic disable-next-line: unused-local
local previewed -- luacheck: ignore previewed
local core_ref, state_ref
local collapsed = {}
local bookmarks = {}
local search_query = ""
local picker_opts = {}
local header_lines = {}
local last_cursor = {}
local active_timers = {}
local RENDER_DEBOUNCE_MS = 50
local DEBUG_MODE = false

local ICON_BOOKMARK = "  "
local ICON_CURRENT_ON = "  "
local ICON_CURRENT_OFF = "  "
local ICON_GROUP_EXP = "  "
local ICON_GROUP_COL = "  "
local BLOCK_CHAR = "  "
local ICON_SEARCH = "   "
local ICON_STATS = "  "
local WANR_ICON = " 󰝧 "

local disable_sorting = false
local reverse_sorting = false

local palette_hl_cache = {}
local PALETTE_HL = {
  "Normal",
  "Comment",
  "String",
  "Keyword",
  "Function",
  "Type",
  "Constant",
  "Special",
}

local help = {
  "Raphael Picker - Keybindings:",
  "",
  "Navigation:",
  "  `j`/`k`         - Navigate (wraps around)",
  "  `<C-j>`/`<C-k>` - Jump to next/prev group header (wraps)",
  "  `[g`/`]g`       - Jump to prev/next group header (wraps)",
  "  `[b`/`]b`       - Jump to prev/next bookmark",
  "  `[r`/`]r`       - Jump to prev/next history state",
  "",
  "Actions:",
  "  `<CR>`        - Select theme",
  "  `c`           - Collapse/expand group",
  "  `s`           - Cycle sort mode",
  "  `S`           - Toggle sorting on/off",
  "  `R`           - Toggle reverse sorting (descending)",
  "  `/`           - Search themes",
  "  `b`           - Toggle bookmark",
  "",
  "History (picker-only):",
  "  `u`           - Undo theme change",
  "  `<C-r>`       - Redo theme change",
  "  `H`           - Show full history",
  "  `J`           - Jump to history position",
  "  `T`           - Show quick stats",
  "  `r`           - Apply random theme",
  "  `i`           - Show Code Sample, Iterate languages forward",
  "  `I`           - Iterate languages backward",
  "",
  "Other:",
  "  `q`/`<Esc>`     - Quit (revert theme)",
  "  `?`             - Show this help",
}

local code_buf = nil
local code_win = nil
local current_lang = nil
local is_preview_visible = false

local function log(level, msg, data)
  if DEBUG_MODE or level == "ERROR" or level == "WARN" then
    local prefix = string.format("[Raphael:%s]", level)
    if data then
      vim.notify(string.format("%s %s: %s", prefix, msg, vim.inspect(data)), vim.log.levels[level])
    else
      vim.notify(string.format("%s %s", prefix, msg), vim.log.levels[level])
    end
  end
end

local function debounce(ms, fn)
  local timer = nil
  return function(...)
    local args = { ... }
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
        log("WARN", "Failed to cleanup debounce timer")
      end
      timer = nil
    end
    timer = vim.defer_fn(function()
      -- luacheck: ignore 113 (unpack)
      local success, err = pcall(fn, unpack(args))
      if not success then
        log("ERROR", "Debounced function error", err)
      end
      timer = nil
    end, ms)
  end
end

local function cleanup_timers()
  for key, timer in pairs(active_timers) do
    if timer and not timer:is_closing() then
      pcall(timer.stop, timer)
      pcall(timer.close, timer)
    end
    active_timers[key] = nil
  end
end

local function trim(s)
  return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function parse_line_theme(line)
  if not line or line == "" then
    return nil
  end
  if line:match("%(%d+%)%s*$") then
    return nil
  end
  line = line:gsub("%s* " .. WANR_ICON, "")
  local theme = line:match("([%w_%-]+)%s*$")
  if theme and theme ~= "" then
    local aliases = core_ref.config.theme_aliases or {}
    local reverse_aliases = {}
    for alias, real in pairs(aliases) do
      reverse_aliases[alias] = real
    end
    return reverse_aliases[theme] or theme
  end
  local last
  for token in line:gmatch("%S+") do
    last = token
  end
  if last then
    last = last:gsub("^[^%w_%-]+", ""):gsub("[^%w_%-]+$", "")
    if last ~= "" then
      local aliases = core_ref.config.theme_aliases or {}
      local reverse_aliases = {}
      for alias, real in pairs(aliases) do
        reverse_aliases[alias] = real
      end
      return reverse_aliases[last] or last
    end
  end
  return nil
end

local function parse_line_header(line)
  local captured = line:match("^%s*[^%s]+%s+(.+)%s*%(%d+%)%s*$")
  return captured and trim(captured) or nil
end

local function get_hl_rgb(name)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  if ok and hl then
    return hl
  end
  return nil
end

local function ensure_palette_hl(idx, color_int)
  if not color_int then
    return nil
  end
  local key = ("raphaelPalette_%d_%x"):format(idx, color_int)
  if palette_hl_cache[key] then
    return key
  end
  local ok = pcall(vim.api.nvim_set_hl, 0, key, { fg = color_int })
  if not ok then
    log("WARN", "Failed to set palette highlight", key)
    return nil
  end
  palette_hl_cache[key] = true
  return key
end

function M.update_palette(theme)
  if not theme or not themes.is_available(theme) then
    if palette_win and vim.api.nvim_win_is_valid(palette_win) then
      pcall(vim.api.nvim_win_close, palette_win, true)
    end
    palette_win, palette_buf = nil, nil
    return
  end

  ---@diagnostic disable-next-line: unused-local
  previewed = theme

  if not picker_win or not vim.api.nvim_win_is_valid(picker_win) or not picker_w then
    return
  end

  if not palette_buf or not vim.api.nvim_buf_is_valid(palette_buf) then
    palette_buf = vim.api.nvim_create_buf(false, true)
    pcall(vim.api.nvim_set_option_value, "buftype", "nofile", { buf = palette_buf })
    pcall(vim.api.nvim_set_option_value, "bufhidden", "wipe", { buf = palette_buf })
    pcall(vim.api.nvim_set_option_value, "modifiable", false, { buf = palette_buf })
  end

  local blocks = {}
  for i = 1, #PALETTE_HL do
    blocks[i] = BLOCK_CHAR
  end
  local blocks_str = table.concat(blocks, " ")
  local display_w = vim.fn.strdisplaywidth(blocks_str)
  local pad = math.max(math.floor((picker_w - display_w) / 2), 0)
  local line = string.rep(" ", pad) .. blocks_str

  pcall(vim.api.nvim_set_option_value, "modifiable", true, { buf = palette_buf })
  pcall(vim.api.nvim_buf_set_lines, palette_buf, 0, -1, false, { line })
  pcall(vim.api.nvim_set_option_value, "modifiable", false, { buf = palette_buf })

  local bufline = (vim.api.nvim_buf_get_lines(palette_buf, 0, 1, false) or { "" })[1] or ""
  local ns = vim.api.nvim_create_namespace("raphael_palette")
  pcall(vim.api.nvim_buf_clear_namespace, palette_buf, ns, 0, -1)

  if not palette_hl_cache[theme] then
    palette_hl_cache[theme] = {}
    for _, hl_name in ipairs(PALETTE_HL) do
      local hl = get_hl_rgb(hl_name)
      if hl then
        palette_hl_cache[theme][hl_name] = hl.fg or hl.bg
      end
    end
    log("DEBUG", "Cached palette for theme", theme)
  else
    log("DEBUG", "Using cached palette for theme", theme)
  end

  for i, hl_name in ipairs(PALETTE_HL) do
    local color_int = palette_hl_cache[theme][hl_name]
    if color_int then
      local gname = ensure_palette_hl(i, color_int)
      if gname then
        local search_pos, occurrence = 1, 0
        while true do
          local s, e = string.find(bufline, BLOCK_CHAR, search_pos, true)
          if not s then
            break
          end
          occurrence = occurrence + 1
          if occurrence == i then
            pcall(
              vim.api.nvim_buf_set_extmark,
              palette_buf,
              ns,
              0,
              s - 1,
              { end_col = e, hl_group = gname, strict = false }
            )
            break
          end
          search_pos = e + 1
        end
      end
    end
  end

  vim.cmd("redraw!")

  local pal_row, pal_col, pal_width = math.max(picker_row - 2, 0), picker_col, picker_w
  if palette_win and vim.api.nvim_win_is_valid(palette_win) then
    pcall(vim.api.nvim_win_set_buf, palette_win, palette_buf)
    pcall(
      vim.api.nvim_win_set_config,
      palette_win,
      { relative = "editor", width = pal_width, height = 1, row = pal_row, col = pal_col, style = "minimal" }
    )
  else
    palette_win = vim.api.nvim_open_win(palette_buf, false, {
      relative = "editor",
      width = pal_width,
      height = 1,
      row = pal_row,
      col = pal_col,
      style = "minimal",
      zindex = 50,
    })
    pcall(vim.api.nvim_set_option_value, "winhl", "Normal:Normal", { win = palette_win })
  end
end

local HIGHLIGHT_NS = vim.api.nvim_create_namespace("raphael_picker_cursor")

local function highlight_current_line()
  if
    not picker_buf
    or not vim.api.nvim_buf_is_valid(picker_buf)
    or not picker_win
    or not vim.api.nvim_win_is_valid(picker_win)
  then
    return
  end

  local ok, cursor = pcall(vim.api.nvim_win_get_cursor, picker_win)
  if not ok then
    return
  end

  local cur_line = cursor[1] - 1
  pcall(vim.api.nvim_buf_clear_namespace, picker_buf, HIGHLIGHT_NS, 0, -1)

  local line_text = vim.api.nvim_buf_get_lines(picker_buf, cur_line, cur_line + 1, false)[1] or ""
  if not line_text:match("^" .. ICON_GROUP_EXP) and not line_text:match("^" .. ICON_GROUP_COL) then
    pcall(
      vim.highlight.range,
      picker_buf,
      HIGHLIGHT_NS,
      "Visual",
      { cur_line, 0 },
      { cur_line, -1 },
      { inclusive = false, priority = 100 }
    )
  end
end

local function render_internal(opts)
  opts = opts or picker_opts
  picker_opts = opts
  local only_configured = opts.only_configured or false
  local exclude_configured = opts.exclude_configured or false
  local picker_ns = vim.api.nvim_create_namespace("raphael_picker_content")
  pcall(vim.api.nvim_buf_clear_namespace, picker_buf, picker_ns, 0, -1)

  if only_configured and exclude_configured then
    log("WARN", "Both only_configured and exclude_configured are true")
    return
  end
  if not picker_buf or not vim.api.nvim_buf_is_valid(picker_buf) then
    log("ERROR", "Picker buffer is invalid")
    return
  end

  local current_group
  -- luacheck: ignore
  local current_line = 1
  if picker_win and vim.api.nvim_win_is_valid(picker_win) then
    local ok, cursor = pcall(vim.api.nvim_win_get_cursor, picker_win)
    if ok then
      current_line = cursor[1]
      local lines_before = vim.api.nvim_buf_get_lines(picker_buf, 0, -1, false)
      local line = lines_before[current_line] or ""
      current_group = parse_line_header(line)
      if not current_group then
        for i = current_line, 1, -1 do
          local maybe = parse_line_header(lines_before[i])
          if maybe then
            current_group = maybe
            break
          end
        end
      end
      if current_group then
        last_cursor[current_group] = current_line
      end
    end
  end

  local lines = {}
  header_lines = {}

  local config = core_ref.config
  local show_bookmarks = config.bookmark_group ~= false
  local show_recent = config.recent_group ~= false

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
  local sort_mode = state_ref.sort_mode or config.sort_mode or "alpha"

  local function sort_filtered(filtered)
    if disable_sorting then
      return
    end

    local function cmp_alpha(a, b)
      return reverse_sorting and a:lower() > b:lower() or a:lower() < b:lower()
    end

    local function cmp_recent(a, b)
      local idx_a = vim.fn.index(state_ref.history or {}, a) or -1
      local idx_b = vim.fn.index(state_ref.history or {}, b) or -1
      return reverse_sorting and idx_a < idx_b or idx_a > idx_b
    end

    local function cmp_usage(a, b)
      local count_a = (state_ref.usage or {})[a] or 0
      local count_b = (state_ref.usage or {})[b] or 0
      return reverse_sorting and count_a < count_b or count_a > count_b
    end

    if sort_mode == "alpha" then
      table.sort(filtered, cmp_alpha)
    elseif sort_mode == "recent" then
      table.sort(filtered, cmp_recent)
    elseif sort_mode == "usage" then
      table.sort(filtered, cmp_usage)
    end

    local custom_sorts = config.custom_sorts or {}
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

  if show_bookmarks then
    local bookmark_filtered = {}
    for _, t in ipairs(state_ref.bookmarks or {}) do
      if search_query == "" or t:lower():find(search_query:lower(), 1, true) then
        table.insert(bookmark_filtered, t)
      end
    end

    if #bookmark_filtered > 0 then
      local group = "__bookmarks"
      local bookmark_icon = collapsed[group] and ICON_GROUP_COL or ICON_GROUP_EXP
      table.insert(lines, bookmark_icon .. " Bookmarks (" .. #state_ref.bookmarks .. ")")
      table.insert(header_lines, #lines)
      if not collapsed[group] then
        local visible_count = math.max(1, math.floor(#bookmark_filtered))
        for i = 1, visible_count do
          local t = bookmark_filtered[i]
          local display = config.theme_aliases[t] or t
          local warning = themes.is_available(t) and "" or WANR_ICON
          local b = " "
          local s = (state_ref.current == t) and ICON_CURRENT_ON or ICON_CURRENT_OFF
          table.insert(lines, "  " .. warning .. b .. s .. display)
        end
      end
    end
  end

  if show_recent then
    local recent_filtered = {}
    for _, t in ipairs(state_ref.history or {}) do
      if search_query == "" or t:lower():find(search_query:lower(), 1, true) then
        table.insert(recent_filtered, t)
      end
    end

    if #recent_filtered > 0 then
      local group = "__recent"
      local recent_icon = collapsed[group] and ICON_GROUP_COL or ICON_GROUP_EXP
      table.insert(lines, recent_icon .. " Recent (" .. #state_ref.history .. ")")
      table.insert(header_lines, #lines)
      if not collapsed[group] then
        local visible_count = math.max(1, math.floor(#recent_filtered))
        for i = 1, visible_count do
          local t = recent_filtered[i]
          local display = config.theme_aliases[t] or t
          local warning = themes.is_available(t) and "" or WANR_ICON
          local b = bookmarks[t] and ICON_BOOKMARK or " "
          local s = (state_ref.current == t) and ICON_CURRENT_ON or ICON_CURRENT_OFF
          table.insert(lines, "  " .. warning .. b .. s .. display)
        end
      end
    end
  end

  if not is_display_grouped then
    local flat_candidates = display_map
    local flat_filtered = search_query == "" and flat_candidates
      or vim.fn.matchfuzzy(flat_candidates, search_query, { text = true })
    sort_filtered(flat_filtered)
    for _, t in ipairs(flat_filtered) do
      local display = config.theme_aliases[t] or t
      local warning = themes.is_available(t) and "" or WANR_ICON
      local b = bookmarks[t] and ICON_BOOKMARK or " "
      local s = (state_ref.current == t) and ICON_CURRENT_ON or ICON_CURRENT_OFF
      table.insert(lines, string.format("%s%s %s %s", warning, b, s, display))
    end
  else
    for group, items in pairs(display_map) do
      local filtered_items = search_query == "" and items or vim.fn.matchfuzzy(items, search_query, { text = true })
      sort_filtered(filtered_items)

      if #filtered_items > 0 then
        local header_icon = collapsed[group] and ICON_GROUP_COL or ICON_GROUP_EXP
        local summary = string.format("(%d)", #items)
        table.insert(lines, string.format("%s %s %s", header_icon, group, summary))
        table.insert(header_lines, #lines)

        if not collapsed[group] then
          local visible_count = math.max(1, math.floor(#filtered_items))
          for i = 1, visible_count do
            local t = filtered_items[i]
            local display = config.theme_aliases[t] or t
            local warning = themes.is_available(t) and "" or WANR_ICON
            local b = bookmarks[t] and ICON_BOOKMARK or " "
            local s = (state_ref.current == t) and ICON_CURRENT_ON or ICON_CURRENT_OFF
            table.insert(lines, string.format("  %s%s %s %s", warning, b, s, display))
          end
        end
      end
    end
  end

  if #lines == 0 then
    table.insert(lines, "  No themes found")
  end

  pcall(vim.api.nvim_set_option_value, "modifiable", true, { buf = picker_buf })
  pcall(vim.api.nvim_buf_set_lines, picker_buf, 0, -1, false, lines)
  pcall(vim.api.nvim_set_option_value, "modifiable", false, { buf = picker_buf })

  if picker_win and vim.api.nvim_win_is_valid(picker_win) and #lines > 0 then
    local restore_line = 1
    if current_group and last_cursor[current_group] then
      restore_line = math.max(1, math.min(last_cursor[current_group], #lines))
    end
    pcall(vim.api.nvim_win_set_cursor, picker_win, { restore_line, 0 })
  end
end

local render_debounced = debounce(RENDER_DEBOUNCE_MS, function(opts)
  vim.schedule(function()
    pcall(render_internal, opts)
  end)
end)

local function render(opts)
  render_debounced(opts)
end

local function toggle_group(group)
  if not group then
    log("WARN", "toggle_group called with nil group")
    return
  end

  collapsed[group] = not collapsed[group]

  local target_state = collapsed[group]
  log("DEBUG", string.format("Toggling group %s to %s", group, target_state and "collapsed" or "expanded"))

  render()
end

local function load_theme(theme, set_name)
  if not theme or not themes.is_available(theme) then
    return
  end

  vim.cmd("hi clear")
  if vim.fn.exists("syntax_on") then
    vim.cmd("syntax reset")
  end
  pcall(vim.api.nvim_set_var, "colors_name", nil)

  local lua_path = vim.api.nvim_get_runtime_file("colors/" .. theme .. ".lua", false)[1]
  local vim_path = vim.api.nvim_get_runtime_file("colors/" .. theme .. ".vim", false)[1]
  local path = lua_path or vim_path

  if path then
    if lua_path then
      dofile(path)
    else
      vim.cmd("source " .. vim.fn.fnameescape(path))
    end
  else
    vim.cmd.colorscheme(theme)
  end

  vim.cmd("syntax on")
  vim.cmd("doautocmd ColorScheme")
  vim.cmd("redraw!")

  if set_name then
    pcall(vim.api.nvim_set_var, "colors_name", theme)
  else
    pcall(vim.api.nvim_set_var, "colors_name", nil)
  end
end

local function close_picker(revert)
  log("DEBUG", "Closing picker", { revert = revert })

  if revert and state_ref and state_ref.previous and themes.is_available(state_ref.previous) then
    local ok, err = pcall(load_theme, state_ref.previous, true)
    if not ok then
      log("ERROR", "Failed to revert theme", err)
    end
  end

  cleanup_timers()

  for _, win in ipairs({ picker_win, palette_win, search_win, code_win }) do
    if win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end

  picker_buf, picker_win, palette_buf, palette_win, search_buf, search_win, code_buf, code_win =
    nil, nil, nil, nil, nil, nil, nil, nil

  ---@diagnostic disable-next-line: unused-local
  search_query, previewed, picker_opts = "", nil, {}
  search_query, picker_opts = "", {}

  log("DEBUG", "Picker closed successfully")
end

local function do_preview(theme)
  if not theme or not themes.is_available(theme) then
    return
  end
  ---@diagnostic disable-next-line: unused-local
  previewed = theme

  local ok, err = pcall(load_theme, theme, false)
  if not ok then
    log("ERROR", "Failed to preview theme", { theme = theme, error = err })
    return
  end

  palette_hl_cache = {}

  ok, err = pcall(M.update_palette, theme)
  if not ok then
    log("ERROR", "Failed to update palette", { theme = theme, error = err })
  end
end

local preview = debounce(100, do_preview)

local function open_search()
  if not picker_win or not vim.api.nvim_win_is_valid(picker_win) then
    return
  end
  if search_win and vim.api.nvim_win_is_valid(search_win) then
    pcall(vim.api.nvim_set_current_win, search_win)
    return
  end

  search_buf = vim.api.nvim_create_buf(false, true)
  local s_row = picker_row + picker_h - 1
  search_win = vim.api.nvim_open_win(search_buf, true, {
    relative = "editor",
    width = picker_w,
    height = 1,
    row = s_row,
    col = picker_col,
    style = "minimal",
    border = "rounded",
  })
  pcall(vim.api.nvim_set_option_value, "buftype", "prompt", { buf = search_buf })
  vim.fn.prompt_setprompt(search_buf, ICON_SEARCH .. " ")
  pcall(vim.api.nvim_set_current_win, search_win)
  vim.cmd("startinsert")

  local ns = vim.api.nvim_create_namespace("raphael_search_match")

  autocmds.search_textchange_autocmd(search_buf, {
    trim = trim,
    ICON_SEARCH = ICON_SEARCH,
    render = render,
    get_picker_buf = function()
      return picker_buf
    end,
    get_picker_opts = function()
      return picker_opts
    end,
    ns = ns,
    set_search_query = function(val)
      search_query = val
    end,
  })

  local function restore_cursor_after_search()
    if
      not picker_buf
      or not vim.api.nvim_buf_is_valid(picker_buf)
      or not picker_win
      or not vim.api.nvim_win_is_valid(picker_win)
    then
      return
    end
    local lines = vim.api.nvim_buf_get_lines(picker_buf, 0, -1, false)
    for i, line in ipairs(lines) do
      if not line:match("^" .. ICON_GROUP_EXP) and not line:match("^" .. ICON_GROUP_COL) then
        pcall(vim.api.nvim_win_set_cursor, picker_win, { i, 0 })
        highlight_current_line()
        break
      end
    end
  end

  map("i", "<Esc>", function()
    search_query = ""
    render(picker_opts)
    if search_win and vim.api.nvim_win_is_valid(search_win) then
      pcall(vim.api.nvim_win_close, search_win, true)
    end
    search_buf, search_win = nil, nil
    vim.cmd("stopinsert")
    if picker_win and vim.api.nvim_win_is_valid(picker_win) then
      pcall(vim.api.nvim_set_current_win, picker_win)
      restore_cursor_after_search()
    end
  end, { buffer = search_buf })

  map("i", "<CR>", function()
    if search_win and vim.api.nvim_win_is_valid(search_win) then
      pcall(vim.api.nvim_win_close, search_win, true)
    end
    search_buf, search_win = nil, nil
    vim.cmd("stopinsert")
    if picker_win and vim.api.nvim_win_is_valid(picker_win) then
      pcall(vim.api.nvim_set_current_win, picker_win)
    end
    render(picker_opts)
  end, { buffer = search_buf })
end

local function update_preview(opts)
  -- luacheck: ignore opts
  opts = opts or {}
  if not is_preview_visible then
    return
  end

  local update_ok, err = pcall(function()
    local ok, line = pcall(vim.api.nvim_get_current_line)
    if not ok or not line or line == "" then
      log("WARN", "No line under cursor for preview")
      return
    end

    local hdr = parse_line_header(line)
    local theme = parse_line_theme(line)
    if not theme then
      if not hdr then
        log("WARN", "No theme found for update_preview")
        return
      end
    end

    local lang_info = samples.get_language_info(current_lang)
    local sample_code = samples.get_sample(current_lang)

    if not sample_code then
      ---@diagnostic disable-next-line: param-type-mismatch
      vim.api.nvim_buf_set_lines(code_buf, 0, -1, false, {
        "Sample unavailable - fallback to basic text.",
      })
      return
    end

    local lines = vim.split(sample_code, "\n")
    local header = string.format("[%s] - [%s]", lang_info.display, theme)

    ---@diagnostic disable-next-line: param-type-mismatch
    vim.api.nvim_buf_set_lines(code_buf, 0, -1, false, vim.list_extend({ header, "" }, lines))
    vim.api.nvim_set_option_value("filetype", lang_info.ft, { buf = code_buf })

    vim.cmd(string.format("silent! syntax on | syntax enable | setlocal syntax=%s", lang_info.ft))
  end)

  if not update_ok then
    log("ERROR", "Failed to update preview", err)
    ---@diagnostic disable-next-line: param-type-mismatch
    vim.api.nvim_buf_set_lines(code_buf, 0, -1, false, { "Error loading sample." })
  end
end

local function open_preview()
  if is_preview_visible then
    return
  end

  local ok, err = pcall(function()
    local code_col = picker_col + picker_w + 2
    local code_width = math.floor(picker_w * core_ref.config.sample_preview.relative_size) * 2
    local code_height = picker_h

    ---@diagnostic disable-next-line: param-type-mismatch
    code_win = vim.api.nvim_open_win(code_buf, false, {
      relative = "editor",
      width = code_width,
      height = code_height,
      row = picker_row,
      col = code_col,
      style = "minimal",
      border = "rounded",
      zindex = 50,
    })

    vim.api.nvim_set_current_win(picker_win)

    is_preview_visible = true
    update_preview()
  end)

  if not ok then
    log("ERROR", "Failed to open preview", err)
  end
end

local function get_next_lang(current, langs)
  for i, l in ipairs(langs) do
    if l == current then
      return langs[(i % #langs) + 1]
    end
  end
  return langs[1] or "lua"
end

local function get_prev_lang(current, langs)
  for i, l in ipairs(langs) do
    if l == current then
      return langs[((i - 2) % #langs) + 1]
    end
  end
  return langs[#langs] or "lua"
end

local function toggle_and_iterate_preview(allowed_langs)
  if not is_preview_visible then
    open_preview()
  else
    current_lang = get_next_lang(current_lang, allowed_langs)
    update_preview()
  end
end

local function iterate_backward_preview(allowed_langs)
  if not is_preview_visible then
    return
  end
  current_lang = get_prev_lang(current_lang, allowed_langs)
  update_preview()
end

function M.get_current_theme()
  if not picker_win or not vim.api.nvim_win_is_valid(picker_win) then
    return nil
  end
  local line = vim.api.nvim_get_current_line()
  return parse_line_theme(line)
end

function M.open(core, opts)
  opts = opts or {}

  local picker_type = opts.exclude_configured and "other" or "configured"

  if picker_instances[picker_type] then
    log("DEBUG", "Picker already open, ignoring", { type = picker_type })
    return
  end

  picker_instances[picker_type] = true
  log("DEBUG", "Picker instance started", { type = picker_type })

  picker_opts = opts
  core_ref = core
  state_ref = core.state

  log("DEBUG", "Opening picker", opts)

  bookmarks = {}
  if state_ref.bookmarks and type(state_ref.bookmarks) == "table" then
    for _, b in ipairs(state_ref.bookmarks) do
      if type(b) == "string" and b ~= "" then
        bookmarks[b] = true
      else
        log("WARN", "Invalid bookmark entry", b)
      end
    end
  end

  collapsed = type(state_ref.collapsed) == "table" and vim.deepcopy(state_ref.collapsed) or {}
  collapsed["__bookmarks"] = collapsed["__bookmarks"] or false
  collapsed["__recent"] = collapsed["__recent"] or false

  if not picker_buf or not vim.api.nvim_buf_is_valid(picker_buf) then
    picker_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = picker_buf })
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = picker_buf })
    vim.api.nvim_set_option_value("filetype", "raphael_picker", { buf = picker_buf })
  end

  picker_h = math.max(6, math.floor(vim.o.lines * 0.7))
  picker_w = math.floor(vim.o.columns * 0.35)
  picker_row = math.floor((vim.o.lines - picker_h) / 2)
  picker_col = math.floor(((vim.o.columns - picker_w) / 2) - (picker_w / 2))

  local base_title = opts.exclude_configured and "Raphael - Other Themes" or "Raphael - Configured Themes"

  local display_sort = disable_sorting and "off" or (state_ref.sort_mode or core_ref.config.sort_mode or "alpha")
  local title_suffix = display_sort .. (reverse_sorting and " revserse " or "")
  local title = base_title .. " (Sort: " .. title_suffix .. ")"

  picker_win = vim.api.nvim_open_win(picker_buf, true, {
    relative = "editor",
    width = picker_w,
    height = picker_h,
    row = picker_row,
    col = picker_col,
    style = "minimal",
    border = "rounded",
    title = title,
  })

  state_ref.previous = state_ref.current or vim.g.colors_name or state_ref.saved
  log("DEBUG", "Previous theme saved", state_ref.previous)

  map("n", "q", function()
    if code_win and vim.api.nvim_win_is_valid(code_win) then
      pcall(vim.api.nvim_win_close, code_win, true)
    end
    picker_instances[picker_type] = false
    log("DEBUG", "Picker instance ended", { type = picker_type })
    close_picker(true)
  end, { buffer = picker_buf, desc = "Quit and revert" })

  map("n", "<Esc>", function()
    if code_win and vim.api.nvim_win_is_valid(code_win) then
      pcall(vim.api.nvim_win_close, code_win, true)
    end
    picker_instances[picker_type] = false
    log("DEBUG", "Picker instance ended", { type = picker_type })
    close_picker(true)
  end, { buffer = picker_buf, desc = "Quit and revert" })

  map("n", "<CR>", function()
    local line = vim.api.nvim_get_current_line()
    local hdr = parse_line_header(line)
    if hdr then
      vim.notify("Cannot select a group header", vim.log.levels.WARN)
      return
    end
    local theme = parse_line_theme(line)
    if not theme then
      vim.notify("No theme on this line", vim.log.levels.WARN)
      return
    end
    if not themes.is_available(theme) then
      vim.notify("Theme not installed: " .. theme, vim.log.levels.ERROR)
      log("ERROR", "Attempted to select unavailable theme", theme)
      return
    end

    log("DEBUG", "Applying theme", theme)
    if core_ref and core_ref.apply then
      local apply_ok, err = pcall(core_ref.apply, theme, true)
      if not apply_ok then
        log("ERROR", "Failed to apply theme", { theme = theme, error = err })
        vim.notify("Failed to apply theme: " .. theme, vim.log.levels.ERROR)
        return
      end
    end

    if code_win and vim.api.nvim_win_is_valid(code_win) then
      pcall(vim.api.nvim_win_close, code_win, true)
    end

    state_ref.current = theme
    state_ref.saved = theme
    state_ref.previous = vim.g.colors_name or state_ref.previous
    local state_mod = require("raphael.state")
    pcall(state_mod.save, state_ref, core_ref.config)

    picker_instances[picker_type] = false
    log("DEBUG", "Picker instance ended", { type = picker_type })
    close_picker(false)
  end, { buffer = picker_buf, desc = "Select theme" })

  map("n", "j", function()
    local line_count = #vim.api.nvim_buf_get_lines(picker_buf, 0, -1, false)
    local cur = vim.api.nvim_win_get_cursor(picker_win)[1]
    local next_line = cur >= line_count and 1 or cur + 1
    vim.api.nvim_win_set_cursor(picker_win, { next_line, 0 })
    highlight_current_line()
  end, { buffer = picker_buf, desc = "Next line (wrap to top)" })

  map("n", "k", function()
    local line_count = #vim.api.nvim_buf_get_lines(picker_buf, 0, -1, false)
    local cur = vim.api.nvim_win_get_cursor(picker_win)[1]
    local prev_line = cur <= 1 and line_count or cur - 1
    vim.api.nvim_win_set_cursor(picker_win, { prev_line, 0 })
    highlight_current_line()
  end, { buffer = picker_buf, desc = "Previous line (wrap to bottom)" })

  map("n", "<C-j>", function()
    if #header_lines == 0 then
      log("DEBUG", "No header lines found")
      return
    end
    local cur = vim.api.nvim_win_get_cursor(picker_win)[1]
    log("DEBUG", "C-j navigation", { current = cur, headers = header_lines })
    for _, ln in ipairs(header_lines) do
      if ln > cur then
        vim.api.nvim_win_set_cursor(picker_win, { ln, 0 })
        highlight_current_line()
        log("DEBUG", "Jumped to header", ln)

        return
      end
    end
    if #header_lines > 0 then
      vim.api.nvim_win_set_cursor(picker_win, { header_lines[1], 0 })
      highlight_current_line()
      log("DEBUG", "Wrapped to first header", header_lines[1])
    end
  end, { buffer = picker_buf, desc = "Next group header" })

  map("n", "<C-k>", function()
    if #header_lines == 0 then
      log("DEBUG", "No header lines found")
      return
    end
    local cur = vim.api.nvim_win_get_cursor(picker_win)[1]
    log("DEBUG", "C-k navigation", { current = cur, headers = header_lines })
    for i = #header_lines, 1, -1 do
      if header_lines[i] < cur then
        vim.api.nvim_win_set_cursor(picker_win, { header_lines[i], 0 })
        highlight_current_line()
        log("DEBUG", "Jumped to header", header_lines[i])
        return
      end
    end
    if #header_lines > 0 then
      vim.api.nvim_win_set_cursor(picker_win, { header_lines[#header_lines], 0 })
      highlight_current_line()
      log("DEBUG", "Wrapped to last header", header_lines[#header_lines])
    end
  end, { buffer = picker_buf, desc = "Previous group header" })

  map("n", "gg", function()
    vim.api.nvim_win_set_cursor(picker_win, { 1, 0 })
    highlight_current_line()
  end, { buffer = picker_buf, desc = "Go to top" })

  map("n", "G", function()
    local line_count = #vim.api.nvim_buf_get_lines(picker_buf, 0, -1, false)
    vim.api.nvim_win_set_cursor(picker_win, { line_count, 0 })
    highlight_current_line()
  end, { buffer = picker_buf, desc = "Go to bottom" })

  map("n", "<C-u>", function()
    local height = vim.api.nvim_win_get_height(picker_win)
    local cur = vim.api.nvim_win_get_cursor(picker_win)[1]
    local target = math.max(1, cur - math.floor(height / 2))
    vim.api.nvim_win_set_cursor(picker_win, { target, 0 })
    highlight_current_line()
  end, { buffer = picker_buf, desc = "Page up (half-window)" })

  map("n", "<C-d>", function()
    local height = vim.api.nvim_win_get_height(picker_win)
    local line_count = #vim.api.nvim_buf_get_lines(picker_buf, 0, -1, false)
    local cur = vim.api.nvim_win_get_cursor(picker_win)[1]
    local target = math.min(line_count, cur + math.floor(height / 2))
    vim.api.nvim_win_set_cursor(picker_win, { target, 0 })
    highlight_current_line()
  end, { buffer = picker_buf, desc = "Page down (half-window)" })

  map("n", "zt", function()
    local cur = vim.api.nvim_win_get_cursor(picker_win)[1]
    vim.api.nvim_win_set_cursor(picker_win, { cur, 0 })
    vim.cmd("normal! zt")
    highlight_current_line()
  end, { buffer = picker_buf, desc = "Scroll line to top" })

  map("n", "zz", function()
    local cur = vim.api.nvim_win_get_cursor(picker_win)[1]
    vim.api.nvim_win_set_cursor(picker_win, { cur, 0 })
    vim.cmd("normal! zz")
    highlight_current_line()
  end, { buffer = picker_buf, desc = "Scroll line to center" })

  map("n", "zb", function()
    local cur = vim.api.nvim_win_get_cursor(picker_win)[1]
    vim.api.nvim_win_set_cursor(picker_win, { cur, 0 })
    vim.cmd("normal! zb")
    highlight_current_line()
  end, { buffer = picker_buf, desc = "Scroll line to bottom" })

  map("n", "gb", function()
    for _, ln in ipairs(header_lines) do
      local line = vim.api.nvim_buf_get_lines(picker_buf, ln - 1, ln, false)[1]
      if line:find("Bookmarks") then
        vim.api.nvim_win_set_cursor(picker_win, { ln, 0 })
        highlight_current_line()
        return
      end
    end
    vim.notify("Bookmarks section not found", vim.log.levels.WARN)
  end, { buffer = picker_buf, desc = "Jump to Bookmarks" })

  map("n", "gr", function()
    for _, ln in ipairs(header_lines) do
      local line = vim.api.nvim_buf_get_lines(picker_buf, ln - 1, ln, false)[1]
      if line:find("Recent") then
        vim.api.nvim_win_set_cursor(picker_win, { ln, 0 })
        highlight_current_line()
        return
      end
    end
    vim.notify("Recent section not found", vim.log.levels.WARN)
  end, { buffer = picker_buf, desc = "Jump to Recent" })

  map("n", "ga", function()
    vim.api.nvim_win_set_cursor(picker_win, { 1, 0 })
    highlight_current_line()
  end, { buffer = picker_buf, desc = "Jump to first theme (All)" })

  map("n", "<C-l>", function()
    render(opts)
    highlight_current_line()
    vim.notify("Picker refreshed", vim.log.levels.INFO)
  end, { buffer = picker_buf, desc = "Refresh picker" })

  map("n", "c", function()
    local line = vim.api.nvim_get_current_line()
    local hdr = parse_line_header(line)
    if not hdr then
      local lines = vim.api.nvim_buf_get_lines(picker_buf, 0, -1, false)
      local current_idx = vim.api.nvim_win_get_cursor(picker_win)[1]
      for i = current_idx, 1, -1 do
        local possible_hdr = parse_line_header(lines[i])
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
      state_ref.collapsed = vim.deepcopy(collapsed)
      if core_ref and core_ref.save_state then
        pcall(core_ref.save_state)
      end
    else
      vim.notify("No group detected for current line", vim.log.levels.WARN)
    end
  end, { buffer = picker_buf, desc = "Collapse/expand group" })

  map("n", "s", function()
    local sort_modes = { "alpha", "recent", "usage" }
    local idx = vim.fn.index(sort_modes, state_ref.sort_mode or "alpha") + 1
    state_ref.sort_mode = sort_modes[(idx % #sort_modes) + 1]
    if core_ref and core_ref.save_state then
      pcall(core_ref.save_state)
    end
    -- luacheck: ignore display_sort title_suffix
    ---@diagnostic disable-next-line: redefined-local
    local display_sort = disable_sorting and "off" or (state_ref.sort_mode or core_ref.config.sort_mode or "alpha")
    ---@diagnostic disable-next-line: redefined-local
    local title_suffix = display_sort .. (reverse_sorting and " reverse " or "")
    local new_title = base_title .. " (Sort: " .. title_suffix .. ")"
    vim.api.nvim_win_set_config(picker_win, { title = new_title })
    log("DEBUG", "Sort mode changed", state_ref.sort_mode)
    render(opts)
  end, { buffer = picker_buf, desc = "Cycle sort mode" })

  map("n", "S", function()
    disable_sorting = not disable_sorting
    if core_ref and core_ref.save_state then
      pcall(core_ref.save_state)
    end
    -- luacheck: ignore display_sort title_suffix
    ---@diagnostic disable-next-line: redefined-local
    local display_sort = disable_sorting and "off" or (state_ref.sort_mode or core_ref.config.sort_mode or "alpha")
    ---@diagnostic disable-next-line: redefined-local
    local title_suffix = display_sort .. (reverse_sorting and " revserse " or "")
    vim.api.nvim_win_set_config(picker_win, { title = base_title .. " (Sort: " .. title_suffix .. ")" })
    vim.notify(string.format("[Raphael] Sorting: %s", disable_sorting and "DISABLED" or "ENABLED"))
    log("DEBUG", "Sorting toggled", disable_sorting)
    render(opts)
  end, { buffer = picker_buf, desc = "Toggle sorting on/off" })

  map("n", "R", function()
    reverse_sorting = not reverse_sorting
    if core_ref and core_ref.save_state then
      -- luacheck: ignore display_sort title_suffix
      pcall(core_ref.save_state)
    end
    ---@diagnostic disable-next-line: redefined-local
    local display_sort = disable_sorting and "off" or (state_ref.sort_mode or core_ref.config.sort_mode or "alpha")
    ---@diagnostic disable-next-line: redefined-local
    local title_suffix = display_sort .. (reverse_sorting and " revserse " or "")
    vim.api.nvim_win_set_config(picker_win, { title = base_title .. " (Sort: " .. title_suffix .. ")" })
    vim.notify(string.format("[Raphael] Reverse sort: %s", reverse_sorting and "ON" or "OFF"))
    log("DEBUG", "Reverse sorting toggled", reverse_sorting)
    render(opts)
  end, { buffer = picker_buf, desc = "Toggle reverse sorting" })

  map("n", "/", open_search, { buffer = picker_buf, desc = "Search themes" })

  map("n", "b", function()
    local line = vim.api.nvim_get_current_line()
    local theme = parse_line_theme(line)
    if theme then
      core_ref.toggle_bookmark(theme)
      bookmarks = {}
      if state_ref.bookmarks and type(state_ref.bookmarks) == "table" then
        for _, b in ipairs(state_ref.bookmarks) do
          if type(b) == "string" and b ~= "" then
            bookmarks[b] = true
          end
        end
      end
      render(opts)
      log("DEBUG", "Bookmark toggled", theme)
    end
  end, { buffer = picker_buf, desc = "Toggle bookmark" })

  map("n", "u", function()
    local theme = history.undo(function(t)
      if core_ref and core_ref.apply then
        pcall(core_ref.apply, t, false)
      end
    end)
    if theme then
      pcall(M.update_palette, theme)
      render(opts)
      highlight_current_line()
    end
  end, { buffer = picker_buf, desc = "Undo theme change" })

  map("n", "<C-r>", function()
    local theme = history.redo(function(t)
      if core_ref and core_ref.apply then
        pcall(core_ref.apply, t, false)
      end
    end)
    if theme then
      pcall(M.update_palette, theme)
      render(opts)
      highlight_current_line()
    end
  end, { buffer = picker_buf, desc = "Redo theme change" })

  map("n", "]b", function()
    if not next(bookmarks) then
      return
    end
    local lines = vim.api.nvim_buf_get_lines(picker_buf, 0, -1, false)
    local cur = vim.api.nvim_win_get_cursor(picker_win)[1]
    local skip_start, skip_end = 0, 0
    if core_ref.config.bookmark_group ~= false then
      for _, ln in ipairs(header_lines) do
        if (lines[ln] or ""):find("Bookmarks") then
          skip_start = ln
          for _, next_ln in ipairs(header_lines) do
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
      local theme = parse_line_theme(lines[i])
      if theme and bookmarks[theme] then
        vim.api.nvim_win_set_cursor(picker_win, { i, 0 })
        highlight_current_line()
        return
      end
    end
    for i = 1, cur - 1 do
      if is_in_skip(i) then
        goto continue
      end
      local theme = parse_line_theme(lines[i])
      if theme and bookmarks[theme] then
        vim.api.nvim_win_set_cursor(picker_win, { i, 0 })
        highlight_current_line()
        return
      end
      ::continue::
    end
  end, { buffer = picker_buf, desc = "Next bookmark (skip group)" })

  map("n", "[b", function()
    if not next(bookmarks) then
      return
    end
    local lines = vim.api.nvim_buf_get_lines(picker_buf, 0, -1, false)
    local cur = vim.api.nvim_win_get_cursor(picker_win)[1]
    local skip_start, skip_end = 0, 0
    if core_ref.config.bookmark_group ~= false then
      for _, ln in ipairs(header_lines) do
        if (lines[ln] or ""):find("Bookmarks") then
          skip_start = ln
          for _, next_ln in ipairs(header_lines) do
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
      local theme = parse_line_theme(lines[i])
      if theme and bookmarks[theme] then
        vim.api.nvim_win_set_cursor(picker_win, { i, 0 })
        highlight_current_line()
        return
      end
    end
    for i = #lines, cur + 1, -1 do
      if is_in_skip(i) then
        goto continue
      end
      local theme = parse_line_theme(lines[i])
      if theme and bookmarks[theme] then
        vim.api.nvim_win_set_cursor(picker_win, { i, 0 })
        highlight_current_line()
        return
      end
      ::continue::
    end
  end, { buffer = picker_buf, desc = "Prev bookmark (skip group)" })

  map("n", "]r", function()
    if not (state_ref.history and #state_ref.history > 0) then
      return
    end
    local lines = vim.api.nvim_buf_get_lines(picker_buf, 0, -1, false)
    local cur = vim.api.nvim_win_get_cursor(picker_win)[1]
    local skip_start, skip_end = 0, 0
    if core_ref.config.recent_group ~= false then
      for _, ln in ipairs(header_lines) do
        if (lines[ln] or ""):find("Recent") then
          skip_start = ln
          for _, next_ln in ipairs(header_lines) do
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
      local theme = parse_line_theme(lines[i])
      if theme and vim.tbl_contains(state_ref.history, theme) then
        vim.api.nvim_win_set_cursor(picker_win, { i, 0 })
        highlight_current_line()
        return
      end
    end
    for i = 1, cur - 1 do
      if is_in_skip(i) then
        goto continue
      end
      local theme = parse_line_theme(lines[i])
      if theme and vim.tbl_contains(state_ref.history, theme) then
        vim.api.nvim_win_set_cursor(picker_win, { i, 0 })
        highlight_current_line()
        return
      end
      ::continue::
    end
  end, { buffer = picker_buf, desc = "Next recent (skip group)" })

  map("n", "[r", function()
    if not (state_ref.history and #state_ref.history > 0) then
      return
    end
    local lines = vim.api.nvim_buf_get_lines(picker_buf, 0, -1, false)
    local cur = vim.api.nvim_win_get_cursor(picker_win)[1]
    local skip_start, skip_end = 0, 0
    if core_ref.config.recent_group ~= false then
      for _, ln in ipairs(header_lines) do
        if (lines[ln] or ""):find("Recent") then
          skip_start = ln
          for _, next_ln in ipairs(header_lines) do
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
      local theme = parse_line_theme(lines[i])
      if theme and vim.tbl_contains(state_ref.history, theme) then
        vim.api.nvim_win_set_cursor(picker_win, { i, 0 })
        highlight_current_line()
        return
      end
    end
    for i = #lines, cur + 1, -1 do
      if is_in_skip(i) then
        goto continue
      end
      local theme = parse_line_theme(lines[i])
      if theme and vim.tbl_contains(state_ref.history, theme) then
        vim.api.nvim_win_set_cursor(picker_win, { i, 0 })
        highlight_current_line()
        return
      end
      ::continue::
    end
  end, { buffer = picker_buf, desc = "Prev recent (skip group)" })

  map("n", "]g", function()
    local cur = vim.api.nvim_win_get_cursor(picker_win)[1]
    for _, ln in ipairs(header_lines) do
      if ln > cur then
        vim.api.nvim_win_set_cursor(picker_win, { ln, 0 })
        highlight_current_line()
        return
      end
    end
    if #header_lines > 0 then
      vim.api.nvim_win_set_cursor(picker_win, { header_lines[1], 0 })
      highlight_current_line()
    end
  end, { buffer = picker_buf, desc = "Next group" })

  map("n", "[g", function()
    local cur = vim.api.nvim_win_get_cursor(picker_win)[1]
    for i = #header_lines, 1, -1 do
      if header_lines[i] < cur then
        vim.api.nvim_win_set_cursor(picker_win, { header_lines[i], 0 })
        highlight_current_line()
        return
      end
    end
    if #header_lines > 0 then
      vim.api.nvim_win_set_cursor(picker_win, { header_lines[#header_lines], 0 })
      highlight_current_line()
    end
  end, { buffer = picker_buf, desc = "Previous group" })

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
      if core_ref and core_ref.apply then
        local ok, err = pcall(core_ref.apply, random_theme, true)
        if ok then
          pcall(M.update_palette, random_theme)
          render(opts)
          highlight_current_line()
          vim.notify("  Random: " .. random_theme, vim.log.levels.INFO)
        else
          log("ERROR", "Failed to apply random theme", { theme = random_theme, error = err })
        end
      end
    else
      vim.notify("Random theme not available", vim.log.levels.WARN)
    end
  end, { buffer = picker_buf, desc = "Apply random theme" })

  map("n", "H", function()
    history.show()
  end, { buffer = picker_buf, desc = "Show theme history" })

  map("n", "J", function()
    vim.ui.input({
      prompt = string.format("Jump to position (1-%d): ", #history.stack),
      default = tostring(history.index),
    }, function(input)
      if not input then
        return
      end

      local pos = tonumber(input)
      if pos then
        local theme = history.jump(pos, function(t)
          if core_ref and core_ref.apply then
            pcall(core_ref.apply, t, false)
          end
        end)
        if theme then
          pcall(M.update_palette, theme)
          render(opts)
          highlight_current_line()
        end
      else
        vim.notify("Invalid position", vim.log.levels.ERROR)
      end
    end)
  end, { buffer = picker_buf, desc = "Jump to history position" })

  map("n", "T", function()
    local stats = history.stats()

    if stats.total == 0 then
      vim.notify("No history data", vim.log.levels.INFO)
      return
    end

    local lines = {
      ICON_STATS .. "Theme History:",
      "",
      string.format("Position: %d/%d", stats.position, stats.total),
      string.format("Unique: %d themes", stats.unique_themes),
      string.format("Most used: %s (%dx)", stats.most_used, stats.most_used_count),
    }

    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
  end, { buffer = picker_buf, desc = "Show quick stats" })

  map("n", "?", function()
    vim.notify(table.concat(help, "\n"), vim.log.levels.INFO)
  end, { buffer = picker_buf, desc = "Show help" })

  if core_ref.config.sample_preview.enabled then
    if not code_buf or not vim.api.nvim_buf_is_valid(code_buf) then
      code_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = code_buf })
      vim.api.nvim_set_option_value("buftype", "nofile", { buf = code_buf })
      vim.api.nvim_set_option_value("swapfile", false, { buf = code_buf })
    end

    local allowed_langs = core_ref.config.sample_preview.languages
      or vim.tbl_map(function(lang)
        return lang.name
      end, samples.languages)

    current_lang = allowed_langs[1] or "lua"

    vim.api.nvim_buf_set_keymap(picker_buf, "n", "i", "", {
      callback = function()
        toggle_and_iterate_preview(allowed_langs)
      end,
      silent = true,
      noremap = true,
    })

    vim.api.nvim_buf_set_keymap(picker_buf, "n", "I", "", {
      callback = function()
        iterate_backward_preview(allowed_langs)
      end,
      silent = true,
      noremap = true,
    })
  end

  autocmds.picker_cursor_autocmd(picker_buf, {
    parse = parse_line_theme,
    preview = preview,
    highlight = highlight_current_line,
    update_preview = update_preview,
  })

  autocmds.picker_bufdelete_autocmd(picker_buf, {
    log = log,
    cleanup = cleanup_timers,
  })

  render(opts)
  highlight_current_line()

  if state_ref.current then
    M.update_palette(state_ref.current)
  end

  log("DEBUG", "Picker opened successfully")
end

return M
