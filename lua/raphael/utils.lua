-- lua/raphael/utils.lua
--- Pure utility functions: theme detection, fuzzy matching,
--- safe colorscheme application, string helpers, etc.
---
--- These helpers are intentionally stateless (no internal caching):
---   - They either query Neovim state (runtimepath, options)
---   - Or operate purely on their inputs.

local M = {}

--- Get all installed colorschemes by scanning 'runtimepath'.
---
--- Looks for:
---   - colors/*.vim
---   - colors/*.lua
---
---@return string[] themes  List of all available theme names (sorted)
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

--- Get themes from user's configured theme_map.
---
--- Traverses a potentially nested theme_map and returns a flat, deduplicated
--- list of theme names.
---
---@param theme_map table User's theme_map configuration
---@return string[] themes  Flat list of all configured themes
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

--- Flatten theme_map into list with group information.
---
--- The returned array contains entries of the form:
---   { name = string, group = string|nil, is_header = boolean }
---
--- Example:
---   theme_map = {
---     group1 = { "a", "b" },
---     single = "c",
---   }
---
--- returns e.g.
---   {
---     { name = "group1", group = nil,    is_header = true  },
---     { name = "a",      group = "group1", is_header = false },
---     { name = "b",      group = "group1", is_header = false },
---     { name = "c",      group = nil,    is_header = false },
---   }
---
---@param theme_map table User's theme_map
---@return table items Array of {name, group, is_header}
function M.flatten_theme_map(theme_map)
  local items = {}

  for key, value in pairs(theme_map) do
    if type(value) == "table" then
      table.insert(items, {
        name = key,
        group = nil,
        is_header = true,
      })

      for _, theme in ipairs(value) do
        table.insert(items, {
          name = theme,
          group = key,
          is_header = false,
        })
      end
    else
      table.insert(items, {
        name = value,
        group = nil,
        is_header = false,
      })
    end
  end

  return items
end

--- Check if a theme exists (is installed) by scanning runtimepath.
---
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

--- Safely apply a colorscheme with error handling.
---
---@param theme string Theme name
---@return boolean success  Whether application succeeded
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

--- Fuzzy match scorer (simple implementation).
---
--- Heuristics:
---   - Empty query → score 1 (always matches)
---   - Exact match → score 1000
---   - Prefix match → score 500
---   - Substring match → score 250
---   - Otherwise:
---       * all chars of query must appear in `str` in order
---       * base score + small bonus for consecutive matches
---
---@param str string  String to search in
---@param query string Query string
---@return number score Match score (higher is better, 0 = no match)
function M.fuzzy_score(str, query)
  if not query or query == "" then
    return 1
  end

  str = str:lower()
  query = query:lower()

  if str == query then
    return 1000
  end

  if str:sub(1, #query) == query then
    return 500
  end

  if str:find(query, 1, true) then
    return 250
  end

  local score = 0
  local str_idx = 1
  local consecutive = 0

  for i = 1, #query do
    local char = query:sub(i, i)
    local found = str:find(char, str_idx, true)

    if found then
      score = score + 10

      if found == str_idx then
        consecutive = consecutive + 1
        score = score + consecutive * 5
      else
        consecutive = 0
      end

      str_idx = found + 1
    else
      return 0
    end
  end

  return score
end

--- Filter and sort items by fuzzy query.
---
--- Expects `items` to be an array of tables each with a `.name` field.
--- Returns a new array sorted by descending fuzzy_score(name, query).
---
---@param items table[]   Array of items with .name field
---@param query string    Search query
---@return table[] filtered Filtered and sorted items
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

--- Deep copy a table (recursive).
---
---@param tbl any  Table or value to copy
---@return any copy Deep copy if table, otherwise the value itself
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

--- Check if a list-like table contains a value (ipairs-based).
---
---@param tbl table
---@param value any
---@return boolean contains
function M.tbl_contains(tbl, value)
  for _, v in ipairs(tbl) do
    if v == value then
      return true
    end
  end
  return false
end

--- Get random theme from list.
---
--- @param themes string[] Array of theme names
--- @return string|nil theme Random theme, or nil if empty
function M.random_theme(themes)
  if #themes == 0 then
    return nil
  end
  math.randomseed(os.time())
  return themes[math.random(#themes)]
end

--- Clamp number to range [min, max].
---
---@param value number Value to clamp
---@param min   number Minimum value
---@param max   number Maximum value
---@return number clamped Clamped value
function M.clamp(value, min, max)
  return math.max(min, math.min(max, value))
end

--- Get window dimensions for picker.
---
--- Computes a centered rectangle of the given width/height percentages.
---
---@param width_pct  number Width as fraction of total columns (0-1)
---@param height_pct number Height as fraction of total lines (0-1)
---@return table dimensions { width, height, row, col }
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

--- Truncate string to max length with ellipsis.
---
---@param str     string String to truncate
---@param max_len integer Maximum length
---@return string truncated Truncated string (with "…" if truncated)
function M.truncate(str, max_len)
  if #str <= max_len then
    return str
  end
  return str:sub(1, max_len - 1) .. "…"
end

--- Pad string to length (left-aligned), respecting display width.
---
---@param str  string String to pad
---@param len  integer Target display width
---@param char string|nil Padding character (default: space)
---@return string padded Padded string
function M.pad_right(str, len, char)
  char = char or " "
  local padding = len - vim.fn.strdisplaywidth(str)
  if padding <= 0 then
    return str
  end
  return str .. string.rep(char, padding)
end

--- Create a notification (intended to respect config.notifications).
---
--- NOTE:
---   - This assumes there is a `config.get()` API returning the current
---     effective config, which you might want to implement.
---   - If `config.notifications.enabled` is false, it is silent.
---
---@param msg    string       Message to display
---@param level  integer      Log level (vim.log.levels.*)
---@param config table|nil    User configuration (optional; if nil, tries config.get())
function M.notify(msg, level, config)
  config = config or (require("raphael.config").get and require("raphael.config").get()) or {}

  config.notifications = config.notifications
    or {
      enabled = true,
      on_error = true,
      on_warn = true,
      on_info = true,
    }

  if not config.notifications.enabled then
    return
  end

  if level == vim.log.levels.ERROR and config.notifications.on_error == false then
    return
  end
  if level == vim.log.levels.WARN and config.notifications.on_warn == false then
    return
  end
  if level == vim.log.levels.INFO and config.notifications.on_info == false then
    return
  end

  local prefix = ""
  if level == vim.log.levels.ERROR then
    prefix = " "
  elseif level == vim.log.levels.WARN then
    prefix = " "
  elseif level == vim.log.levels.INFO then
    prefix = " "
  end

  vim.notify(prefix .. msg, level)
end

return M
