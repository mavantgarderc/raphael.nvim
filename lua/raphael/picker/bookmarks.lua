local M = {}

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
