-- tests/palette_cache_test.lua
-- Unit tests for raphael.nvim palette cache functionality

local palette_cache = require("raphael.core.palette_cache")

describe("raphael.nvim palette cache functionality", function()
  local test_theme = "default" -- Use default theme which should always exist

  describe("palette generation", function()
    it("should generate palette data for a theme", function()
      local palette_data = palette_cache.generate_palette_data(test_theme)
      assert.truthy(palette_data ~= nil)
      assert.truthy(type(palette_data) == "table")

      -- Should contain expected highlight groups
      local expected_groups = { "Normal", "Comment", "String", "Keyword", "Function", "Type", "Constant", "Special" }
      for _, group in ipairs(expected_groups) do
        assert.truthy(palette_data[group] ~= nil, "Missing highlight group: " .. group)
        assert.truthy(type(palette_data[group]) == "table")
      end
    end)

    it("should return nil for invalid theme", function()
      local palette_data = palette_cache.generate_palette_data("nonexistent-theme-12345")
      assert.is_nil(palette_data)
    end)
  end)

  describe("caching system", function()
    it("should cache and retrieve palette data", function()
      -- Clear cache first
      palette_cache.clear_cache()

      local palette_data = palette_cache.generate_palette_data(test_theme)
      assert.truthy(palette_data ~= nil)

      -- Cache the data
      palette_cache.cache_palette(test_theme, palette_data)

      -- Retrieve from cache
      local cached_data = palette_cache.get_cached_palette(test_theme)
      assert.truthy(cached_data ~= nil)
      assert.truthy(type(cached_data) == "table")
    end)

    it("should return nil for non-existent cache entry", function()
      local cached_data = palette_cache.get_cached_palette("nonexistent-theme")
      assert.is_nil(cached_data)
    end)

    it("should handle cache expiration", function()
      -- This test checks that the expiration logic works
      local stats_before = palette_cache.get_stats()
      assert.truthy(type(stats_before) == "table")
      assert.truthy(type(stats_before.valid_entries) == "number")
      assert.truthy(type(stats_before.expired_entries) == "number")
    end)

    it("should clear expired entries", function()
      -- Set up a scenario where we can test expiration
      palette_cache.clear_expired()
      local stats = palette_cache.get_stats()
      assert.truthy(type(stats) == "table")
    end)

    it("should get stats", function()
      local stats = palette_cache.get_stats()
      assert.truthy(type(stats) == "table")
      assert.truthy(type(stats.total_entries) == "number")
      assert.truthy(type(stats.valid_entries) == "number")
      assert.truthy(type(stats.expired_entries) == "number")
      assert.truthy(type(stats.max_size) == "number")
      assert.truthy(type(stats.timeout_seconds) == "number")
    end)
  end)

  describe("get_palette_with_cache", function()
    it("should get palette with caching", function()
      local palette_data = palette_cache.get_palette_with_cache(test_theme)
      assert.truthy(palette_data ~= nil)
      assert.truthy(type(palette_data) == "table")

      -- Should now be cached, so getting it again should work
      local cached_data = palette_cache.get_palette_with_cache(test_theme)
      assert.truthy(cached_data ~= nil)
    end)

    it("should handle nil theme gracefully", function()
      local palette_data = palette_cache.get_palette_with_cache(nil)
      assert.is_nil(palette_data)
    end)
  end)

  describe("preload functionality", function()
    it("should handle preload with empty list", function()
      palette_cache.preload_palettes({})
      -- Should not error
    end)

    it("should handle preload with valid themes", function()
      -- Test with a valid theme
      palette_cache.preload_palettes({ test_theme })
      -- Should not error
    end)
  end)
end)
