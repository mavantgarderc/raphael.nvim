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
local RENDER_DEBOUNCE_MS = 50

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

local function debounce(ms, fn)
  local timer = nil
  return function(...)
    local args = { ... }
    if timer then
      ---@diagnostic disable-next-line: undefined-field
      pcall(vim.loop.timer_stop, timer)
      ---@diagnostic disable-next-line: undefined-field
      pcall(vim.loop.close, timer)
      timer = nil
    end
    timer = vim.defer_fn(function()
      pcall(fn, unpack(args))
      timer = nil
    end, ms)
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
  pcall(vim.api.nvim_set_hl, 0, key, { fg = color_int })
  palette_hl_cache[key] = true
  return key
end

function M.update_palette(theme)
  palette_hl_cache = {}
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

  local pal_row, pal_col, pal_width = math.max(picker_row - 2, 0), picker_col, picker_w
  if palette_win and vim.api.nvim_win_is_valid(palette_win) then
    pcall(vim.api.nvim_win_set_buf, palette_win, palette_buf)
    pcall(
      vim.api.nvim_win_set_config,
      palette_win,
      { relative = "editor", width = pal_width, height = 1, row = pal_row, col = pal_col, style = "minimal" }
    )
  else
    palette_win = vim.api.nvim_open_win(
      palette_buf,
      false,
      {
        relative = "editor",
        width = pal_width,
        height = 1,
        row = pal_row,
        col = pal_col,
        style = "minimal",
        zindex = 50,
      }
    )
    pcall(vim.api.nvim_set_option_value, "winhl", "Normal:Normal", { win = palette_win })
  end
end

last_cursor = last_cursor or {}

