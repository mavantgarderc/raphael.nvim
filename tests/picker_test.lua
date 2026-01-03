-- tests/picker_test.lua
-- Unit tests for raphael.nvim picker functionality

local picker = require("raphael.picker.ui")
local lazy_loader = require("raphael.picker.lazy_loader")

describe("raphael.nvim picker functionality", function()
  describe("lazy loader", function()
    it("should load render module", function()
      local render = lazy_loader.get_render()
      assert.truthy(render ~= nil)
      assert.truthy(type(render.render) == "function")
    end)

    it("should load search module", function()
      local search = lazy_loader.get_search()
      assert.truthy(search ~= nil)
      assert.truthy(type(search.open) == "function")
    end)

    it("should load preview module", function()
      local preview = lazy_loader.get_preview()
      assert.truthy(preview ~= nil)
      assert.truthy(type(preview.update_palette) == "function")
    end)

    it("should load keymaps module", function()
      local keymaps = lazy_loader.get_keymaps()
      assert.truthy(keymaps ~= nil)
      assert.truthy(type(keymaps.attach) == "function")
    end)

    it("should load bookmarks module", function()
      local bookmarks = lazy_loader.get_bookmarks()
      assert.truthy(bookmarks ~= nil)
      assert.truthy(type(bookmarks.build_set) == "function")
    end)

    it("should provide stats", function()
      local stats = lazy_loader.get_stats()
      assert.truthy(type(stats) == "table")
      assert.truthy(type(stats.loaded_modules_count) == "number")
      assert.truthy(type(stats.loaded_modules) == "table")
    end)
  end)

  describe("picker UI", function()
    it("should have get_cache_stats function", function()
      assert.truthy(type(picker.get_cache_stats) == "function")
    end)

    it("should have get_current_theme function", function()
      assert.truthy(type(picker.get_current_theme) == "function")
    end)

    it("should have update_palette function", function()
      assert.truthy(type(picker.update_palette) == "function")
    end)

    it("should have toggle_debug function", function()
      assert.truthy(type(picker.toggle_debug) == "function")
    end)

    it("should have open function", function()
      assert.truthy(type(picker.open) == "function")
    end)
  end)
end)
