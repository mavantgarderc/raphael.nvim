local themes = require("raphael.themes")
local M = {}

local picker_buf, picker_win
local palette_buf, palette_win
local search_buf, search_win

local picker_w, picker_h, picker_row, picker_col

local core_ref, state_ref
local previewed
local collapsed = {}
local bookmarks = {}
local search_query = ""
local picker_opts = {}
local header_lines = {}
local last_cursor = {}
local active_timers = {}
local RENDER_DEBOUNCE_MS = 50
local ANIM_STEPS = 5
local ANIM_INTERVAL = 15
local ENABLE_ANIMATIONS = true
local DEBUG_MODE = false

local ICON_BOOKMARK = "  "
local ICON_CURRENT_ON = "  "
local ICON_CURRENT_OFF = "  "
local ICON_GROUP_EXP = "  "
local ICON_GROUP_COL = "  "
local BLOCK_CHAR = " 󱡌 "
local ICON_SEARCH = "   "

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

local palette_hl_cache = {}

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
  line = line:gsub("%s* 󰝧 ", "")
  local theme = line:match("([%w_%-]+)%s*$")
  if theme and theme ~= "" then
    return theme
  end
  local last
  for token in line:gmatch("%S+") do
    last = token
  end
  if last then
    last = last:gsub("^[^%w_%-]+", ""):gsub("[^%w_%-]+$", "")
    if last ~= "" then
      return last
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

  for i, hl_name in ipairs(PALETTE_HL) do
    local hl = get_hl_rgb(hl_name)
    if hl then
      local color_int = hl.fg or hl.bg
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
  end

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
  if line_text:match("^" .. ICON_GROUP_EXP) or line_text:match("^" .. ICON_GROUP_COL) then
    return
  end
  pcall(
    vim.highlight.range,
    picker_buf,
    HIGHLIGHT_NS,
    "Visual",
    { start_line = cur_line, start_col = 0 },
    { end_line = cur_line, end_col = -1 },
    { inclusive = false, priority = 100 }
  )
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
  local sort_mode = state_ref.sort_mode or core_ref.config.sort_mode or "alpha"

  local function sort_filtered(filtered)
    if sort_mode == "alpha" then
      table.sort(filtered, function(a, b)
        return a:lower() < b:lower()
      end)
    elseif sort_mode == "recent" then
      table.sort(filtered, function(a, b)
        local idx_a = vim.fn.index(state_ref.history or {}, a) or -1
        local idx_b = vim.fn.index(state_ref.history or {}, b) or -1
        return idx_a > idx_b
      end)
    elseif sort_mode == "usage" then
      table.sort(filtered, function(a, b)
        local count_a = (state_ref.usage or {})[a] or 0
        local count_b = (state_ref.usage or {})[b] or 0
        return count_a > count_b
      end)
    end
    local custom_sorts = core_ref.config.custom_sorts or {}
    local custom_func = custom_sorts[sort_mode]
    if custom_func then
      table.sort(filtered, custom_func)
    end
  end

  state_ref._anim_ratio_group = state_ref._anim_ratio_group or {}

  local bookmark_filtered = {}
  for _, t in ipairs(state_ref.bookmarks or {}) do
    if search_query == "" or t:lower():find(search_query:lower(), 1, true) then
      table.insert(bookmark_filtered, t)
    end
  end
  if #bookmark_filtered > 0 then
    local group = "__bookmarks"
    local ratio = state_ref._anim_ratio_group[group] or 1
    local bookmark_icon = collapsed[group] and ICON_GROUP_COL or ICON_GROUP_EXP
    table.insert(lines, bookmark_icon .. " Bookmarks (" .. #state_ref.bookmarks .. ")")
    table.insert(header_lines, #lines)
    if not collapsed[group] then
      local visible_count = math.max(1, math.floor(#bookmark_filtered * ratio))
      for i = 1, visible_count do
        local t = bookmark_filtered[i]
        local warning = themes.is_available(t) and "" or " 󰝧 "
        local b = " "
        local s = (state_ref.current == t) and ICON_CURRENT_ON or ICON_CURRENT_OFF
        table.insert(lines, "  " .. warning .. b .. s .. t)
      end
    end
  end

  local recent_filtered = {}
  for _, t in ipairs(state_ref.history or {}) do
    if search_query == "" or t:lower():find(search_query:lower(), 1, true) then
      table.insert(recent_filtered, t)
    end
  end
  if #recent_filtered > 0 then
    local group = "__recent"
    local ratio = state_ref._anim_ratio_group[group] or 1
    local recent_icon = collapsed[group] and ICON_GROUP_COL or ICON_GROUP_EXP
    table.insert(lines, recent_icon .. " Recent (" .. #state_ref.history .. ")")
    table.insert(header_lines, #lines)
    if not collapsed[group] then
      local visible_count = math.max(1, math.floor(#recent_filtered * ratio))
      for i = 1, visible_count do
        local t = recent_filtered[i]
        local warning = themes.is_available(t) and "" or " 󰝧 "
        local b = bookmarks[t] and ICON_BOOKMARK or " "
        local s = (state_ref.current == t) and ICON_CURRENT_ON or ICON_CURRENT_OFF
        table.insert(lines, "  " .. warning .. b .. s .. t)
      end
    end
  end

  if not is_display_grouped then
    local flat_candidates = display_map
    local flat_filtered = search_query == "" and flat_candidates
      or vim.fn.matchfuzzy(flat_candidates, search_query, { text = true })
    sort_filtered(flat_filtered)
    for _, t in ipairs(flat_filtered) do
      local warning = themes.is_available(t) and "" or " 󰝧 "
      local b = bookmarks[t] and ICON_BOOKMARK or " "
      local s = (state_ref.current == t) and ICON_CURRENT_ON or ICON_CURRENT_OFF
      table.insert(lines, string.format("%s%s %s %s", warning, b, s, t))
    end
  else
    for group, items in pairs(display_map) do
      local filtered_items = search_query == "" and items or vim.fn.matchfuzzy(items, search_query, { text = true })
      sort_filtered(filtered_items)

      if #filtered_items > 0 then
        local ratio = state_ref._anim_ratio_group[group] or 1
        local header_icon = collapsed[group] and ICON_GROUP_COL or ICON_GROUP_EXP
        local summary = string.format("(%d)", #items)
        table.insert(lines, string.format("%s %s %s", header_icon, group, summary))
        table.insert(header_lines, #lines)

        if not collapsed[group] then
          local visible_count = math.max(1, math.floor(#filtered_items * ratio))
          for i = 1, visible_count do
            local t = filtered_items[i]
            local warning = themes.is_available(t) and "" or " 󰝧 "
            local b = bookmarks[t] and ICON_BOOKMARK or " "
            local s = (state_ref.current == t) and ICON_CURRENT_ON or ICON_CURRENT_OFF
            table.insert(lines, string.format("  %s%s %s %s", warning, b, s, t))
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

local function animate_steps(group_key, fn)
  if active_timers[group_key] then
    local old_timer = active_timers[group_key]
    if old_timer and not old_timer:is_closing() then
      pcall(old_timer.stop, old_timer)
      pcall(old_timer.close, old_timer)
    end
    active_timers[group_key] = nil
  end

  local step = 1
  ---@diagnostic disable-next-line: undefined-field
  local timer = vim.loop.new_timer()
  active_timers[group_key] = timer

  local function cleanup()
    if timer and not timer:is_closing() then
      pcall(timer.stop, timer)
      pcall(timer.close, timer)
    end
    active_timers[group_key] = nil
  end

  timer:start(0, ANIM_INTERVAL, function()
    vim.schedule(function()
      if not picker_win or not vim.api.nvim_win_is_valid(picker_win) then
        cleanup()
        return
      end

      local ok, keep_going = pcall(fn, step)
      if not ok then
        log("ERROR", "Animation step error", keep_going)
        cleanup()
        return
      end

      if not keep_going or step >= ANIM_STEPS then
        cleanup()
      end
      step = step + 1
    end)
  end)
end

local function ease_out_cubic(t)
  return 1 - (1 - t) ^ 3
end

local function toggle_group(group)
  if not group then
    log("WARN", "toggle_group called with nil group")
    return
  end

  collapsed[group] = not collapsed[group]
  state_ref._anim_ratio_group = state_ref._anim_ratio_group or {}

  if not ENABLE_ANIMATIONS or ANIM_STEPS <= 1 then
    state_ref._anim_ratio_group[group] = 1
    render()
    return
  end

  local target_state = collapsed[group]
  log("DEBUG", string.format("Toggling group %s to %s", group, target_state and "collapsed" or "expanded"))

  local step_fn = function(frame)
    local t = frame / ANIM_STEPS
    local eased = ease_out_cubic(t)

    if target_state then
      state_ref._anim_ratio_group[group] = 1 - eased
    else
      state_ref._anim_ratio_group[group] = eased
    end

    render()
    return frame < ANIM_STEPS
  end

  animate_steps("toggle_" .. group, step_fn)
end

local function close_picker(revert)
  log("DEBUG", "Closing picker", { revert = revert })

  cleanup_timers()

  if revert and state_ref and state_ref.previous and themes.is_available(state_ref.previous) then
    local ok, err = pcall(vim.cmd.colorscheme, state_ref.previous)
    if not ok then
      log("ERROR", "Failed to revert colorscheme", err)
    end
    if core_ref and core_ref.apply then
      ok, err = pcall(core_ref.apply, state_ref.previous, true)
      if not ok then
        log("ERROR", "Failed to apply reverted theme", err)
      end
    end
  end

  if picker_win and vim.api.nvim_win_is_valid(picker_win) then
    pcall(vim.api.nvim_win_close, picker_win, true)
  end
  if palette_win and vim.api.nvim_win_is_valid(palette_win) then
    pcall(vim.api.nvim_win_close, palette_win, true)
  end
  if search_win and vim.api.nvim_win_is_valid(search_win) then
    pcall(vim.api.nvim_win_close, search_win, true)
  end

  picker_buf, picker_win, palette_buf, palette_win, search_buf, search_win = nil, nil, nil, nil, nil, nil
  search_query = ""
  previewed = nil
  picker_opts = {}

  log("DEBUG", "Picker closed successfully")
end

local function do_preview(theme)
  if not theme or not themes.is_available(theme) then
    return
  end
  if previewed == theme then
    return
  end
  previewed = theme

  local ok, err = pcall(vim.cmd.colorscheme, theme)
  if not ok then
    log("ERROR", "Failed to preview theme", { theme = theme, error = err })
    return
  end

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

  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    buffer = search_buf,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(search_buf, 0, -1, false)
      search_query = trim(table.concat(lines, "\n"):gsub("^" .. ICON_SEARCH .. " ", ""))
      render(picker_opts)

      if picker_buf and vim.api.nvim_buf_is_valid(picker_buf) then
        pcall(vim.api.nvim_buf_clear_namespace, picker_buf, ns, 0, -1)
        if search_query ~= "" and #search_query >= 2 then
          local picker_lines = vim.api.nvim_buf_get_lines(picker_buf, 0, -1, false)
          local query_lower = search_query:lower()
          for i, line in ipairs(picker_lines) do
            local start_idx = 1
            local match_count = 0
            while match_count < 10 do
              local s, e = line:lower():find(query_lower, start_idx, true)
              if not s then
                break
              end
              pcall(vim.api.nvim_buf_set_extmark, picker_buf, ns, i - 1, s - 1, {
                end_col = e,
                hl_group = "Search",
                strict = false,
              })
              start_idx = e + 1
              match_count = match_count + 1
            end
          end
        end
      end
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

  vim.keymap.set("i", "<Esc>", function()
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

  vim.keymap.set("i", "<CR>", function()
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

function M.toggle_debug()
  DEBUG_MODE = not DEBUG_MODE
  vim.notify(string.format("[Raphael] Debug mode: %s", DEBUG_MODE and "ON" or "OFF"))
end

function M.toggle_animations()
  ENABLE_ANIMATIONS = not ENABLE_ANIMATIONS
  vim.notify(string.format("[Raphael] Animations: %s", ENABLE_ANIMATIONS and "ON" or "OFF"))
end

function M.get_cache_stats()
  local count = 0
  for _ in pairs(palette_hl_cache) do
    count = count + 1
  end
  return {
    palette_cache_size = count,
    active_timers = vim.tbl_count(active_timers),
  }
end

function M.open(core, opts)
  opts = opts or {}
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

  picker_h = math.max(6, math.floor(vim.o.lines * 0.6))
  picker_w = math.floor(vim.o.columns * 0.5)
  picker_row = math.floor((vim.o.lines - picker_h) / 2)
  picker_col = math.floor((vim.o.columns - picker_w) / 2)

  local sort_mode = state_ref.sort_mode or core_ref.config.sort_mode or "alpha"
  local base_title = opts.exclude_configured and "Raphael - Other Themes" or "Raphael - Configured Themes"
  local title = base_title .. " (Sort: " .. sort_mode .. ")"

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

  state_ref.previous = vim.g.colors_name
  log("DEBUG", "Previous theme saved", state_ref.previous)

  vim.keymap.set("n", "j", function()
    local line_count = #vim.api.nvim_buf_get_lines(picker_buf, 0, -1, false)
    local cur = vim.api.nvim_win_get_cursor(picker_win)[1]
    local next_line = cur >= line_count and 1 or cur + 1
    vim.api.nvim_win_set_cursor(picker_win, { next_line, 0 })
    highlight_current_line()
  end, { buffer = picker_buf, desc = "Next line (wrap)" })

  vim.keymap.set("n", "k", function()
    local line_count = #vim.api.nvim_buf_get_lines(picker_buf, 0, -1, false)
    local cur = vim.api.nvim_win_get_cursor(picker_win)[1]
    local prev_line = cur <= 1 and line_count or cur - 1
    vim.api.nvim_win_set_cursor(picker_win, { prev_line, 0 })
    highlight_current_line()
  end, { buffer = picker_buf, desc = "Previous line (wrap)" })

  vim.keymap.set("n", "<C-j>", function()
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

  vim.keymap.set("n", "<C-k>", function()
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

  vim.keymap.set("n", "q", function()
    close_picker(true)
  end, { buffer = picker_buf, desc = "Quit and revert" })

  vim.keymap.set("n", "<Esc>", function()
    close_picker(true)
  end, { buffer = picker_buf, desc = "Quit and revert" })

  vim.keymap.set("n", "<CR>", function()
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
      local ok, err = pcall(core_ref.apply, theme, true)
      if not ok then
        log("ERROR", "Failed to apply theme", { theme = theme, error = err })
        vim.notify("Failed to apply theme: " .. theme, vim.log.levels.ERROR)
        return
      end
    end

    state_ref.current = theme
    state_ref.saved = theme
    if core_ref and core_ref.save_state then
      pcall(core_ref.save_state)
    end
    close_picker(false)
  end, { buffer = picker_buf, desc = "Select theme" })

  vim.keymap.set("n", "c", function()
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

  vim.keymap.set("n", "s", function()
    local sort_modes = { "alpha", "recent", "usage" }
    local idx = vim.fn.index(sort_modes, state_ref.sort_mode or "alpha") + 1
    state_ref.sort_mode = sort_modes[(idx % #sort_modes) + 1]
    if core_ref and core_ref.save_state then
      pcall(core_ref.save_state)
    end
    local new_title = base_title .. " (Sort: " .. state_ref.sort_mode .. ")"
    vim.api.nvim_win_set_config(picker_win, { title = new_title })
    log("DEBUG", "Sort mode changed", state_ref.sort_mode)
    render(opts)
  end, { buffer = picker_buf, desc = "Cycle sort mode" })

  vim.keymap.set("n", "/", open_search, { buffer = picker_buf, desc = "Search themes" })

  vim.keymap.set("n", "b", function()
    local line = vim.api.nvim_get_current_line()
    local theme = parse_line_theme(line)
    if theme then
      core_ref.toggle_bookmark(theme)
      bookmarks = {}
      for _, b in ipairs(state_ref.bookmarks or {}) do
        if type(b) == "string" and b ~= "" then
          bookmarks[b] = true
        end
      end
      render(opts)
      log("DEBUG", "Bookmark toggled", theme)
    end
  end, { buffer = picker_buf, desc = "Toggle bookmark" })

  vim.keymap.set("n", "?", function()
    local help = {
      "Raphael Picker - Keybindings:",
      "",
      "  j/k         - Navigate (wraps around)",
      "  <C-j>/<C-k> - Jump to next/prev group header (wraps)",
      "  <CR>        - Select theme",
      "  c           - Collapse/expand group",
      "  s           - Cycle sort mode",
      "  /           - Search themes",
      "  b           - Toggle bookmark",
      "  q/<Esc>     - Quit (revert theme)",
      "  ?           - Show this help",
      "",
      "Debug commands:",
      "  :lua require('raphael.picker').toggle_debug()",
      "  :lua require('raphael.picker').toggle_animations()",
      "  :lua print(vim.inspect(require('raphael.picker').get_cache_stats()))",
    }
    vim.notify(table.concat(help, "\n"), vim.log.levels.INFO)
  end, { buffer = picker_buf, desc = "Show help" })

  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = picker_buf,
    callback = function()
      local ok, line = pcall(vim.api.nvim_get_current_line)
      if not ok then
        return
      end
      local theme = parse_line_theme(line)
      if theme then
        preview(theme)
      end
      highlight_current_line()
    end,
  })

  vim.api.nvim_create_autocmd("BufDelete", {
    buffer = picker_buf,
    once = true,
    callback = function()
      log("DEBUG", "Picker buffer deleted, cleaning up")
      cleanup_timers()
    end,
  })

  render(opts)
  highlight_current_line()

  if state_ref.current then
    M.update_palette(state_ref.current)
  end

  log("DEBUG", "Picker opened successfully")
end

return M
