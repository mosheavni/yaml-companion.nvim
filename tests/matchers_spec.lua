local eq = assert.are.same

describe("matchers module:", function()
  local matchers

  before_each(function()
    -- Reset the matchers module
    package.loaded["yaml-companion._matchers"] = nil
    matchers = require("yaml-companion._matchers")
  end)

  describe("_loaded", function()
    it("should start empty", function()
      eq({}, matchers._loaded)
    end)
  end)

  describe("load", function()
    it("should load builtin kubernetes matcher", function()
      local kubernetes = matchers.load("kubernetes")

      assert.is_not_nil(kubernetes)
      assert.is_not_nil(kubernetes.match)
      assert.is_not_nil(kubernetes.handles)
      assert.is_not_nil(kubernetes.health)
    end)

    it("should load builtin cloud_init matcher", function()
      local cloud_init = matchers.load("cloud_init")

      assert.is_not_nil(cloud_init)
      assert.is_not_nil(cloud_init.match)
    end)

    it("should add loaded matcher to _loaded table", function()
      matchers.load("kubernetes")

      assert.is_not_nil(matchers._loaded.kubernetes)
      assert.is_not_nil(matchers._loaded.kubernetes.match)
    end)

    it("should load external matchers from _matchers namespace", function()
      -- The dummy matcher is loaded via the minimal_init.vim
      local dummy = matchers.load("dummy")

      assert.is_not_nil(dummy)
      assert.is_not_nil(dummy.match)
      assert.is_not_nil(dummy.handles)
    end)

    it("should error on non-existent matcher", function()
      local ok, err = pcall(function()
        matchers.load("nonexistent_matcher_xyz")
      end)

      eq(false, ok)
      assert.is_true(err:match("doesn't exist") ~= nil)
    end)

    it("should return the same matcher when loaded multiple times", function()
      local first = matchers.load("kubernetes")
      local second = matchers.load("kubernetes")

      eq(first, second)
    end)
  end)

  describe("manager metatable", function()
    it("should lazy load matchers on access", function()
      -- Clear loaded matchers
      matchers._loaded = {}

      -- Access through manager should trigger load
      local kubernetes = matchers.manager.kubernetes

      assert.is_not_nil(kubernetes)
      assert.is_not_nil(kubernetes.match)
    end)

    it("should provide default health function if not defined", function()
      local dummy = matchers.manager.dummy

      assert.is_not_nil(dummy.health)
      -- Should be callable without error
      dummy.health()
    end)

    it("should provide default match function if not defined", function()
      -- This tests the fallback behavior - our dummy has match defined
      -- but the manager ensures a function exists
      local dummy = matchers.manager.dummy

      assert.is_not_nil(dummy.match)
      assert.is_function(dummy.match)
    end)

    it("should provide default handles function if not defined", function()
      local dummy = matchers.manager.dummy

      assert.is_not_nil(dummy.handles)
      assert.is_function(dummy.handles)
    end)

    it("should cache matchers after first access", function()
      -- Clear to ensure fresh state
      matchers.manager.kubernetes = nil

      local first_access = matchers.manager.kubernetes
      local second_access = matchers.manager.kubernetes

      eq(first_access, second_access)
    end)
  end)

  describe("matcher interface", function()
    it("kubernetes matcher should implement required interface", function()
      local kubernetes = matchers.load("kubernetes")

      -- match should be a function
      assert.is_function(kubernetes.match)

      -- handles should return array of schemas
      local schemas = kubernetes.handles()
      assert.is_table(schemas)
      assert.is_true(#schemas > 0)

      -- Each schema should have name and uri
      for _, schema in ipairs(schemas) do
        assert.is_not_nil(schema.name)
        assert.is_not_nil(schema.uri)
      end
    end)

    it("dummy matcher should implement required interface", function()
      local dummy = matchers.load("dummy")

      assert.is_function(dummy.match)

      local schemas = dummy.handles()
      assert.is_table(schemas)
      assert.is_true(#schemas > 0)

      eq("dummy", schemas[1].name)
      eq("dummy", schemas[1].uri)
    end)
  end)

  describe("matcher behavior", function()
    local bufnr

    before_each(function()
      bufnr = vim.api.nvim_create_buf(false, true)
    end)

    after_each(function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end)

    it("dummy matcher should match test: true", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "test: true",
        "other: value",
      })

      local dummy = matchers.load("dummy")
      local result = dummy.match(bufnr)

      assert.is_not_nil(result)
      eq("dummy", result.name)
    end)

    it("dummy matcher should not match without test: true", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "foo: bar",
        "baz: qux",
      })

      local dummy = matchers.load("dummy")
      local result = dummy.match(bufnr)

      eq(nil, result)
    end)
  end)
end)
