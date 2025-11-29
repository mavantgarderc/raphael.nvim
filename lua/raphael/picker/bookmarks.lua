-- lua/raphael/picker/bookmarks.lua
-- Small helpers for bookmark handling inside the picker.
--
-- Responsibilities:
--   - Convert the persistent `state.bookmarks` list into a fast lookup set
--     for use in the picker (theme -> boolean).

local M = {}

--- Build a set (map) from state.bookmarks list.
---
--- Converts a list like:
---   state.bookmarks = { "theme-a", "theme-b", ... }
--- into:
---   { ["theme-a"] = true, ["theme-b"] = true, ... }
---
---@param state table  # usually core.state
---@return table<string, boolean> set  # map: theme_name -> true
function M.build_set(state)
  local set = {}
  if state.bookmarks and type(state.bookmarks) == "table" then
    for _, b in ipairs(state.bookmarks) do
      if type(b) == "string" and b ~= "" then
        set[b] = true
      end
    end
  end
  return set
end

return M
