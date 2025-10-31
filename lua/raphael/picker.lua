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

local ICON_BOOKMARK = " "
local ICON_CURRENT_ON = " "
local ICON_CURRENT_OFF = " "
local ICON_GROUP_EXP = " "
local ICON_GROUP_COL = " "
local BLOCK_CHAR = "󱡌 "
local ICON_SEARCH = " "

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

local function debounce(ms, fn)
  local timer = nil
  return function(...)
    local args = { ... }
    if timer then
      pcall(vim.loop.timer_stop, timer)
      pcall(vim.loop.close, timer)
      timer = nil
    end
    timer = vim.defer_fn(function()
      ---@diagnostic disable-next-line: deprecated
      pcall(fn, unpack(args))
      timer = nil
    end, ms)
  end
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

  if not picker_win or not vim.api.nvim_win_is_valid(picker_win) or not picker_w then
    return
  end

  if not palette_buf or not vim.api.nvim_buf_is_valid(palette_buf) then
    palette_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = palette_buf })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = palette_buf })
    vim.api.nvim_set_option_value("modifiable", false, { buf = palette_buf })
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
  pcall(vim.api.nvim_buf_clear_namespace, palette_buf, -1, 0, -1)

  for i, hl_name in ipairs(PALETTE_HL) do
    local hl = get_hl_rgb(hl_name)
    if hl then
      local color_int = hl.fg or hl.bg
      if color_int then
        local gname = ensure_palette_hl(i, color_int)

        local search_pos = 1
        local occurrence = 0
        while true do
          local s, e = string.find(bufline, BLOCK_CHAR, search_pos, true)
          if not s then
            break
          end
          occurrence = occurrence + 1
          if occurrence == i then
            pcall(vim.api.nvim_buf_add_highlight, palette_buf, -1, gname, 0, s - 1, e)
            break
          end
          search_pos = e + 1
        end
      end
    end
  end

  local pal_row = math.max(picker_row - 2, 0)
  local pal_col = picker_col
  local pal_width = picker_w

  if palette_win and vim.api.nvim_win_is_valid(palette_win) then
    pcall(vim.api.nvim_win_set_buf, palette_win, palette_buf)
    pcall(vim.api.nvim_win_set_config, palette_win, {
      relative = "editor",
      width = pal_width,
      height = 1,
      row = pal_row,
      col = pal_col,
      style = "minimal",
    })
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

local function render(opts)
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
    for _, t in ipairs(display_map) do
      if search_query == "" or (t:lower():find(search_query:lower(), 1, true)) then
        local warning = themes.is_available(t) and "" or " 󰝧 "
        local b = bookmarks[t] and ICON_BOOKMARK or " "
        local s = (state_ref and state_ref.current == t) and ICON_CURRENT_ON or ICON_CURRENT_OFF
        table.insert(lines, string.format("%s%s %s %s", warning, b, s, t))
      end
    end
  else
    for group, items in pairs(display_map) do
      local filtered_items = {}
      for _, t in ipairs(items) do
        if search_query == "" or (t:lower():find(search_query:lower(), 1, true)) then
          table.insert(filtered_items, t)
        end
      end

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

  picker_win = vim.api.nvim_open_win(picker_buf, true, {
    relative = "editor",
    width = picker_w,
    height = picker_h,
    row = picker_row,
    col = picker_col,
    style = "minimal",
    border = "rounded",
    title = opts.exclude_configured and "Raphael - Other Themes" or "Raphael - Configured Themes",
  })

  state_ref.previous = vim.g.colors_name

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
    if hdr then
      vim.notify("Detected header: " .. hdr, vim.log.levels.INFO)
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
      render(opts)
    else
      vim.notify("No header detected on line", vim.log.levels.WARN)
    end
  end, { buffer = picker_buf, desc = "Collapse/expand group" })

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
