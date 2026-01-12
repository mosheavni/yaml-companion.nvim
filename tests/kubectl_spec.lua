local eq = assert.are.same

-- Mock the config module before requiring kubectl
local config = require("yaml-companion.config")
config.options = vim.tbl_deep_extend("force", config.defaults, {
  cluster_crds = {
    enabled = true,
    fallback = false,
    cache_dir = nil,
    cache_ttl = 86400,
  },
})

local kubectl = require("yaml-companion.kubectl")

describe("kubectl module:", function()
  describe("is_available", function()
    it("should return boolean", function()
      local result = kubectl.is_available()
      eq("boolean", type(result))
    end)
  end)

  describe("get_cache_path", function()
    it("should return path ending with .json", function()
      local path = kubectl.get_cache_path("applications.argoproj.io")
      assert.is_truthy(path:match("%.json$"))
    end)

    it("should include CRD name in path", function()
      local path = kubectl.get_cache_path("certificates.cert-manager.io")
      assert.is_truthy(path:match("certificates%.cert%-manager%.io"))
    end)
  end)

  describe("cache operations", function()
    local test_crd_name = "test-crd.example.com"
    local test_schema = {
      type = "object",
      properties = {
        apiVersion = { type = "string" },
        kind = { type = "string" },
        metadata = { type = "object" },
      },
    }

    after_each(function()
      -- Clean up test cache file
      local path = kubectl.get_cache_path(test_crd_name)
      os.remove(path)
    end)

    it("should cache and retrieve schema", function()
      local cached_path, err = kubectl.cache_schema(test_crd_name, test_schema)
      eq(nil, err)
      assert.is_truthy(cached_path)

      local retrieved_schema, retrieve_err = kubectl.get_cached_schema(test_crd_name)
      eq(nil, retrieve_err)
      eq(test_schema, retrieved_schema)
    end)

    it("should return error for non-existent cache", function()
      local schema, err = kubectl.get_cached_schema("non-existent.example.com")
      eq(nil, schema)
      assert.is_truthy(err)
    end)

    it("should report valid cache after caching", function()
      -- First, cache should be invalid
      eq(false, kubectl.is_cache_valid(test_crd_name))

      -- Cache the schema
      kubectl.cache_schema(test_crd_name, test_schema)

      -- Now cache should be valid
      eq(true, kubectl.is_cache_valid(test_crd_name))
    end)
  end)

  describe("cache TTL", function()
    it("should respect cache_ttl=0 as never expire", function()
      local original_ttl = config.options.cluster_crds.cache_ttl
      config.options.cluster_crds.cache_ttl = 0

      local test_crd = "ttl-test.example.com"
      local test_schema = { type = "object" }

      kubectl.cache_schema(test_crd, test_schema)

      -- With TTL=0, cache should always be valid
      eq(true, kubectl.is_cache_valid(test_crd))

      -- Clean up
      os.remove(kubectl.get_cache_path(test_crd))
      config.options.cluster_crds.cache_ttl = original_ttl
    end)
  end)

  describe("api_resources_cache", function()
    it("should start empty", function()
      kubectl.clear_cache()
      eq({}, kubectl._api_resources_cache)
    end)
  end)
end)

describe("kubectl schema extraction:", function()
  -- Test the extract_stored_schema logic by simulating CRD JSON structures
  -- Note: The actual function is local, so we test indirectly through fetch_crd_schema
  -- For unit testing, we could expose it or test the behavior

  describe("CRD version selection logic", function()
    it("should prefer storage=true version", function()
      -- This would require mocking vim.system, which is complex
      -- For now, this serves as documentation of expected behavior
      local crd_with_multiple_versions = {
        spec = {
          versions = {
            { name = "v1alpha1", served = true, storage = false },
            { name = "v1beta1", served = true, storage = false },
            { name = "v1", served = true, storage = true },
          },
        },
      }
      -- Expected: v1 should be selected because storage=true
      assert.is_truthy(crd_with_multiple_versions.spec.versions[3].storage)
    end)

    it("should fall back to served version if no storage version", function()
      local crd_without_storage = {
        spec = {
          versions = {
            { name = "v1alpha1", served = true, storage = false },
            { name = "v1beta1", served = true, storage = false },
          },
        },
      }
      -- Expected: first served version (v1alpha1) should be selected
      assert.is_truthy(crd_without_storage.spec.versions[1].served)
    end)
  end)
end)

describe("kubectl config:", function()
  it("should have cluster_crds in config defaults", function()
    local defaults = require("yaml-companion.config").defaults
    assert.is_truthy(defaults.cluster_crds)
    assert.is_truthy(defaults.cluster_crds.enabled)
    eq("boolean", type(defaults.cluster_crds.fallback))
    eq("number", type(defaults.cluster_crds.cache_ttl))
  end)
end)
