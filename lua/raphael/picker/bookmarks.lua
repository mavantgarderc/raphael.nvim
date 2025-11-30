-- lua/raphael/picker/bookmarks.lua
-- Small helpers for bookmark handling inside the picker.
--
-- Responsibilities:
--   - Convert the persistent `state.bookmarks` (scope -> list) into a fast
--     lookup set (theme -> boolean) for the active scope.

local M = {}

--- Build a set (map) from state.bookmarks for the active scope.
---
--- state.bookmarks is scope -> { "theme-a", "theme-b", ... }
--- We pick scope based on:
---   - core.config.profile_scoped_state
---   - core.state.current_profile / core.config.current_profile
--- and always fallback to __global.
---
---@param state table  # usually core.state
---@param core  table  # require("raphael.core")
---@return table<string, boolean> set  # map: theme_name -> true
function M.build_set(state, core)
  local set = {}

  if type(state.bookmarks) ~= "table" then
    return set
  end

  local scope = "__global"
  if core and core.config and core.config.profile_scoped_state then
    local profile = (core.state and core.state.current_profile) or core.config.current_profile
    if type(profile) == "string" and profile ~= "" then
      scope = profile
    end
  end

  local scoped_list = state.bookmarks[scope] or state.bookmarks.__global or {}
  if type(scoped_list) ~= "table" then
    return set
  end

  for _, b in ipairs(scoped_list) do
    if type(b) == "string" and b ~= "" then
      set[b] = true
    end
  end

  return set
end

return M
