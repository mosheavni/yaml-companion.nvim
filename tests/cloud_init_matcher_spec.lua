local eq = assert.are.same

local cloud_init = require("yaml-companion.builtin.cloud_init")

describe("cloud-init matcher:", function()
  local bufnr

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  describe("match", function()
    it("should match #cloud-config header", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "#cloud-config",
        "packages:",
        "  - vim",
        "  - git",
      })

      local result = cloud_init.match(bufnr)
      assert.is_not_nil(result)
      eq("cloud-init", result.name)
      assert.is_true(result.uri:match("cloud%-init") ~= nil)
    end)

    it("should match #cloud-config with trailing content", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "#cloud-config some comment",
        "packages:",
        "  - vim",
      })

      local result = cloud_init.match(bufnr)
      assert.is_not_nil(result)
      eq("cloud-init", result.name)
    end)

    it("should not match without #cloud-config header", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "packages:",
        "  - vim",
        "  - git",
      })

      local result = cloud_init.match(bufnr)
      eq(nil, result)
    end)

    it("should not match #cloud-config in second line", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "# some comment",
        "#cloud-config",
        "packages:",
        "  - vim",
      })

      local result = cloud_init.match(bufnr)
      eq(nil, result)
    end)

    it("should not match cloud-config without hash", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "cloud-config",
        "packages:",
        "  - vim",
      })

      local result = cloud_init.match(bufnr)
      eq(nil, result)
    end)

    it("should not match empty buffer", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

      local result = cloud_init.match(bufnr)
      eq(nil, result)
    end)

    it("should not match regular YAML", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "apiVersion: v1",
        "kind: ConfigMap",
      })

      local result = cloud_init.match(bufnr)
      eq(nil, result)
    end)

    it("should not match indented #cloud-config", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "  #cloud-config",
        "packages:",
        "  - vim",
      })

      local result = cloud_init.match(bufnr)
      eq(nil, result)
    end)

    it("should match minimal cloud-init config", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "#cloud-config",
      })

      local result = cloud_init.match(bufnr)
      assert.is_not_nil(result)
      eq("cloud-init", result.name)
    end)

    it("should match cloud-init with user data", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "#cloud-config",
        "users:",
        "  - name: admin",
        "    groups: sudo",
        "    shell: /bin/bash",
        "    ssh_authorized_keys:",
        "      - ssh-rsa AAAAB3...",
      })

      local result = cloud_init.match(bufnr)
      assert.is_not_nil(result)
      eq("cloud-init", result.name)
    end)

    it("should match cloud-init with runcmd", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "#cloud-config",
        "runcmd:",
        "  - echo 'Hello World'",
        "  - apt-get update",
      })

      local result = cloud_init.match(bufnr)
      assert.is_not_nil(result)
      eq("cloud-init", result.name)
    end)
  end)
end)
