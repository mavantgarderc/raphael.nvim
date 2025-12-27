-- tests/core_test.lua
-- Unit tests for raphael.nvim core functionality

local core = require("raphael.core")
local themes = require("raphael.themes")
local cache = require("raphael.core.cache")

describe("raphael.nvim core functionality", function()
  -- Setup function to run before each test
  local original_state = nil
  setup(function()
    -- Save original state
    original_state = cache.read()
  end)

  -- Teardown function to run after each test
  teardown(function()
    -- Restore original state
    if original_state then
      cache.write(original_state)
    end
  end)

  describe("theme discovery", function()
    it("should discover installed themes", function()
      themes.refresh()
      local installed = themes.installed
      assert.truthy(type(installed) == "table")
      assert.truthy(next(installed) ~= nil) -- Should have at least one theme
    end)

    it("should check if a theme is available", function()
      themes.refresh()
      local all_themes = themes.get_all_themes()
      if #all_themes > 0 then
        local first_theme = all_themes[1]
        assert.truthy(themes.is_available(first_theme))
      end
    end)

    it("should get all configured themes", function()
      themes.theme_map = { test_theme = { "default" } }
      local all_themes = themes.get_all_themes()
      assert.truthy(vim.tbl_contains(all_themes, "default"))
    end)
  end)

  describe("configuration validation", function()
    it("should validate default configuration", function()
      local config = require("raphael.config")
      local validated = config.validate(nil)
      assert.truthy(type(validated) == "table")
      assert.truthy(validated.default_theme ~= nil)
      assert.truthy(validated.leader ~= nil)
    end)

    it("should handle user overrides", function()
      local config = require("raphael.config")
      local user_config = {
        default_theme = "test-theme",
        leader = "<leader>tt",
      }
      local validated = config.validate(user_config)
      assert.equals("test-theme", validated.default_theme)
      assert.equals("<leader>tt", validated.leader)
    end)
  end)

  describe("core state management", function()
    it("should initialize with default state", function()
      local state = core.state
      assert.truthy(type(state) == "table")
      assert.truthy(state.bookmarks ~= nil)
      assert.truthy(state.history ~= nil)
      assert.truthy(state.usage ~= nil)
    end)

    it("should have working setup function", function()
      -- Test that setup doesn't error with minimal config
      local success, err = pcall(core.setup, { default_theme = "default" })
      assert.truthy(success, "Setup should not error: " .. tostring(err))
    end)
  end)

  describe("cache functionality", function()
    it("should read and write state", function()
      local test_state = {
        current = "test-theme",
        bookmarks = { __global = { "test-theme" } },
        history = { "test-theme" },
        usage = { ["test-theme"] = 1 },
      }

      cache.write(test_state)
      local read_state = cache.read()

      assert.equals("test-theme", read_state.current)
      assert.truthy(vim.tbl_contains(read_state.history, "test-theme"))
      assert.equals(1, read_state.usage["test-theme"])
    end)

    it("should handle bookmark toggling", function()
      local theme = "test-bookmark-theme"
      local scope = "__global"

      -- Initially should not be bookmarked
      local is_bookmarked = cache.is_bookmarked(theme, scope)
      assert.falsy(is_bookmarked)

      -- Toggle on
      local new_state = cache.toggle_bookmark(theme, scope)
      assert.truthy(new_state)

      -- Should now be bookmarked
      is_bookmarked = cache.is_bookmarked(theme, scope)
      assert.truthy(is_bookmarked)

      -- Toggle off
      local new_state2, _ = cache.toggle_bookmark(theme, scope)
      assert.falsy(new_state2)
    end)

    it("should handle history", function()
      local theme = "test-history-theme"

      cache.add_to_history(theme)
      local history = cache.get_history()

      assert.truthy(vim.tbl_contains(history, theme))
    end)

    it("should handle usage counts", function()
      local theme = "test-usage-theme"

      cache.increment_usage(theme)
      local count = cache.get_usage(theme)

      assert.equals(1, count)

      cache.increment_usage(theme)
      local count2 = cache.get_usage(theme)

      assert.equals(2, count2)
    end)
  end)

  describe("theme application", function()
    it("should have apply function", function()
      assert.truthy(type(core.apply) == "function")
    end)

    it("should have toggle_auto function", function()
      assert.truthy(type(core.toggle_auto) == "function")
    end)

    it("should have toggle_bookmark function", function()
      assert.truthy(type(core.toggle_bookmark) == "function")
    end)
  end)

  describe("picker functionality", function()
    it("should have open_picker function", function()
      assert.truthy(type(core.open_picker) == "function")
    end)

    it("should have get_current_theme function", function()
      assert.truthy(type(core.get_current_theme) == "function")
    end)
  end)
end)
