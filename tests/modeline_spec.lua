local eq = assert.are.same

local modeline = require("yaml-companion.modeline")

describe("modeline utilities:", function()
  describe("parse_modeline", function()
    it("should parse valid modeline", function()
      local url =
        modeline.parse_modeline("# yaml-language-server: $schema=https://example.com/schema.json")
      eq("https://example.com/schema.json", url)
    end)

    it("should parse modeline with extra spaces", function()
      local url =
        modeline.parse_modeline("#  yaml-language-server:  $schema=https://example.com/schema.json")
      eq("https://example.com/schema.json", url)
    end)

    it("should return nil for non-modeline", function()
      eq(nil, modeline.parse_modeline("apiVersion: v1"))
    end)

    it("should return nil for comment without schema", function()
      eq(nil, modeline.parse_modeline("# just a comment"))
    end)

    it("should return nil for nil input", function()
      eq(nil, modeline.parse_modeline(nil))
    end)

    it("should return nil for empty string", function()
      eq(nil, modeline.parse_modeline(""))
    end)
  end)

  describe("format_modeline", function()
    it("should format schema URL into modeline", function()
      local result = modeline.format_modeline("https://example.com/schema.json")
      eq("# yaml-language-server: $schema=https://example.com/schema.json", result)
    end)
  end)

  describe("is_document_separator", function()
    it("should recognize ---", function()
      eq(true, modeline.is_document_separator("---"))
    end)

    it("should recognize --- with trailing content", function()
      eq(true, modeline.is_document_separator("--- some comment"))
    end)

    it("should not match regular content", function()
      eq(false, modeline.is_document_separator("kind: Deployment"))
    end)

    it("should not match indented ---", function()
      eq(false, modeline.is_document_separator("  ---"))
    end)
  end)

  describe("find_modeline", function()
    local bufnr

    before_each(function()
      bufnr = vim.api.nvim_create_buf(false, true)
    end)

    after_each(function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end)

    it("should find modeline at start of buffer", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "# yaml-language-server: $schema=https://example.com/schema.json",
        "apiVersion: v1",
        "kind: ConfigMap",
      })

      local result = modeline.find_modeline(bufnr)
      assert.is_not_nil(result)
      eq(1, result.line_number)
      eq("https://example.com/schema.json", result.schema_url)
    end)

    it("should find modeline in middle of buffer", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "---",
        "# yaml-language-server: $schema=https://example.com/schema.json",
        "apiVersion: v1",
      })

      local result = modeline.find_modeline(bufnr)
      assert.is_not_nil(result)
      eq(2, result.line_number)
    end)

    it("should return nil when no modeline exists", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "apiVersion: v1",
        "kind: ConfigMap",
      })

      local result = modeline.find_modeline(bufnr)
      eq(nil, result)
    end)

    it("should respect start_line and end_line range", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "# yaml-language-server: $schema=https://first.com/schema.json",
        "---",
        "# yaml-language-server: $schema=https://second.com/schema.json",
        "apiVersion: v1",
      })

      local result = modeline.find_modeline(bufnr, 2, 4)
      assert.is_not_nil(result)
      eq("https://second.com/schema.json", result.schema_url)
      eq(3, result.line_number)
    end)
  end)

  describe("set_modeline", function()
    local bufnr

    before_each(function()
      bufnr = vim.api.nvim_create_buf(false, true)
    end)

    after_each(function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end)

    it("should add modeline at line 1 by default", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "apiVersion: v1",
        "kind: ConfigMap",
      })

      local success = modeline.set_modeline(bufnr, "https://example.com/schema.json")
      eq(true, success)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      eq("# yaml-language-server: $schema=https://example.com/schema.json", lines[1])
      eq("apiVersion: v1", lines[2])
    end)

    it("should add modeline at specified line", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "---",
        "apiVersion: v1",
        "kind: ConfigMap",
      })

      local success = modeline.set_modeline(bufnr, "https://example.com/schema.json", 2)
      eq(true, success)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      eq("---", lines[1])
      eq("# yaml-language-server: $schema=https://example.com/schema.json", lines[2])
      eq("apiVersion: v1", lines[3])
    end)

    it("should not overwrite existing modeline by default", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "# yaml-language-server: $schema=https://old.com/schema.json",
        "apiVersion: v1",
      })

      local success = modeline.set_modeline(bufnr, "https://new.com/schema.json", 1, false)
      eq(true, success)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      -- Should keep the old modeline
      eq("# yaml-language-server: $schema=https://old.com/schema.json", lines[1])
    end)

    it("should overwrite existing modeline when requested", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "# yaml-language-server: $schema=https://old.com/schema.json",
        "apiVersion: v1",
      })

      local success = modeline.set_modeline(bufnr, "https://new.com/schema.json", 1, true)
      eq(true, success)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      eq("# yaml-language-server: $schema=https://new.com/schema.json", lines[1])
    end)
  end)

  describe("find_document_boundaries", function()
    local bufnr

    before_each(function()
      bufnr = vim.api.nvim_create_buf(false, true)
    end)

    after_each(function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end)

    it("should find single document", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "apiVersion: v1",
        "kind: ConfigMap",
      })

      local boundaries = modeline.find_document_boundaries(bufnr)
      eq(1, #boundaries)
      eq(1, boundaries[1].start_line)
      eq(2, boundaries[1].end_line)
    end)

    it("should find multiple documents", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "apiVersion: v1",
        "kind: ConfigMap",
        "---",
        "apiVersion: apps/v1",
        "kind: Deployment",
      })

      local boundaries = modeline.find_document_boundaries(bufnr)
      eq(2, #boundaries)
      eq(1, boundaries[1].start_line)
      eq(2, boundaries[1].end_line)
      eq(3, boundaries[2].start_line)
      eq(5, boundaries[2].end_line)
    end)

    it("should handle leading document separator", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "---",
        "apiVersion: v1",
        "kind: ConfigMap",
      })

      local boundaries = modeline.find_document_boundaries(bufnr)
      eq(1, #boundaries)
      eq(1, boundaries[1].start_line)
      eq(3, boundaries[1].end_line)
    end)

    it("should handle three documents", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "apiVersion: v1",
        "kind: ConfigMap",
        "---",
        "apiVersion: apps/v1",
        "kind: Deployment",
        "---",
        "apiVersion: v1",
        "kind: Service",
      })

      local boundaries = modeline.find_document_boundaries(bufnr)
      eq(3, #boundaries)
    end)

    it("should return empty for empty buffer", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

      local boundaries = modeline.find_document_boundaries(bufnr)
      eq(0, #boundaries)
    end)
  end)
end)
