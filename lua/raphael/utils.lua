-- lua/raphael/utils.lua
--- Pure utility functions: theme detection, fuzzy matching, safe colorscheme, etc.

local M = {}

--- Get all installed colorschemes
---@return table themes List of all available theme names
function M.get_all_themes()
  local themes = {}
  local rtp = vim.api.nvim_list_runtime_paths()

  for _, path in ipairs(rtp) do
    local colors_dir = path .. "/colors"
    if vim.fn.isdirectory(colors_dir) == 1 then
      local files = vim.fn.readdir(colors_dir)
      for _, file in ipairs(files) do
        if file:match("%.lua$") or file:match("%.vim$") then
          local theme_name = file:gsub("%.lua$", ""):gsub("%.vim$", "")
          if not vim.tbl_contains(themes, theme_name) then
            table.insert(themes, theme_name)
          end
        end
      end
    end
  end

  table.sort(themes)
  return themes
end

--- Get themes from user's configured theme_map
---@param theme_map table User's theme_map configuration
---@return table themes Flat list of all configured themes
function M.get_configured_themes(theme_map)
  local themes = {}
  local seen = {}

  local function add_theme(name)
    if not seen[name] then
      table.insert(themes, name)
      seen[name] = true
    end
  end

  local function traverse(node)
    if type(node) == "string" then
      add_theme(node)
    elseif type(node) == "table" then
      for _, value in pairs(node) do
        traverse(value)
      end
    end
  end

  traverse(theme_map)
  return themes
end

--- Flatten theme_map into list with group information
---@param theme_map table User's theme_map
---@return table items Array of {name, group, is_header}
function M.flatten_theme_map(theme_map)
  local items = {}

  for key, value in pairs(theme_map) do
    if type(value) == "table" then
      -- It's a group
      table.insert(items, {
        name = key,
        group = nil,
        is_header = true,
      })

      -- Add themes in group
      for _, theme in ipairs(value) do
        table.insert(items, {
          name = theme,
          group = key,
          is_header = false,
        })
      end
    else
      -- It's a standalone theme
      table.insert(items, {
        name = value,
        group = nil,
        is_header = false,
      })
    end
  end

  return items
end

--- Check if a theme exists (is installed)
---@param theme string Theme name
---@return boolean exists
function M.theme_exists(theme)
  local all_themes = M.get_all_themes()
  for _, name in ipairs(all_themes) do
    if name == theme then
      return true
    end
  end
  return false
end

--- Safely apply a colorscheme with error handling
---@param theme string Theme name
---@return boolean success Whether application succeeded
---@return string|nil error Error message if failed
function M.safe_colorscheme(theme)
  if not theme or theme == "" then
    return false, "Empty theme name"
  end

  local ok, err = pcall(vim.cmd.colorscheme, theme)
  if not ok then
    return false, tostring(err)
  end

  return true
end

--- Fuzzy match scorer (simple implementation)
---@param str string String to search in
---@param query string Query string
---@return number score Match score (higher is better, 0 = no match)
function M.fuzzy_score(str, query)
  if not query or query == "" then
    return 1
  end

  str = str:lower()
  query = query:lower()

  -- Exact match gets highest score
  if str == query then
    return 1000
  end

  -- Starts with query gets high score
  if str:sub(1, #query) == query then
    return 500
  end

  -- Contains query gets medium score
  if str:find(query, 1, true) then
    return 250
  end

  -- Fuzzy match: all chars in order
  local score = 0
  local str_idx = 1
  local consecutive = 0

  for i = 1, #query do
    local char = query:sub(i, i)
    local found = str:find(char, str_idx, true)

    if found then
      score = score + 10

      -- Bonus for consecutive matches
      if found == str_idx then
        consecutive = consecutive + 1
        score = score + consecutive * 5
      else
        consecutive = 0
      end

      str_idx = found + 1
    else
      return 0 -- Not a match
    end
  end

  return score
end

--- Filter and sort items by fuzzy query
---@param items table Array of items with .name field
---@param query string Search query
---@return table filtered Filtered and sorted items
function M.fuzzy_filter(items, query)
  if not query or query == "" then
    return items
  end

  local scored = {}
  for _, item in ipairs(items) do
    local score = M.fuzzy_score(item.name, query)
    if score > 0 then
      table.insert(scored, { item = item, score = score })
    end
  end

  table.sort(scored, function(a, b)
    return a.score > b.score
  end)

  local filtered = {}
  for _, entry in ipairs(scored) do
    table.insert(filtered, entry.item)
  end

  return filtered
end

--- Deep copy a table
---@param tbl table Table to copy
---@return table copy Deep copy
function M.deep_copy(tbl)
  if type(tbl) ~= "table" then
    return tbl
  end
  local copy = {}
  for k, v in pairs(tbl) do
    copy[k] = M.deep_copy(v)
  end
  return copy
end

--- Check if table contains value
---@param tbl table Table to search
---@param value any Value to find
---@return boolean contains
function M.tbl_contains(tbl, value)
  for _, v in ipairs(tbl) do
    if v == value then
      return true
    end
  end
  return false
end

--- Get random theme from list
---@param themes table Array of theme names
---@return string|nil theme Random theme, or nil if empty
function M.random_theme(themes)
  if #themes == 0 then
    return nil
  end
  math.randomseed(os.time())
  return themes[math.random(#themes)]
end

--- Clamp number to range
---@param value number Value to clamp
---@param min number Minimum value
---@param max number Maximum value
---@return number clamped Clamped value
function M.clamp(value, min, max)
  return math.max(min, math.min(max, value))
end

--- Get window dimensions for picker
---@param width_pct number Width as percentage (0-1)
---@param height_pct number Height as percentage (0-1)
---@return table dimensions {width, height, row, col}
function M.get_picker_dimensions(width_pct, height_pct)
  local screen_w = vim.o.columns
  local screen_h = vim.o.lines

  local width = math.floor(screen_w * width_pct)
  local height = math.floor(screen_h * height_pct)

  local row = math.floor((screen_h - height) / 2)
  local col = math.floor((screen_w - width) / 2)

  return {
    width = width,
    height = height,
    row = row,
    col = col,
  }
end

--- Truncate string to max length with ellipsis
---@param str string String to truncate
---@param max_len number Maximum length
---@return string truncated Truncated string
function M.truncate(str, max_len)
  if #str <= max_len then
    return str
  end
  return str:sub(1, max_len - 1) .. "…"
end

--- Pad string to length (left-aligned)
---@param str string String to pad
---@param len number Target length
---@param char string Padding character (default: space)
---@return string padded Padded string
function M.pad_right(str, len, char)
  char = char or " "
  local padding = len - vim.fn.strdisplaywidth(str)
  if padding <= 0 then
    return str
  end
  return str .. string.rep(char, padding)
end

--- Create a notification (respects config.notifications)
---@param msg string Message to display
---@param level number Log level (vim.log.levels)
---@param config table User configuration
function M.notify(msg, level, config)
  config = config or require("raphael.config").get()

  if not config.notifications.enabled then
    return
  end

  if level == vim.log.levels.ERROR and not config.notifications.on_error then
    return
  end

  -- Add emoji prefix based on level
  local prefix = ""
  if level == vim.log.levels.ERROR then
    prefix = " "
  elseif level == vim.log.levels.WARN then
    prefix = " "
  elseif level == vim.log.levels.INFO then
    prefix = " "
  end

  vim.notify(prefix .. msg, level)
end

return M
