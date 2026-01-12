local eq = assert.are.same

local keys = require("yaml-companion.keys")
local ts = require("yaml-companion.treesitter")

-- Check if YAML treesitter parser is available
local has_yaml_parser = ts.has_parser()

describe("keys navigation:", function()
  local bufnr

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("filetype", "yaml", { buf = bufnr })
    vim.api.nvim_set_current_buf(bufnr)
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  describe("quickfix", function()
    it("should populate quickfix with all keys", function()
      if not has_yaml_parser then
        pending("YAML treesitter parser not installed", function() end)
        return
      end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "apiVersion: v1",
        "kind: ConfigMap",
        "metadata:",
        "  name: my-config",
      })

      local entries = keys.quickfix(bufnr, { open = false })
      -- Should have apiVersion, kind, metadata, metadata.name
      assert.is_true(#entries >= 4)
    end)

    it("should not include values by default", function()
      if not has_yaml_parser then
        pending("YAML treesitter parser not installed", function() end)
        return
      end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "foo: bar",
      })

      local entries = keys.quickfix(bufnr, { open = false })
      eq(1, #entries)
      eq(".foo", entries[1].text)
    end)

    it("should set correct line numbers", function()
      if not has_yaml_parser then
        pending("YAML treesitter parser not installed", function() end)
        return
      end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "first: 1",
        "second: 2",
      })

      local entries = keys.quickfix(bufnr, { open = false })
      eq(1, entries[1].lnum)
      eq(2, entries[2].lnum)
    end)

    it("should set buffer number", function()
      if not has_yaml_parser then
        pending("YAML treesitter parser not installed", function() end)
        return
      end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "key: value",
      })

      local entries = keys.quickfix(bufnr, { open = false })
      eq(bufnr, entries[1].bufnr)
    end)

    it("should handle nested keys", function()
      if not has_yaml_parser then
        pending("YAML treesitter parser not installed", function() end)
        return
      end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "parent:",
        "  child:",
        "    grandchild: value",
      })

      local entries = keys.quickfix(bufnr, { open = false })
      local texts = vim.tbl_map(function(e)
        return e.text
      end, entries)

      local has_grandchild = false
      for _, text in ipairs(texts) do
        if text:match("parent%.child%.grandchild") then
          has_grandchild = true
          break
        end
      end
      assert.is_true(has_grandchild)
    end)

    it("should handle empty buffer", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

      local entries = keys.quickfix(bufnr, { open = false })
      eq(0, #entries)
    end)

    it("should return empty when parser not available", function()
      if has_yaml_parser then
        pending("skipped - parser is available", function() end)
        return
      end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "foo: bar",
      })

      local entries = keys.quickfix(bufnr, { open = false })
      eq(0, #entries)
    end)

    it("should handle long values without truncation when values disabled", function()
      if not has_yaml_parser then
        pending("YAML treesitter parser not installed", function() end)
        return
      end
      local long_value = string.rep("x", 100)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "key: " .. long_value,
      })

      local entries = keys.quickfix(bufnr, { open = false })
      -- Values are disabled by default, so just show key
      eq(".key", entries[1].text)
    end)

    it("should show just key path for keys without scalar values", function()
      if not has_yaml_parser then
        pending("YAML treesitter parser not installed", function() end)
        return
      end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "parent:",
        "  child: value",
      })

      local entries = keys.quickfix(bufnr, { open = false })
      local parent = vim.tbl_filter(function(e)
        return e.text == ".parent"
      end, entries)
      eq(1, #parent)
    end)
  end)

  describe("at_cursor", function()
    it("should return key info at cursor", function()
      if not has_yaml_parser then
        pending("YAML treesitter parser not installed", function() end)
        return
      end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "foo: bar",
        "baz: qux",
      })
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      local info = keys.at_cursor()
      assert.is_not_nil(info)
      eq(".foo", info.key)
      eq("bar", info.value)
      eq(".foo = bar", info.human)
    end)

    it("should return nil for empty buffer", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

      local info = keys.at_cursor()
      eq(nil, info)
    end)

    it("should return nil when parser not available", function()
      if has_yaml_parser then
        pending("skipped - parser is available", function() end)
        return
      end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "foo: bar",
      })

      local info = keys.at_cursor()
      eq(nil, info)
    end)

    it("should return nested key path", function()
      if not has_yaml_parser then
        pending("YAML treesitter parser not installed", function() end)
        return
      end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "parent:",
        "  child: value",
      })
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      local info = keys.at_cursor()
      assert.is_not_nil(info)
      eq(".parent.child", info.key)
    end)

    it("should return correct line number", function()
      if not has_yaml_parser then
        pending("YAML treesitter parser not installed", function() end)
        return
      end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "first: 1",
        "second: 2",
        "third: 3",
      })
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      local info = keys.at_cursor()
      assert.is_not_nil(info)
      eq(2, info.line)
    end)
  end)
end)
