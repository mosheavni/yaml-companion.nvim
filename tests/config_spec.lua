local eq = assert.are.same

describe("config module:", function()
  local config

  before_each(function()
    -- Reset the config module to defaults before each test
    package.loaded["yaml-companion.config"] = nil
    config = require("yaml-companion.config")
  end)

  describe("defaults", function()
    it("should have default log_level", function()
      eq("info", config.defaults.log_level)
    end)

    it("should have formatting enabled by default", function()
      eq(true, config.defaults.formatting)
    end)

    it("should have builtin matchers enabled by default", function()
      eq(true, config.defaults.builtin_matchers.kubernetes.enabled)
      eq(true, config.defaults.builtin_matchers.cloud_init.enabled)
    end)

    it("should have empty schemas by default", function()
      eq({}, config.defaults.schemas)
    end)

    it("should have modeline defaults", function()
      eq(false, config.defaults.modeline.auto_add.on_attach)
      eq(false, config.defaults.modeline.auto_add.on_save)
      eq(false, config.defaults.modeline.overwrite_existing)
      eq(false, config.defaults.modeline.validate_urls)
      eq(true, config.defaults.modeline.notify)
    end)

    it("should have datree defaults", function()
      eq(3600, config.defaults.datree.cache_ttl)
      assert.is_true(config.defaults.datree.raw_content_base:match("datreeio/CRDs%-catalog") ~= nil)
    end)

    it("should have core_api_groups defined", function()
      eq(true, config.defaults.core_api_groups[""])
      eq(true, config.defaults.core_api_groups["apps"])
      eq(true, config.defaults.core_api_groups["batch"])
      eq(true, config.defaults.core_api_groups["networking.k8s.io"])
    end)

    it("should have lspconfig defaults", function()
      eq(150, config.defaults.lspconfig.flags.debounce_text_changes)
      eq(true, config.defaults.lspconfig.single_file_support)
      eq(false, config.defaults.lspconfig.settings.redhat.telemetry.enabled)
      eq(true, config.defaults.lspconfig.settings.yaml.validate)
      eq(true, config.defaults.lspconfig.settings.yaml.schemaStore.enable)
    end)
  end)

  describe("options", function()
    it("should be a deep copy of defaults initially", function()
      eq(config.defaults.log_level, config.options.log_level)
      eq(config.defaults.formatting, config.options.formatting)
    end)
  end)

  describe("setup", function()
    it("should merge user options with defaults", function()
      config.setup({ log_level = "debug" })
      eq("debug", config.options.log_level)
      -- Other defaults should remain
      eq(true, config.options.formatting)
    end)

    it("should handle nil options", function()
      config.setup(nil)
      eq("info", config.options.log_level)
    end)

    it("should merge nested options", function()
      config.setup({
        modeline = {
          auto_add = {
            on_attach = true,
          },
        },
      })
      eq(true, config.options.modeline.auto_add.on_attach)
      -- Other modeline defaults should remain
      eq(false, config.options.modeline.auto_add.on_save)
    end)

    it("should deduplicate schemas by URI", function()
      local schema1 = { name = "Schema A", uri = "https://example.com/schema.json" }
      local schema2 = { name = "Schema B", uri = "https://example.com/schema.json" }
      local schema3 = { name = "Schema C", uri = "https://other.com/schema.json" }

      config.setup({ schemas = { schema1, schema2, schema3 } })

      -- Should have only 2 schemas (deduped by URI)
      eq(2, #config.options.schemas)
    end)

    it("should handle legacy schema format with result key", function()
      local schema1 = { name = "Schema A", uri = "https://example.com/schema.json" }

      config.setup({ schemas = { result = { schema1 } } })

      eq(1, #config.options.schemas)
      eq("https://example.com/schema.json", config.options.schemas[1].uri)
    end)

    it("should convert url to uri for legacy compatibility", function()
      local schema = { name = "Schema A", url = "https://example.com/schema.json" }

      config.setup({ schemas = { schema } })

      eq("https://example.com/schema.json", config.options.schemas[1].uri)
    end)

    it("should disable builtin matchers when configured", function()
      config.setup({
        builtin_matchers = {
          kubernetes = { enabled = false },
        },
      })
      eq(false, config.options.builtin_matchers.kubernetes.enabled)
    end)

    it("should preserve user on_attach callback", function()
      local user_on_attach_called = false

      config.setup({
        lspconfig = {
          on_attach = function()
            user_on_attach_called = true
          end,
        },
      })

      -- User's on_attach should be preserved in lspconfig options
      assert.is_not_nil(config.options.lspconfig.on_attach)

      -- Simulate calling on_attach
      config.options.lspconfig.on_attach()

      eq(true, user_on_attach_called)
    end)

    it("should set up on_init to send yaml/supportSchemaSelection", function()
      config.setup({})

      assert.is_not_nil(config.options.lspconfig.on_init)
    end)

    it("should register yaml/schema/store/initialized handler", function()
      config.setup({})

      assert.is_not_nil(config.options.lspconfig.handlers)
      assert.is_not_nil(config.options.lspconfig.handlers["yaml/schema/store/initialized"])
    end)

    it("should override lspconfig settings", function()
      config.setup({
        lspconfig = {
          settings = {
            yaml = {
              validate = false,
            },
          },
        },
      })

      eq(false, config.options.lspconfig.settings.yaml.validate)
      -- Other settings should remain from defaults
      eq(true, config.options.lspconfig.settings.yaml.hover)
    end)

    it("should preserve custom lspconfig flags", function()
      config.setup({
        lspconfig = {
          flags = {
            debounce_text_changes = 300,
          },
        },
      })

      eq(300, config.options.lspconfig.flags.debounce_text_changes)
    end)

    it("should auto-enable validate_urls when cluster_crds.fallback is true", function()
      config.setup({
        cluster_crds = {
          fallback = true,
        },
      })

      eq(true, config.options.cluster_crds.fallback)
      eq(true, config.options.modeline.validate_urls)
    end)

    it("should allow validate_urls=true with fallback=true", function()
      config.setup({
        cluster_crds = {
          fallback = true,
        },
        modeline = {
          validate_urls = true,
        },
      })

      eq(true, config.options.cluster_crds.fallback)
      eq(true, config.options.modeline.validate_urls)
    end)

    it("should error when fallback=true and validate_urls explicitly set to false", function()
      assert.has_error(function()
        config.setup({
          cluster_crds = {
            fallback = true,
          },
          modeline = {
            validate_urls = false,
          },
        })
      end)
    end)

    it("should not auto-enable validate_urls when fallback is false", function()
      config.setup({
        cluster_crds = {
          fallback = false,
        },
      })

      eq(false, config.options.cluster_crds.fallback)
      eq(false, config.options.modeline.validate_urls)
    end)
  end)
end)
