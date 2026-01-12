local eq = assert.are.same

describe("schema module functions:", function()
  local schema
  local config
  local matchers

  before_each(function()
    -- Reset modules in the right order - schema imports matchers._loaded at load time
    package.loaded["yaml-companion.schema"] = nil
    package.loaded["yaml-companion.config"] = nil
    package.loaded["yaml-companion._matchers"] = nil
    package.loaded["yaml-companion.lsp.requests"] = nil

    config = require("yaml-companion.config")
    matchers = require("yaml-companion._matchers")
    -- Load schema AFTER matchers is set up
    schema = require("yaml-companion.schema")
  end)

  describe("default", function()
    it("should return a schema with name 'none'", function()
      local result = schema.default()
      eq("none", result.name)
    end)

    it("should return a schema with uri 'none'", function()
      local result = schema.default()
      eq("none", result.uri)
    end)

    it("should return the same object each time", function()
      local first = schema.default()
      local second = schema.default()
      eq(first.name, second.name)
      eq(first.uri, second.uri)
    end)
  end)

  describe("from_options", function()
    it("should return empty array when no schemas configured", function()
      config.options.schemas = {}
      local result = schema.from_options()
      eq({}, result)
    end)

    it("should return user-defined schemas (new format)", function()
      config.options.schemas = {
        { name = "Schema A", uri = "https://example.com/a.json" },
        { name = "Schema B", uri = "https://example.com/b.json" },
      }

      local result = schema.from_options()

      eq(2, #result)
      eq("Schema A", result[1].name)
      eq("https://example.com/a.json", result[1].uri)
    end)

    it("should return user-defined schemas (legacy format)", function()
      -- Note: Legacy format triggers a log.warn, so we mock the log module first
      -- Save original and mock
      local original_log = package.loaded["yaml-companion.log"]
      package.loaded["yaml-companion.log"] = { warn = function() end }

      -- Reload schema to pick up the mock
      package.loaded["yaml-companion.schema"] = nil
      schema = require("yaml-companion.schema")

      config.options.schemas = {
        result = {
          { name = "Legacy Schema", uri = "https://example.com/legacy.json" },
        },
      }

      local result = schema.from_options()

      -- Restore original log
      package.loaded["yaml-companion.log"] = original_log

      eq(1, #result)
      eq("Legacy Schema", result[1].name)
    end)

    it("should filter out schemas without uri", function()
      config.options.schemas = {
        { name = "Valid", uri = "https://example.com/valid.json" },
        { name = "Invalid without URI" },
      }

      local result = schema.from_options()

      -- Only the valid schema should be included
      eq(1, #result)
      eq("Valid", result[1].name)
    end)

    it("should include all valid schemas", function()
      config.options.schemas = {
        { name = "Valid", uri = "https://example.com/valid.json" },
        { name = "Also Valid", uri = "https://example.com/also.json" },
      }

      local result = schema.from_options()

      eq(2, #result)
    end)
  end)

  describe("from_matchers", function()
    it("should return empty array when no matchers loaded", function()
      -- Need to reload schema with empty matchers
      package.loaded["yaml-companion.schema"] = nil
      matchers._loaded = {}
      schema = require("yaml-companion.schema")

      local result = schema.from_matchers()
      eq({}, result)
    end)

    it("should return schemas from loaded matchers", function()
      -- Load matcher before loading schema module (schema captures _loaded at load time)
      package.loaded["yaml-companion.schema"] = nil
      matchers._loaded = {}
      matchers.load("kubernetes")
      schema = require("yaml-companion.schema")

      local result = schema.from_matchers()

      assert.is_true(#result > 0)

      -- Should contain Kubernetes schema
      local found_kubernetes = false
      for _, s in ipairs(result) do
        if s.name == "Kubernetes" then
          found_kubernetes = true
          break
        end
      end
      assert.is_true(found_kubernetes)
    end)

    it("should work with matchers that have handles function", function()
      -- Load matchers before loading schema module
      package.loaded["yaml-companion.schema"] = nil
      package.loaded["yaml-companion._matchers"] = nil

      matchers = require("yaml-companion._matchers")
      matchers.load("kubernetes")
      schema = require("yaml-companion.schema")

      local result = schema.from_matchers()

      -- Should have Kubernetes schema
      local found_kubernetes = false

      for _, s in ipairs(result) do
        if s.name == "Kubernetes" then
          found_kubernetes = true
          break
        end
      end

      assert.is_true(found_kubernetes)
    end)

    it("should handle matchers without handles function gracefully", function()
      -- Load matchers before loading schema module
      package.loaded["yaml-companion.schema"] = nil
      package.loaded["yaml-companion._matchers"] = nil

      matchers = require("yaml-companion._matchers")
      -- cloud_init doesn't define handles(), so it gets a default empty one
      matchers.load("cloud_init")
      schema = require("yaml-companion.schema")

      local result = schema.from_matchers()

      -- cloud_init returns empty from handles, so result should be empty or contain nothing from cloud_init
      -- This is fine - matchers without handles just don't contribute schemas to the list
      assert.is_table(result)
    end)
  end)

  describe("all", function()
    it("should return a table", function()
      local result = schema.all()
      assert.is_table(result)
    end)

    it("should include user-defined schemas from options", function()
      config.options.schemas = {
        { name = "User Schema", uri = "https://example.com/user.json" },
      }

      local result = schema.all()

      -- Should contain user schema
      local found_user = false

      for _, s in ipairs(result) do
        if s.name == "User Schema" then
          found_user = true
          break
        end
      end

      assert.is_true(found_user)
    end)
  end)
end)

describe("schema validation:", function()
  local schema
  local config

  before_each(function()
    package.loaded["yaml-companion.schema"] = nil
    package.loaded["yaml-companion.config"] = nil
    package.loaded["yaml-companion._matchers"] = nil
    package.loaded["yaml-companion.lsp.requests"] = nil

    config = require("yaml-companion.config")
    local matchers = require("yaml-companion._matchers")
    matchers._loaded = {}
    schema = require("yaml-companion.schema")
  end)

  it("should accept schema with name and uri", function()
    config.options.schemas = {
      { name = "Valid", uri = "https://example.com/schema.json" },
    }

    local result = schema.from_options()
    eq(1, #result)
  end)

  it("should accept schema with empty uri (empty string is truthy in Lua)", function()
    config.options.schemas = {
      { name = "WithEmptyUri", uri = "" },
    }

    local result = schema.from_options()
    -- Empty string is truthy in Lua, so this passes validation
    eq(1, #result)
  end)

  it("should accept schema with only uri (no name)", function()
    config.options.schemas = {
      { uri = "https://example.com/schema.json" },
    }

    local result = schema.from_options()
    eq(1, #result)
  end)

  it("should handle mixed valid and invalid schemas", function()
    config.options.schemas = {
      { name = "Valid 1", uri = "https://example.com/1.json" },
      { name = "Invalid" },
      { name = "Valid 2", uri = "https://example.com/2.json" },
      {},
      { name = "Valid 3", uri = "https://example.com/3.json" },
    }

    local result = schema.from_options()
    eq(3, #result)
  end)
end)
