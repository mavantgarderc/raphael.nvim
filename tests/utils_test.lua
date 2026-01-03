-- tests/utils_test.lua
--
-- Unit tests for raphael.nvim utility functions

local utils = require("raphael.utils")
local debounce_utils = require("raphael.utils.debounce")

describe("raphael.nvim utils functionality", function()
  describe("get_all_themes", function()
    it("should return a list of themes", function()
      local themes = utils.get_all_themes()
      assert.truthy(type(themes) == "table")
      -- Themes list can be empty if no themes are installed, so we just check type
    end)
  end)

  describe("get_configured_themes", function()
    it("should handle empty theme_map", function()
      local themes = utils.get_configured_themes({})
      assert.truthy(type(themes) == "table")
      assert.equals(0, #themes)
    end)

    it("should extract themes from theme_map", function()
      local theme_map = {
        group1 = { "theme1", "theme2" },
        single = "theme3",
      }
      local themes = utils.get_configured_themes(theme_map)
      assert.truthy(type(themes) == "table")
      assert.truthy(vim.tbl_contains(themes, "theme1"))
      assert.truthy(vim.tbl_contains(themes, "theme2"))
      assert.truthy(vim.tbl_contains(themes, "theme3"))
    end)
  end)

  describe("flatten_theme_map", function()
    it("should flatten a simple theme_map", function()
      local theme_map = {
        group1 = { "theme1", "theme2" },
        single = "theme3",
      }
      local flattened = utils.flatten_theme_map(theme_map)
      assert.truthy(type(flattened) == "table")

      -- Should have 4 items: 1 header + 2 themes + 1 single theme
      assert.truthy(#flattened >= 3) -- At least 3 items

      -- Find the header
      local header_found = false
      for _, item in ipairs(flattened) do
        if item.name == "group1" and item.is_header then
          header_found = true
          break
        end
      end
      assert.truthy(header_found)
    end)
  end)

  describe("theme_exists", function()
    it("should handle empty theme name", function()
      local exists = utils.theme_exists("")
      assert.falsy(exists)
    end)

    it("should handle nil theme name", function()
      local exists = utils.theme_exists(nil)
      assert.falsy(exists)
    end)
  end)

  describe("safe_colorscheme", function()
    it("should handle empty theme name", function()
      local success, error_msg = utils.safe_colorscheme("")
      assert.falsy(success)
      assert.truthy(error_msg ~= nil)
    end)

    it("should handle nil theme name", function()
      local success, error_msg = utils.safe_colorscheme(nil)
      assert.falsy(success)
      assert.truthy(error_msg ~= nil)
    end)
  end)

  describe("fuzzy_score", function()
    it("should score empty query as 1", function()
      local score = utils.fuzzy_score("anything", "")
      assert.equals(1, score)
    end)

    it("should score exact match high", function()
      local score = utils.fuzzy_score("test", "test")
      assert.truthy(score >= 1000)
    end)

    it("should score prefix match high", function()
      local score = utils.fuzzy_score("testing", "test")
      assert.truthy(score >= 500)
    end)

    it("should score substring match", function()
      local score = utils.fuzzy_score("testing", "est")
      assert.truthy(score >= 250)
    end)

    it("should score no match as 0", function()
      local score = utils.fuzzy_score("test", "xyz")
      assert.equals(0, score)
    end)
  end)

  describe("fuzzy_filter", function()
    it("should handle empty query", function()
      local items = { { name = "test1" }, { name = "test2" } }
      local filtered = utils.fuzzy_filter(items, "")
      assert.equals(#items, #filtered)
    end)

    it("should filter and sort items", function()
      local items = {
        { name = "zeta" },
        { name = "alpha" },
        { name = "beta" },
      }
      local filtered = utils.fuzzy_filter(items, "al")
      assert.truthy(type(filtered) == "table")
      -- Should contain items that match the query
      if #filtered > 0 then
        assert.truthy(filtered[1].name:lower():find("al", 1, true) ~= nil)
      end
    end)
  end)

  describe("deep_copy", function()
    it("should copy simple table", function()
      local original = { a = 1, b = 2 }
      local copy = utils.deep_copy(original)
      assert.equals(original.a, copy.a)
      assert.equals(original.b, copy.b)
      assert.not_equals(original, copy) -- Different objects
    end)

    it("should copy nested table", function()
      local original = { a = { b = { c = 1 } } }
      local copy = utils.deep_copy(original)
      assert.equals(original.a.b.c, copy.a.b.c)
      assert.not_equals(original.a, copy.a) -- Different nested objects
    end)

    it("should copy non-table values directly", function()
      local original = "string"
      local copy = utils.deep_copy(original)
      assert.equals(original, copy)
    end)
  end)

  describe("tbl_contains", function()
    it("should find existing value", function()
      local tbl = { "a", "b", "c" }
      assert.truthy(utils.tbl_contains(tbl, "b"))
    end)

    it("should not find non-existing value", function()
      local tbl = { "a", "b", "c" }
      assert.falsy(utils.tbl_contains(tbl, "d"))
    end)
  end)

  describe("random_theme", function()
    it("should return nil for empty list", function()
      local theme = utils.random_theme({})
      assert.is_nil(theme)
    end)

    it("should return theme from single-item list", function()
      local theme = utils.random_theme({ "only-theme" })
      assert.equals("only-theme", theme)
    end)

    it("should return theme from multi-item list", function()
      local themes = { "theme1", "theme2", "theme3" }
      local theme = utils.random_theme(themes)
      assert.truthy(theme ~= nil)
      assert.truthy(vim.tbl_contains(themes, theme))
    end)
  end)

  describe("clamp", function()
    it("should clamp value below min", function()
      local result = utils.clamp(0, 5, 10)
      assert.equals(5, result)
    end)

    it("should clamp value above max", function()
      local result = utils.clamp(15, 5, 10)
      assert.equals(10, result)
    end)

    it("should not clamp value in range", function()
      local result = utils.clamp(7, 5, 10)
      assert.equals(7, result)
    end)
  end)

  describe("get_picker_dimensions", function()
    it("should calculate dimensions", function()
      local dims = utils.get_picker_dimensions(0.5, 0.5)
      assert.truthy(type(dims) == "table")
      assert.truthy(type(dims.width) == "number")
      assert.truthy(type(dims.height) == "number")
      assert.truthy(type(dims.row) == "number")
      assert.truthy(type(dims.col) == "number")
    end)
  end)

  describe("truncate", function()
    it("should not truncate short string", function()
      local result = utils.truncate("short", 10)
      assert.equals("short", result)
    end)

    it("should truncate long string", function()
      local result = utils.truncate("very long string", 5)
      assert.equals("very…", result)
    end)
  end)

  describe("pad_right", function()
    it("should pad short string", function()
      local result = utils.pad_right("hi", 5)
      assert.equals("hi   ", result)
    end)

    it("should not pad long string", function()
      local result = utils.pad_right("hello", 3)
      assert.equals("hello", result)
    end)
  end)

  describe("notify", function()
    it("should handle basic notification", function()
      -- Just test that it doesn't error
      local success = pcall(utils.notify, "test message", vim.log.levels.INFO)
      assert.truthy(success)
    end)
  end)
end)

describe("raphael.nvim debounce utilities", function()
  describe("debounce function", function()
    it("should create a debounced function", function()
      local call_count = 0
      local test_fn = function()
        call_count = call_count + 1
      end

      local debounced_fn = debounce_utils.debounce(test_fn, 10) -- 10ms delay

      -- Call multiple times quickly
      for _ = 1, 5 do
        debounced_fn()
      end

      -- Wait for debounce to complete
      vim.wait(50, function()
        return call_count >= 1
      end, 100)

      -- Should have been called at least once
      assert.truthy(call_count >= 1)
    end)
  end)

  describe("throttle function", function()
    it("should create a throttled function", function()
      local call_count = 0
      local test_fn = function()
        call_count = call_count + 1
      end

      local throttled_fn = debounce_utils.throttle(test_fn, 10) -- 10ms delay

      -- Call multiple times quickly
      for _ = 1, 5 do
        throttled_fn()
      end

      -- Wait for throttle to complete
      vim.wait(50, function()
        return call_count >= 1
      end, 100)

      -- Should have been called at least once
      assert.truthy(call_count >= 1)
    end)
  end)
end)