local function render_internal(opts)
  opts = opts or picker_opts
  picker_opts = opts
  local only_configured = opts.only_configured or false
  local exclude_configured = opts.exclude_configured or false

  if only_configured and exclude_configured then
    return
  end
  if not picker_buf or not vim.api.nvim_buf_is_valid(picker_buf) then
    return
  end

  local current_group
  local current_line = 1
  if picker_win and vim.api.nvim_win_is_valid(picker_win) then
    current_line = vim.api.nvim_win_get_cursor(picker_win)[1]
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

  local lines = {}
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
  elseif only_configured then
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

  local bookmark_filtered = {}
  for _, t in ipairs(state_ref.bookmarks or {}) do
    if search_query == "" or (t:lower():find(search_query:lower(), 1, true)) then
      table.insert(bookmark_filtered, t)
    end
  end
  if #bookmark_filtered > 0 then
    local bookmark_icon = collapsed["__bookmarks"] and ICON_GROUP_COL or ICON_GROUP_EXP
    table.insert(lines, bookmark_icon .. " Bookmarks (" .. #state_ref.bookmarks .. ")")
    if not collapsed["__bookmarks"] then
      for _, t in ipairs(bookmark_filtered) do
        local warning = themes.is_available(t) and "" or " 󰝧 "
        local b = " "
        local s = (state_ref and state_ref.current == t) and ICON_CURRENT_ON or ICON_CURRENT_OFF
        table.insert(lines, "  " .. warning .. b .. s .. t)
      end
    end
  end

  local recent_filtered = {}
  for _, t in ipairs(state_ref.history or {}) do
    if search_query == "" or (t:lower():find(search_query:lower(), 1, true)) then
      table.insert(recent_filtered, t)
    end
  end
  if #recent_filtered > 0 then
    local recent_icon = collapsed["__recent"] and ICON_GROUP_COL or ICON_GROUP_EXP
    table.insert(lines, recent_icon .. " Recent (" .. #state_ref.history .. ")")
    if not collapsed["__recent"] then
      for _, t in ipairs(recent_filtered) do
        local warning = themes.is_available(t) and "" or " 󰝧 "
        local b = bookmarks[t] and ICON_BOOKMARK or " "
        local s = (state_ref and state_ref.current == t) and ICON_CURRENT_ON or ICON_CURRENT_OFF
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
      local s = (state_ref and state_ref.current == t) and ICON_CURRENT_ON or ICON_CURRENT_OFF
      table.insert(lines, string.format("%s%s %s %s", warning, b, s, t))
    end
  else
    for group, items in pairs(display_map) do
      local group_candidates = items
      local filtered_items = search_query == "" and group_candidates
        or vim.fn.matchfuzzy(group_candidates, search_query, { text = true })
      sort_filtered(filtered_items)

      if #filtered_items > 0 then
        local header_icon = collapsed[group] and ICON_GROUP_COL or ICON_GROUP_EXP
        local summary = string.format("(%d)", #items)
        table.insert(lines, string.format("%s %s %s", header_icon, group, summary))

        if not collapsed[group] then
          for _, t in ipairs(filtered_items) do
            local warning = themes.is_available(t) and "" or " 󰝧 "
            local b = bookmarks[t] and ICON_BOOKMARK or " "
            local s = (state_ref and state_ref.current == t) and ICON_CURRENT_ON or ICON_CURRENT_OFF
            table.insert(lines, string.format("  %s%s %s %s", warning, b, s, t))
          end
        end
      end
    end
  end

  pcall(vim.api.nvim_set_option_value, "modifiable", true, { buf = picker_buf })
  pcall(vim.api.nvim_buf_set_lines, picker_buf, 0, -1, false, lines)
  pcall(vim.api.nvim_set_option_value, "modifiable", false, { buf = picker_buf })

  if picker_win and vim.api.nvim_win_is_valid(picker_win) then
    local restore_line = 1
    if current_group and last_cursor[current_group] then
      restore_line = math.min(last_cursor[current_group], #lines)
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

local function close_picker(revert)
  if revert and state_ref and state_ref.previous and themes.is_available(state_ref.previous) then
    pcall(vim.cmd.colorscheme, state_ref.previous)
    if core_ref and core_ref.apply then
      core_ref.apply(state_ref.previous, true)
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
end

local function do_preview(theme)
  if not theme or not themes.is_available(theme) then
    return
  end
  if previewed == theme then
    return
  end
  previewed = theme
  pcall(vim.cmd.colorscheme, theme)
  pcall(M.update_palette, theme)
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

  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    buffer = search_buf,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(search_buf, 0, -1, false)
      search_query = trim(table.concat(lines, "\n"):gsub("^" .. ICON_SEARCH .. " ", ""))
      render()
    end,
  })

  vim.keymap.set("i", "<Esc>", function()
    if search_win and vim.api.nvim_win_is_valid(search_win) then
      pcall(vim.api.nvim_win_close, search_win, true)
    end
    search_buf, search_win = nil, nil
    vim.cmd("stopinsert")
    if picker_win and vim.api.nvim_win_is_valid(picker_win) then
      pcall(vim.api.nvim_set_current_win, picker_win)
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
  end, { buffer = search_buf })
end

function M.open(core, opts)
  opts = opts or {}
  picker_opts = opts
  core_ref = core
  state_ref = core.state

  bookmarks = {}
  for _, b in ipairs(state_ref.bookmarks or {}) do
    bookmarks[b] = true
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

  vim.keymap.set("n", "<C-j>", function()
    local cur = vim.api.nvim_win_get_cursor(picker_win)[1]
    for _, ln in ipairs(header_lines) do
      if ln > cur then
        vim.api.nvim_win_set_cursor(picker_win, { ln, 0 })
        break
      end
    end
  end, { buffer = picker_buf })

  vim.keymap.set("n", "<C-k>", function()
    local cur = vim.api.nvim_win_get_cursor(picker_win)[1]
    for i = #header_lines, 1, -1 do
      if header_lines[i] < cur then
        vim.api.nvim_win_set_cursor(picker_win, { header_lines[i], 0 })
        break
      end
    end
  end, { buffer = picker_buf })

  vim.keymap.set("n", "q", function()
    close_picker(true)
  end, { buffer = picker_buf })

  vim.keymap.set("n", "<Esc>", function()
    close_picker(true)
  end, { buffer = picker_buf })

  vim.keymap.set("n", "<CR>", function()
    local line = vim.api.nvim_get_current_line()
    local hdr = parse_line_header(line)
    if hdr then
      return
    end
    local theme = parse_line_theme(line)
    if not theme then
      vim.notify("No theme on this line", vim.log.levels.WARN)
      return
    end
    if not themes.is_available(theme) then
      vim.notify("Theme not installed: " .. theme, vim.log.levels.ERROR)
      return
    end
    if core_ref and core_ref.apply then
      pcall(core_ref.apply, theme, true)
    end
    state_ref.current = theme
    state_ref.saved = theme
    if core_ref and core_ref.save_state then
      pcall(core_ref.save_state)
    end
    close_picker(false)
  end, { buffer = picker_buf })

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
      collapsed[hdr] = not collapsed[hdr]
      state_ref.collapsed = vim.deepcopy(collapsed)
      if core_ref and core_ref.save_state then
        pcall(core_ref.save_state)
      end
      render(picker_opts)
    else
      vim.notify("No group detected for current line", vim.log.levels.WARN)
    end
  end, { buffer = picker_buf, desc = "Collapse/expand group under cursor" })

  vim.keymap.set("n", "s", function()
    local sort_modes = { "alpha", "recent", "usage" }
    local idx = vim.fn.index(sort_modes, state_ref.sort_mode or "alpha") + 1
    state_ref.sort_mode = sort_modes[(idx % #sort_modes) + 1]
    if core_ref and core_ref.save_state then
      pcall(core_ref.save_state)
    end
    local new_title = base_title .. " (Sort: " .. state_ref.sort_mode .. ")"
    vim.api.nvim_win_set_config(picker_win, { title = new_title })
    render(opts)
  end, { buffer = picker_buf, desc = "Cycle sort mode" })

  vim.keymap.set("n", "/", open_search, { buffer = picker_buf })

  vim.keymap.set("n", "b", function()
    local line = vim.api.nvim_get_current_line()
    local theme = parse_line_theme(line)
    if theme then
      core_ref.toggle_bookmark(theme)
      bookmarks = {}
      for _, b in ipairs(state_ref.bookmarks or {}) do
        bookmarks[b] = true
      end
      render(opts)
    end
  end, { buffer = picker_buf, desc = "Toggle bookmark" })

  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = picker_buf,
    callback = function()
      local line = vim.api.nvim_get_current_line()
      local theme = parse_line_theme(line)
      preview(theme)
    end,
  })

  render(opts)

  if state_ref.current then
    M.update_palette(state_ref.current)
  end
end

return M
