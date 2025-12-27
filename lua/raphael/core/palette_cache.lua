-- lua/raphael/core/palette_cache.lua
-- Enhanced caching system for theme palettes and highlight information
-- This module provides efficient caching and retrieval of theme palette data

local M = {}

local themes = require("raphael.themes")
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

-- Cache structure: { theme_name = { timestamp, palette_data } }
local cache = {}
local max_cache_size = 50
local cache_timeout = 300

--- Get highlight RGB value for a given highlight group
---@param name string Highlight group name
---@return table|nil hl_data Highlight data with fg, bg, etc.
local function get_hl_rgb(name)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  if ok and hl then
    return hl
  end
  return nil
end

--- Generate palette data for a theme
---@param theme string Theme name
---@return table|nil palette_data Palette data with highlight information
function M.generate_palette_data(theme)
  if not theme or not themes.is_available(theme) then
    return nil
  end

  local current_colors_name = vim.g.colors_name
  local current_hls = {}

  for _, hl_name in ipairs(PALETTE_HL) do
    current_hls[hl_name] = get_hl_rgb(hl_name)
  end

  local success = pcall(function()
    vim.cmd("hi clear")
    if vim.fn.exists("syntax_on") == 1 then
      vim.cmd("syntax reset")
    end

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
  end)

  if not success then
    for hl_name, hl_data in pairs(current_hls) do
      if hl_data then
        pcall(vim.api.nvim_set_hl, 0, hl_name, hl_data)
      end
    end
    if current_colors_name then
      pcall(vim.api.nvim_set_var, "colors_name", current_colors_name)
    else
      pcall(vim.api.nvim_del_var, "colors_name")
    end
    return nil
  end

  local palette_data = {}
  for _, hl_name in ipairs(PALETTE_HL) do
    local hl = get_hl_rgb(hl_name)
    if hl then
      palette_data[hl_name] = {
        fg = hl.fg or hl.foreground,
        bg = hl.bg or hl.background,
        sp = hl.sp or hl.special,
        bold = hl.bold,
        italic = hl.italic,
        underline = hl.underline,
        reverse = hl.reverse,
      }
    end
  end

  for hl_name, hl_data in pairs(current_hls) do
    if hl_data then
      pcall(vim.api.nvim_set_hl, 0, hl_name, hl_data)
    end
  end
  if current_colors_name then
    pcall(vim.api.nvim_set_var, "colors_name", current_colors_name)
  else
    pcall(vim.api.nvim_del_var, "colors_name")
  end

  if current_colors_name then
    pcall(vim.cmd.colorscheme, current_colors_name)
  end

  return palette_data
end

--- Check if cache entry is still valid (not expired)
---@param entry table Cache entry with timestamp
---@return boolean Validity status
local function is_cache_valid(entry)
  if not entry or not entry.timestamp then
    return false
  end
  return (os.time() - entry.timestamp) < cache_timeout
end

--- Get cached palette data for a theme
---@param theme string Theme name
---@return table|nil palette_data Cached palette data or nil if not available/cached
function M.get_cached_palette(theme)
  if not theme then
    return nil
  end

  local entry = cache[theme]
  if entry and is_cache_valid(entry) then
    return entry.palette_data
  end

  if entry then
    cache[theme] = nil
  end

  return nil
end

--- Cache palette data for a theme
---@param theme string Theme name
---@param palette_data table Palette data to cache
function M.cache_palette(theme, palette_data)
  if not theme or not palette_data then
    return
  end

  local cache_keys = {}
  for k in pairs(cache) do
    table.insert(cache_keys, k)
  end

  if #cache_keys >= max_cache_size then
    local oldest_key = nil
    local oldest_time = math.huge
    for k, v in pairs(cache) do
      if v.timestamp and v.timestamp < oldest_time then
        oldest_time = v.timestamp
        oldest_key = k
      end
    end
    if oldest_key then
      cache[oldest_key] = nil
    end
  end

  cache[theme] = {
    timestamp = os.time(),
    palette_data = palette_data,
  }
end

--- Preload palettes for a list of themes (async and non-blocking)
---@param themes_list table List of theme names to preload
function M.preload_palettes(themes_list)
  if not themes_list or type(themes_list) ~= "table" then
    return
  end

  local max_preload = 10
  local preload_list = {}

  for i, theme in ipairs(themes_list) do
    if i > max_preload then
      break
    end
    table.insert(preload_list, theme)
  end

  vim.defer_fn(function()
    local function preload_next(index)
      if index > #preload_list then
        return
      end

      local theme = preload_list[index]
      if not M.get_cached_palette(theme) then
        local palette_data = M.generate_palette_data(theme)
        if palette_data then
          M.cache_palette(theme, palette_data)
        end
      end

      vim.defer_fn(function()
        preload_next(index + 1)
      end, 10)
    end

    preload_next(1)
  end, 10)
end

--- Clear the entire cache
function M.clear_cache()
  cache = {}
end

--- Clear expired entries from cache
function M.clear_expired()
  local now = os.time()
  for theme, entry in pairs(cache) do
    if (now - entry.timestamp) >= cache_timeout then
      cache[theme] = nil
    end
  end
end

--- Get cache statistics
---@return table Cache statistics
function M.get_stats()
  local valid_count = 0
  local expired_count = 0
  local now = os.time()

  for _, entry in pairs(cache) do
    if (now - entry.timestamp) < cache_timeout then
      valid_count = valid_count + 1
    else
      expired_count = expired_count + 1
    end
  end

  return {
    total_entries = valid_count + expired_count,
    valid_entries = valid_count,
    expired_entries = expired_count,
    max_size = max_cache_size,
    timeout_seconds = cache_timeout,
  }
end

--- Get palette data with caching
--- This is the main function to use when you need palette data
---@param theme string Theme name
---@return table|nil palette_data Palette data (cached or generated)
function M.get_palette_with_cache(theme)
  if not theme then
    return nil
  end

  local cached = M.get_cached_palette(theme)
  if cached then
    return cached
  end

  local palette_data = M.generate_palette_data(theme)
  if palette_data then
    M.cache_palette(theme, palette_data)
    return palette_data
  end

  return nil
end

return M
