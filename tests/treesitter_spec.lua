local eq = assert.are.same

local pair = require("yaml-companion.treesitter.pair")
local document = require("yaml-companion.treesitter.document")
local ts = require("yaml-companion.treesitter")

-- Check if YAML treesitter parser is available
local has_yaml_parser = ts.has_parser()

describe("treesitter utilities:", function()
  local bufnr

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("filetype", "yaml", { buf = bufnr })
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  describe("ts.has_parser", function()
    it("should return boolean indicating YAML parser availability", function()
      local has = ts.has_parser()
      assert.is_boolean(has)
    end)
  end)

  describe("pair.clean_value", function()
    it("should remove double quotes", function()
      eq("hello", pair.clean_value('"hello"'))
    end)

    it("should remove single quotes", function()
      eq("world", pair.clean_value("'world'"))
    end)

    it("should trim whitespace", function()
      eq("test", pair.clean_value("  test  "))
    end)

    it("should handle empty string", function()
      eq("", pair.clean_value(""))
    end)

    it("should handle nil", function()
      eq("", pair.clean_value(nil))
    end)

    it("should handle block scalar indicator |", function()
      eq("multiline content", pair.clean_value("| multiline content"))
    end)

    it("should handle block scalar indicator >", function()
      eq("folded content", pair.clean_value("> folded content"))
    end)

    it("should collapse multiple whitespace", function()
      eq("hello world", pair.clean_value("hello   world"))
    end)
  end)

  -- Document parsing tests - require treesitter YAML parser
  describe("document.all_keys", function()
    it("should return empty when parser not available", function()
      if has_yaml_parser then
        pending("skipped - parser is available", function() end)
        return
      end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "foo: bar",
      })

      local keys = document.all_keys(bufnr)
      eq(0, #keys)
    end)

    it("should return all top-level keys", function()
      if not has_yaml_parser then
        pending("YAML treesitter parser not installed - run :TSInstall yaml", function() end)
        return
      end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "foo: bar",
        "baz: qux",
      })

      local keys = document.all_keys(bufnr)
      eq(2, #keys)
      eq(".foo", keys[1].key)
      eq(".baz", keys[2].key)
    end)

    it("should extract scalar values", function()
      if not has_yaml_parser then
        pending("YAML treesitter parser not installed", function() end)
        return
      end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "name: hello",
        "count: 42",
      })

      local keys = document.all_keys(bufnr)
      eq("hello", keys[1].value)
      eq("42", keys[2].value)
    end)

    it("should build nested key paths", function()
      if not has_yaml_parser then
        pending("YAML treesitter parser not installed", function() end)
        return
      end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "root:",
        "  parent:",
        "    child: value",
      })

      local keys = document.all_keys(bufnr)
      local paths = vim.tbl_map(function(k)
        return k.key
      end, keys)

      assert.is_true(vim.tbl_contains(paths, ".root"))
      assert.is_true(vim.tbl_contains(paths, ".root.parent"))
      assert.is_true(vim.tbl_contains(paths, ".root.parent.child"))
    end)

    it("should handle array indices", function()
      if not has_yaml_parser then
        pending("YAML treesitter parser not installed", function() end)
        return
      end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "items:",
        "  - name: first",
        "  - name: second",
      })

      local keys = document.all_keys(bufnr)
      local paths = vim.tbl_map(function(k)
        return k.key
      end, keys)

      assert.is_true(vim.tbl_contains(paths, ".items"))
      assert.is_true(vim.tbl_contains(paths, ".items[0].name"))
      assert.is_true(vim.tbl_contains(paths, ".items[1].name"))
    end)

    it("should return empty for empty buffer", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

      local keys = document.all_keys(bufnr)
      eq(0, #keys)
    end)

    it("should handle Kubernetes manifest", function()
      if not has_yaml_parser then
        pending("YAML treesitter parser not installed", function() end)
        return
      end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "apiVersion: v1",
        "kind: ConfigMap",
        "metadata:",
        "  name: my-config",
        "  namespace: default",
        "data:",
        "  key1: value1",
      })

      local keys = document.all_keys(bufnr)
      local paths = vim.tbl_map(function(k)
        return k.key
      end, keys)

      assert.is_true(vim.tbl_contains(paths, ".apiVersion"))
      assert.is_true(vim.tbl_contains(paths, ".kind"))
      assert.is_true(vim.tbl_contains(paths, ".metadata"))
      assert.is_true(vim.tbl_contains(paths, ".metadata.name"))
      assert.is_true(vim.tbl_contains(paths, ".metadata.namespace"))
      assert.is_true(vim.tbl_contains(paths, ".data"))
      assert.is_true(vim.tbl_contains(paths, ".data.key1"))
    end)

    it("should set correct line numbers", function()
      if not has_yaml_parser then
        pending("YAML treesitter parser not installed", function() end)
        return
      end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "first: 1",
        "second: 2",
        "third: 3",
      })

      local keys = document.all_keys(bufnr)
      eq(1, keys[1].line)
      eq(2, keys[2].line)
      eq(3, keys[3].line)
    end)

    it("should format human-readable output with values", function()
      if not has_yaml_parser then
        pending("YAML treesitter parser not installed", function() end)
        return
      end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "name: hello",
      })

      local keys = document.all_keys(bufnr)
      eq(".name = hello", keys[1].human)
    end)

    it("should format human-readable output without values", function()
      if not has_yaml_parser then
        pending("YAML treesitter parser not installed", function() end)
        return
      end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "parent:",
        "  child: value",
      })

      local keys = document.all_keys(bufnr)
      -- parent has no scalar value, human shows with colon (for API use)
      local parent = vim.tbl_filter(function(k)
        return k.key == ".parent"
      end, keys)[1]
      eq(".parent:", parent.human)
    end)
  end)

  describe("document.get_key_at_line", function()
    it("should return key at cursor line", function()
      if not has_yaml_parser then
        pending("YAML treesitter parser not installed", function() end)
        return
      end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "foo: bar",
        "baz: qux",
      })

      local key = document.get_key_at_line(bufnr, 2)
      assert.is_not_nil(key)
      eq(".baz", key.key)
      eq("qux", key.value)
    end)

    it("should return first key for line 1", function()
      if not has_yaml_parser then
        pending("YAML treesitter parser not installed", function() end)
        return
      end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "first: value",
        "second: value2",
      })

      local key = document.get_key_at_line(bufnr, 1)
      assert.is_not_nil(key)
      eq(".first", key.key)
    end)

    it("should return nested key when cursor is on nested line", function()
      if not has_yaml_parser then
        pending("YAML treesitter parser not installed", function() end)
        return
      end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "parent:",
        "  child: value",
      })

      local key = document.get_key_at_line(bufnr, 2)
      assert.is_not_nil(key)
      eq(".parent.child", key.key)
    end)

    it("should return nil for empty buffer", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

      local key = document.get_key_at_line(bufnr, 1)
      eq(nil, key)
    end)

    it("should return nil when parser not available", function()
      if has_yaml_parser then
        pending("skipped - parser is available", function() end)
        return
      end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "only: line",
      })

      local key = document.get_key_at_line(bufnr, 1)
      eq(nil, key)
    end)

    it("should handle line beyond buffer end", function()
      if not has_yaml_parser then
        pending("YAML treesitter parser not installed", function() end)
        return
      end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "only: line",
      })

      -- Line 100 is beyond buffer, should return the last key
      local key = document.get_key_at_line(bufnr, 100)
      assert.is_not_nil(key)
      eq(".only", key.key)
    end)
  end)
end)
