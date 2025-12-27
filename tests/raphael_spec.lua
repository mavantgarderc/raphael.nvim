-- tests/raphael_spec.lua
-- Main test suite for raphael.nvim using plenary.nvim test runner

-- Only require plenary if we're in a test environment
local success, async = pcall(require, "plenary.async")
local async_fn

if success then
  async_fn = async.tests
else
  -- Provide mock functions for basic validation
  async_fn = {
    describe = function(desc, fn)
      print("Testing: " .. desc)
      fn()
    end,
    it = function(desc, fn)
      local test_success, err = pcall(fn)
      if test_success then
        print("  ✓ " .. desc)
      else
        print("  ✗ " .. desc .. " - " .. tostring(err))
      end
    end,
    setup = function(fn)
      fn()
    end,
  }
end

-- Test core functionality
async_fn.describe("raphael core functionality", function()
  local themes = require("raphael.themes")
  local cache = require("raphael.core.cache")

  async_fn.it("should have working theme discovery", function()
    themes.refresh()
    local installed = themes.installed
    assert(type(installed) == "table")
  end)

  async_fn.it("should validate configuration properly", function()
    local config = require("raphael.config")
    local validated = config.validate(nil)
    assert(type(validated) == "table")
    assert(validated.default_theme ~= nil)
  end)

  async_fn.it("should have working cache system", function()
    local test_state = {
      current = "test-theme",
      bookmarks = { __global = { "test-theme" } },
    }
    cache.write(test_state)
    local read_state = cache.read()
    assert(read_state.current == "test-theme")
  end)

  async_fn.it("should handle bookmark toggling", function()
    local theme = "test-bookmark-theme"
    local scope = "__global"

    -- Initially should not be bookmarked
    local is_bookmarked = cache.is_bookmarked(theme, scope)
    assert(not is_bookmarked)

    -- Toggle on
    local new_state = cache.toggle_bookmark(theme, scope)
    assert(new_state)

    -- Should now be bookmarked
    is_bookmarked = cache.is_bookmarked(theme, scope)
    assert(is_bookmarked)
  end)
end)

-- Test picker functionality
async_fn.describe("raphael picker functionality", function()
  local lazy_loader = require("raphael.picker.lazy_loader")

  async_fn.it("should load picker modules lazily", function()
    local render = lazy_loader.get_render()
    assert(render ~= nil)
    assert(type(render.render) == "function")

    local search = lazy_loader.get_search()
    assert(search ~= nil)
    assert(type(search.open) == "function")

    local preview = lazy_loader.get_preview()
    assert(preview ~= nil)
    assert(type(preview.update_palette) == "function")

    local keymaps = lazy_loader.get_keymaps()
    assert(keymaps ~= nil)
    assert(type(keymaps.attach) == "function")

    local bookmarks = lazy_loader.get_bookmarks()
    assert(bookmarks ~= nil)
    assert(type(bookmarks.build_set) == "function")
  end)

  async_fn.it("should provide lazy loader stats", function()
    local stats = lazy_loader.get_stats()
    assert(type(stats) == "table")
    assert(type(stats.loaded_modules_count) == "number")
  end)
end)

-- Test cache functionality
async_fn.describe("raphael cache functionality", function()
  local cache = require("raphael.core.cache")
  local test_theme = "test-cache-theme"

  async_fn.setup(function()
    -- Clean state before tests
    cache.clear()
  end)

  async_fn.it("should read default state", function()
    local state = cache.read()
    assert(type(state) == "table")
    assert(state.bookmarks ~= nil)
    assert(state.history ~= nil)
  end)

  async_fn.it("should handle history operations", function()
    cache.add_to_history(test_theme)
    local history = cache.get_history()
    assert(vim.tbl_contains(history, test_theme))
  end)

  async_fn.it("should handle usage tracking", function()
    cache.increment_usage(test_theme)
    local usage = cache.get_usage(test_theme)
    assert(usage == 1)
  end)

  async_fn.it("should handle undo operations", function()
    cache.undo_push(test_theme)
    local theme = cache.undo_pop()
    assert(theme == test_theme)
  end)
end)

-- Test palette cache functionality
async_fn.describe("raphael palette cache functionality", function()
  local palette_cache = require("raphael.core.palette_cache")
  local test_theme = "default" -- Use default theme which should exist

  async_fn.it("should generate palette data", function()
    local palette_data = palette_cache.generate_palette_data(test_theme)
    assert(palette_data ~= nil)
    assert(type(palette_data) == "table")
  end)

  async_fn.it("should cache and retrieve palette data", function()
    local palette_data = palette_cache.generate_palette_data(test_theme)
    assert(palette_data ~= nil)

    -- Cache the data
    palette_cache.cache_palette(test_theme, palette_data)

    -- Retrieve from cache
    local cached_data = palette_cache.get_cached_palette(test_theme)
    assert(cached_data ~= nil)
  end)

  async_fn.it("should get palette with caching", function()
    local palette_data = palette_cache.get_palette_with_cache(test_theme)
    assert(palette_data ~= nil)
    assert(type(palette_data) == "table")
  end)

  async_fn.it("should provide cache stats", function()
    local stats = palette_cache.get_stats()
    assert(type(stats) == "table")
    assert(type(stats.total_entries) == "number")
  end)
end)

-- Test utils functionality
async_fn.describe("raphael utils functionality", function()
  local utils = require("raphael.utils")

  async_fn.it("should handle fuzzy scoring", function()
    local score1 = utils.fuzzy_score("testing", "test")
    assert(score1 >= 500) -- Should be high for prefix match

    local score2 = utils.fuzzy_score("anything", "")
    assert(score2 == 1) -- Empty query should score 1
  end)

  async_fn.it("should handle deep copy", function()
    local original = { a = { b = { c = 1 } } }
    local copy = utils.deep_copy(original)
    assert(original.a.b.c == copy.a.b.c)
    assert(original ~= copy) -- Different objects
  end)

  async_fn.it("should handle table contains", function()
    local tbl = { "a", "b", "c" }
    assert(utils.tbl_contains(tbl, "b"))
    assert(not utils.tbl_contains(tbl, "d"))
  end)

  async_fn.it("should handle random theme selection", function()
    local empty_result = utils.random_theme({})
    assert(empty_result == nil)

    local single_result = utils.random_theme({ "only-theme" })
    assert(single_result == "only-theme")

    local multi_result = utils.random_theme({ "theme1", "theme2" })
    assert(multi_result ~= nil)
  end)
end)
