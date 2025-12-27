-- Test script for raphael.nvim performance improvements
-- This script tests the new caching and debouncing functionality

local function test_palette_cache()
  print("Testing palette cache functionality...")

  local palette_cache = require("raphael.core.palette_cache")

  -- Test generating palette data
  local test_theme = "default" -- Use a basic theme that should always exist
  local palette_data = palette_cache.generate_palette_data(test_theme)

  if palette_data then
    print("✓ Successfully generated palette data for theme: " .. test_theme)
    print("  Highlight groups found: " .. vim.inspect(vim.tbl_keys(palette_data)))
  else
    print("✗ Failed to generate palette data for theme: " .. test_theme)
  end

  -- Test caching
  ---@diagnostic disable-next-line: param-type-mismatch
  palette_cache.cache_palette(test_theme, palette_data)
  local cached_data = palette_cache.get_cached_palette(test_theme)

  if cached_data then
    print("✓ Successfully cached and retrieved palette data")
  else
    print("✗ Failed to retrieve cached palette data")
  end

  -- Test cache statistics
  local stats = palette_cache.get_stats()
  print("✓ Cache statistics: " .. vim.inspect(stats))
end

local function test_debounce()
  print("\nTesting debounce functionality...")

  local debounce_utils = require("raphael.utils.debounce")
  local test_count = 0

  -- Create a debounced function
  local debounced_fn = debounce_utils.debounce(function()
    test_count = test_count + 1
  end, 50) -- 50ms delay

  -- Call the function multiple times quickly
  ---@diagnostic disable-next-line: unused-local
  for i = 1, 5 do
    debounced_fn()
  end

  print("✓ Debounced function called 5 times rapidly")
  print("  Expected execution count after delay: 1")
  print("  (Actual count will be checked after delay)")

  -- Wait and check result
  vim.defer_fn(function()
    print("  Actual execution count: " .. test_count)
    if test_count == 1 then
      print("✓ Debounce working correctly")
    else
      print("✗ Debounce not working as expected")
    end
  end, 100) -- Wait 100ms to ensure debounce has completed
end

-- Run tests
print("Starting performance improvement tests for raphael.nvim...\n")
test_palette_cache()
test_debounce()

print("\nTests initiated. Check results after delays for debounce test.")

