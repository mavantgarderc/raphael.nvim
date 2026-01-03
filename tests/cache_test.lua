-- tests/cache_test.lua
-- Unit tests for raphael.nvim cache functionality

local cache = require("raphael.core.cache")

describe("raphael.nvim cache functionality", function()
  -- Test state to use for testing
  local test_theme = "test-cache-theme"
  local test_scope = "__global"

  before_each(function()
    -- Ensure clean state for each test
    cache.clear()
  end)

  describe("state management", function()
    it("should read default state", function()
      local state = cache.read()
      assert.truthy(type(state) == "table")
      assert.truthy(state.bookmarks ~= nil)
      assert.truthy(state.history ~= nil)
      assert.truthy(state.usage ~= nil)
      assert.truthy(state.undo_history ~= nil)
    end)

    it("should write and read state", function()
      local test_state = {
        current = test_theme,
        saved = test_theme,
        bookmarks = { [test_scope] = { test_theme } },
        history = { test_theme },
        usage = { [test_theme] = 5 },
        undo_history = {
          stack = { test_theme },
          index = 1,
          max_size = 10,
        },
      }

      cache.write(test_state)
      local read_state = cache.read()

      assert.equals(test_theme, read_state.current)
      assert.equals(test_theme, read_state.saved)
      assert.truthy(vim.tbl_contains(read_state.history, test_theme))
      assert.equals(5, read_state.usage[test_theme])
      assert.equals(1, read_state.undo_history.index)
    end)
  end)

  describe("bookmarks", function()
    it("should handle bookmark toggling", function()
      -- Initially not bookmarked
      assert.falsy(cache.is_bookmarked(test_theme, test_scope))

      -- Toggle on
      local is_bookmarked = cache.toggle_bookmark(test_theme, test_scope)
      assert.truthy(is_bookmarked)
      assert.truthy(cache.is_bookmarked(test_theme, test_scope))

      -- Toggle off
      local is_bookmarked2, _ = cache.toggle_bookmark(test_theme, test_scope)
      assert.falsy(is_bookmarked2)
      assert.falsy(cache.is_bookmarked(test_theme, test_scope))
    end)

    it("should get bookmarks table", function()
      local bookmarks = cache.get_bookmarks_table()
      assert.truthy(type(bookmarks) == "table")
      assert.truthy(type(bookmarks[test_scope]) == "table")
    end)

    it("should get bookmarks for scope", function()
      cache.toggle_bookmark(test_theme, test_scope)

      local bookmarks = cache.get_bookmarks(test_scope)
      assert.truthy(vim.tbl_contains(bookmarks, test_theme))
    end)
  end)

  describe("history", function()
    it("should add to history", function()
      cache.add_to_history(test_theme)
      local history = cache.get_history()
      assert.truthy(vim.tbl_contains(history, test_theme))
    end)

    it("should maintain history order", function()
      local theme1 = "theme1"
      local theme2 = "theme2"

      cache.add_to_history(theme1)
      cache.add_to_history(theme2)

      local history = cache.get_history()
      assert.equals(theme2, history[1]) -- Most recent first
      assert.equals(theme1, history[2])
    end)

    it("should deduplicate history", function()
      cache.add_to_history(test_theme)
      cache.add_to_history(test_theme)

      local history = cache.get_history()
      local count = 0
      for _, theme in ipairs(history) do
        if theme == test_theme then
          count = count + 1
        end
      end
      assert.equals(1, count) -- Should only appear once
    end)
  end)

  describe("usage tracking", function()
    it("should increment usage", function()
      cache.increment_usage(test_theme)
      local usage = cache.get_usage(test_theme)
      assert.equals(1, usage)

      cache.increment_usage(test_theme)
      local usage2 = cache.get_usage(test_theme)
      assert.equals(2, usage2)
    end)

    it("should get all usage", function()
      cache.increment_usage(test_theme)
      local all_usage = cache.get_all_usage()
      assert.truthy(type(all_usage) == "table")
      assert.equals(1, all_usage[test_theme])
    end)
  end)

  describe("undo history", function()
    it("should push to undo stack", function()
      cache.undo_push(test_theme)
      local state = cache.read()
      assert.truthy(vim.tbl_contains(state.undo_history.stack, test_theme))
      assert.equals(1, state.undo_history.index)
    end)

    it("should pop from undo stack", function()
      cache.undo_push(test_theme)
      local theme = cache.undo_pop()
      assert.equals(test_theme, theme)
    end)

    it("should pop from redo stack", function()
      cache.undo_push(test_theme)
      cache.undo_pop() -- Go back
      local theme = cache.redo_pop()
      assert.equals(test_theme, theme)
    end)
  end)

  describe("auto apply", function()
    it("should get and set auto apply", function()
      assert.falsy(cache.get_auto_apply())

      cache.set_auto_apply(true)
      assert.truthy(cache.get_auto_apply())

      cache.set_auto_apply(false)
      assert.falsy(cache.get_auto_apply())
    end)
  end)

  describe("quick slots", function()
    it("should set and get quick slots", function()
      local slot = "1"
      cache.set_quick_slot(slot, test_theme)

      local retrieved = cache.get_quick_slot(slot)
      assert.equals(test_theme, retrieved)
    end)

    it("should get quick slots table", function()
      local slots = cache.get_quick_slots_table()
      assert.truthy(type(slots) == "table")
      assert.truthy(type(slots[test_scope]) == "table")
    end)

    it("should clear quick slots", function()
      local slot = "2"
      cache.set_quick_slot(slot, test_theme)
      cache.clear_quick_slot(slot)

      local retrieved = cache.get_quick_slot(slot)
      assert.is_nil(retrieved)
    end)
  end)

  describe("collapsed state", function()
    it("should get and set collapsed state", function()
      local group = "test-group"
      assert.falsy(cache.collapsed(group))

      cache.collapsed(group, true)
      assert.truthy(cache.collapsed(group))

      cache.collapsed(group, false)
      assert.falsy(cache.collapsed(group))
    end)
  end)

  describe("sort mode", function()
    it("should get and set sort mode", function()
      assert.equals("alpha", cache.get_sort_mode())

      cache.set_sort_mode("recent")
      assert.equals("recent", cache.get_sort_mode())
    end)
  end)

  describe("clear function", function()
    it("should clear all state", function()
      cache.set_quick_slot("1", test_theme)
      cache.toggle_bookmark(test_theme)
      cache.add_to_history(test_theme)

      cache.clear()

      local state = cache.read()
      assert.is_nil(state.current)
      assert.is_nil(state.saved)
      assert.is_nil(state.previous)
      assert.falsy(state.auto_apply)
      assert.truthy(next(state.bookmarks[test_scope]) == nil)
      assert.truthy(#state.history == 0)
      assert.truthy(next(state.usage) == nil)
      assert.truthy(#state.undo_history.stack == 0)
    end)
  end)
end)
