local M = {}

-- flatten table
function M.flatten(tbl)
  local out = {}
  for _, v in pairs(tbl) do
    if type(v) == "table" then
      for _, x in ipairs(v) do
        table.insert(out, x)
      end
    else
      table.insert(out, v)
    end
  end
  return out
end

return M
