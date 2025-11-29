-- lua/raphael/themes.lua
-- Theme discovery & configuration helpers.
--
-- Responsibilities:
--   - Discover installed colorschemes from runtimepath (refresh)
--   - Track configured theme_map and filetype_themes
--   - Provide helpers to flatten nested theme_map into a flat list

local M = {}

--- User/config-provided theme structure.
---
--- Can be:
---   - list:
---       {
---         "a",
---         "b",
---         "c",
---       }
---   - map:
---       {
---         group1 = { "a", "b" },
---         group2 = { "c" },
---       }
---   - nested mix of lists and maps:
---       theme_map = {
---         group1 = {
---           "a",
---           subgroup = { "b", "c" },
---         },
---         group2 = { "d" },
---       }
---
--- This is usually set from user config (config.theme_map).
---@type table
M.theme_map = {}

--- Filetype-specific themes: ft -> theme_name
---
--- Example:
---   filetype_themes = {
---     lua = "kanagawa-paper-ink",
---     rust = "duskpunk",
---   }
---@type table<string, string>
M.filetype_themes = {}

--- Installed themes discovered from runtimepath: theme_name -> true
---
--- Populated by M.refresh().
---@type table<string, boolean>
M.installed = {}

-- ────────────────────────────────────────────────────────────────────────
-- Discovery
-- ────────────────────────────────────────────────────────────────────────

--- Refresh installed theme list by scanning all runtime paths.
---
--- This inspects each entry in 'runtimepath' and collects any files in:
---   - colors/*.vim
---   - colors/*.lua
---
--- The basename (without extension) becomes the theme name.
function M.refresh()
  M.installed = {}

  local rtp = vim.api.nvim_list_runtime_paths()
  for _, p in ipairs(rtp) do
    local vim_files = vim.fn.globpath(p, "colors/*.vim", false, true)
    local lua_files = vim.fn.globpath(p, "colors/*.lua", false, true)
    local all = vim.list_extend(vim_files, lua_files)

    for _, f in ipairs(all) do
      local theme_name = vim.fn.fnamemodify(f, ":t:r")
      M.installed[theme_name] = true
    end
  end
end

--- Check if a theme name is installed/available.
---
---@param theme string
---@return boolean
function M.is_available(theme)
  return M.installed[theme] == true
end

-- ────────────────────────────────────────────────────────────────────────
-- theme_map flattening helpers
-- ────────────────────────────────────────────────────────────────────────

--- Recursively collect theme names from any node in theme_map.
---
--- Node can be:
---   - string (theme name)
---   - list of nodes (array-like table)
---   - map of keys -> nodes (group_name -> nested structure)
---
---@param node any
---@param acc  string[]
local function collect_themes(node, acc)
  local t = type(node)
  if t == "string" then
    table.insert(acc, node)
    return
  end

  if t ~= "table" then
    return
  end

  if vim.islist(node) then
    for _, v in ipairs(node) do
      collect_themes(v, acc)
    end
    return
  end

  for _, v in pairs(node) do
    collect_themes(v, acc)
  end
end

--- Get all configured themes from theme_map, flattening any nesting.
---
--- Behavior:
---   - If M.theme_map is nil or empty:
---       * falls back to all installed themes, sorted alphabetically
---   - Otherwise:
---       * collects all string leaves from theme_map recursively
---
---@return string[] themes  # flat list of theme names
function M.get_all_themes()
  local acc = {}

  if not M.theme_map or next(M.theme_map) == nil then
    for name, _ in pairs(M.installed) do
      table.insert(acc, name)
    end
    table.sort(acc)
    return acc
  end

  collect_themes(M.theme_map, acc)
  return acc
end

return M
