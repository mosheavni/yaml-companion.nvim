local eq = assert.are.same

describe("context module:", function()
  local context
  local schema

  before_each(function()
    -- Reset modules
    package.loaded["yaml-companion.context.init"] = nil
    package.loaded["yaml-companion.schema"] = nil
    package.loaded["yaml-companion.config"] = nil
    package.loaded["yaml-companion._matchers"] = nil
    package.loaded["yaml-companion.log"] = nil

    -- Mock log module
    package.loaded["yaml-companion.log"] = {
      fmt_debug = function() end,
      fmt_error = function() end,
    }

    schema = require("yaml-companion.schema")
    context = require("yaml-companion.context.init")
  end)

  describe("progress notifications:", function()
    local progress_calls
    local original_handlers

    before_each(function()
      progress_calls = {}
      original_handlers = vim.lsp.handlers

      -- Mock the progress handler
      vim.lsp.handlers = setmetatable({}, {
        __index = function(_, key)
          if key == "$/progress" then
            return function(err, result, ctx)
              table.insert(progress_calls, {
                err = err,
                result = result,
                ctx = ctx,
              })
            end
          end
          return original_handlers[key]
        end,
      })
    end)

    after_each(function()
      vim.lsp.handlers = original_handlers
    end)

    it("should send progress notification when schema is set", function()
      -- Create a mock buffer and client
      local bufnr = vim.api.nvim_create_buf(false, true)
      local mock_client = {
        id = 1,
        name = "yamlls",
        settings = {},
        workspace_did_change_configuration = function() end,
      }

      -- Setup context for the buffer
      context.ctxs[bufnr] = {
        client = mock_client,
        schema = schema.default(),
        executed = false,
      }

      -- Set a new schema
      context.schema(bufnr, {
        name = "Test Schema",
        uri = "https://example.com/test.json",
      })

      -- Wait for defer_fn to complete
      vim.wait(200, function()
        return #progress_calls >= 2
      end)

      -- Verify begin notification was sent
      assert.is_true(#progress_calls >= 1, "Expected at least 1 progress call")
      eq(nil, progress_calls[1].err)
      eq("begin", progress_calls[1].result.value.kind)
      eq("YAML Schema", progress_calls[1].result.value.title)
      eq("Test Schema schema applied", progress_calls[1].result.value.message)
      eq(1, progress_calls[1].ctx.client_id)
      eq("$/progress", progress_calls[1].ctx.method)

      -- Verify end notification was sent
      if #progress_calls >= 2 then
        eq("end", progress_calls[2].result.value.kind)
        eq("Test Schema schema applied", progress_calls[2].result.value.message)
      end

      -- Cleanup
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should use unique tokens for each schema change", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local mock_client = {
        id = 1,
        name = "yamlls",
        settings = {},
        workspace_did_change_configuration = function() end,
      }

      context.ctxs[bufnr] = {
        client = mock_client,
        schema = schema.default(),
        executed = false,
      }

      -- Set schema twice
      context.schema(bufnr, {
        name = "Schema 1",
        uri = "https://example.com/1.json",
      })

      context.schema(bufnr, {
        name = "Schema 2",
        uri = "https://example.com/2.json",
      })

      -- Wait for notifications
      vim.wait(200, function()
        return #progress_calls >= 2
      end)

      -- Tokens should be different
      assert.is_true(#progress_calls >= 2, "Expected at least 2 progress calls")
      assert.is_true(
        progress_calls[1].result.token ~= progress_calls[2].result.token,
        "Tokens should be different"
      )

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should not crash when progress handler is not available", function()
      -- Override handler to return nil
      vim.lsp.handlers = setmetatable({}, {
        __index = function()
          return nil
        end,
      })

      local bufnr = vim.api.nvim_create_buf(false, true)
      local mock_client = {
        id = 1,
        name = "yamlls",
        settings = {},
        workspace_did_change_configuration = function() end,
      }

      context.ctxs[bufnr] = {
        client = mock_client,
        schema = schema.default(),
        executed = false,
      }

      -- This should not error
      local ok = pcall(function()
        context.schema(bufnr, {
          name = "Test Schema",
          uri = "https://example.com/test.json",
        })
      end)

      assert.is_true(ok, "Should not error when handler is not available")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should include correct context with method field", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local mock_client = {
        id = 42,
        name = "yamlls",
        settings = {},
        workspace_did_change_configuration = function() end,
      }

      context.ctxs[bufnr] = {
        client = mock_client,
        schema = schema.default(),
        executed = false,
      }

      context.schema(bufnr, {
        name = "Test Schema",
        uri = "https://example.com/test.json",
      })

      vim.wait(50, function()
        return #progress_calls >= 1
      end)

      assert.is_true(#progress_calls >= 1, "Expected at least 1 progress call")
      eq(42, progress_calls[1].ctx.client_id)
      eq("$/progress", progress_calls[1].ctx.method)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("schema function:", function()
    it("should return default schema for unknown buffer", function()
      local result = context.schema(99999, nil)
      eq("none", result.name)
      eq("none", result.uri)
    end)

    it("should handle bufnr 0 as current buffer", function()
      local bufnr = vim.api.nvim_get_current_buf()
      local mock_client = {
        id = 1,
        name = "yamlls",
        settings = {},
        workspace_did_change_configuration = function() end,
      }

      context.ctxs[bufnr] = {
        client = mock_client,
        schema = { name = "Current", uri = "https://example.com/current.json" },
        executed = false,
      }

      local result = context.schema(0, nil)
      eq("Current", result.name)
    end)
  end)
end)
