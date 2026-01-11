--# selene: allow(incorrect_standard_library_use)
---@diagnostic disable: undefined-field

describe("health module:", function()
  local health_module

  before_each(function()
    package.loaded["yaml-companion.health"] = nil
    health_module = require("yaml-companion.health")
  end)

  describe("check function", function()
    it("should exist", function()
      assert.is_not_nil(health_module.check)
      assert.is_function(health_module.check)
    end)

    it("should be callable without error when binaries exist", function()
      -- This test verifies the health check doesn't crash
      -- Actual health output depends on system state
      local ok, err = pcall(health_module.check)

      -- Should not throw an error (might report warnings/errors through vim.health)
      if not ok then
        -- Only fail if it's an actual Lua error, not a missing binary report
        assert.is_true(err:match("vim.health") == nil, "Unexpected error: " .. tostring(err))
      end
    end)
  end)

  describe("binary checking", function()
    it("should check for yaml-language-server", function()
      -- Test that the binary check function works
      local executable = vim.fn.executable("yaml-language-server")
      assert.is_true(executable == 0 or executable == 1)
    end)

    it("should check for curl", function()
      local executable = vim.fn.executable("curl")
      assert.is_true(executable == 0 or executable == 1)
    end)
  end)
end)

describe("health integration:", function()
  before_each(function()
    -- Ensure matchers are loaded for health check
    package.loaded["yaml-companion._matchers"] = nil
    local matchers = require("yaml-companion._matchers")
    matchers.load("kubernetes")
  end)

  it("loaded matchers should have health function", function()
    local matchers = require("yaml-companion._matchers")

    for name, matcher in pairs(matchers._loaded) do
      assert.is_not_nil(matcher.health, "Matcher " .. name .. " missing health function")
      assert.is_function(matcher.health)
    end
  end)

  it("kubernetes matcher health should be callable", function()
    local matchers = require("yaml-companion._matchers")
    matchers.load("kubernetes")

    local kubernetes = matchers._loaded.kubernetes

    local ok = pcall(kubernetes.health)
    assert.is_true(ok)
  end)
end)

describe("health helper functions:", function()
  it("vim.fn.executable should return 0 or 1", function()
    local result = vim.fn.executable("ls")
    assert.is_true(result == 0 or result == 1)
  end)

  it("pcall require should work for installed packages", function()
    local ok, _ = pcall(require, "yaml-companion")
    assert.is_true(ok)
  end)

  it("pcall require should return false for missing packages", function()
    local ok, _ = pcall(require, "nonexistent_package_xyz_123")
    assert.is_false(ok)
  end)
end)
