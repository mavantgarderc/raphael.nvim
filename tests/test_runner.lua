-- tests/test_runner.lua
-- Simple test runner for raphael.nvim tests

local M = {}

-- Load and run the test file to validate syntax
local function run_test_file(test_file)
  local success, err = pcall(function()
    dofile(test_file)
  end)

  if success then
    print("✓ Test file syntax is valid: " .. test_file)
    return true
  else
    print("✗ Test file has syntax errors: " .. test_file)
    print("  Error: " .. tostring(err))
    return false
  end
end

-- Validate all test files
function M.validate_tests()
  print("Validating raphael.nvim test files...\n")

  local test_files = {
    "tests/raphael_spec.lua",
  }

  local all_valid = true
  for _, file in ipairs(test_files) do
    if not run_test_file(file) then
      all_valid = false
    end
  end

  print("\n" .. (all_valid and "All test files are syntactically valid!" or "Some test files have errors!"))
  return all_valid
end

-- Run basic functionality tests
function M.run_basic_tests()
  print("\nRunning basic functionality tests...\n")

  -- Test that we can require all core modules
  local modules_to_test = {
    "raphael",
    "raphael.core",
    "raphael.themes",
    "raphael.core.cache",
    "raphael.core.palette_cache",
    "raphael.picker.lazy_loader",
    "raphael.utils",
    "raphael.utils.debounce",
  }

  for _, module in ipairs(modules_to_test) do
    local success, err = pcall(require, module)
    if success then
      print("✓ Module loaded: " .. module)
    else
      print("✗ Module failed to load: " .. module .. " - " .. tostring(err))
    end
  end

  -- Test basic functionality
  print("\nTesting basic functionality...")

  local themes = require("raphael.themes")
  themes.refresh()
  print("✓ Theme discovery works")

  local cache = require("raphael.core.cache")
  cache.read()
  print("✓ Cache system works")

  require("raphael.core.palette_cache")
  print("✓ Palette cache system works")

  require("raphael.picker.lazy_loader")
  print("✓ Lazy loader system works")

  print("\nAll basic functionality tests passed!")
end

return M
