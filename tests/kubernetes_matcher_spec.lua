local eq = assert.are.same

local kubernetes = require("yaml-companion.builtin.kubernetes")
local resources = require("yaml-companion.builtin.kubernetes.resources")

describe("kubernetes matcher:", function()
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
    it("should match Deployment kind", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "apiVersion: apps/v1",
        "kind: Deployment",
        "metadata:",
        "  name: my-deployment",
      })

      local result = kubernetes.match(bufnr)
      assert.is_not_nil(result)
      eq("Kubernetes", result.name)
      assert.is_true(result.uri:match("kubernetes%-json%-schema") ~= nil)
    end)

    it("should match ConfigMap kind", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "apiVersion: v1",
        "kind: ConfigMap",
        "metadata:",
        "  name: my-configmap",
      })

      local result = kubernetes.match(bufnr)
      assert.is_not_nil(result)
      eq("Kubernetes", result.name)
    end)

    it("should match Service kind", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "apiVersion: v1",
        "kind: Service",
        "metadata:",
        "  name: my-service",
      })

      local result = kubernetes.match(bufnr)
      assert.is_not_nil(result)
      eq("Kubernetes", result.name)
    end)

    it("should match Pod kind", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "apiVersion: v1",
        "kind: Pod",
        "metadata:",
        "  name: my-pod",
      })

      local result = kubernetes.match(bufnr)
      assert.is_not_nil(result)
      eq("Kubernetes", result.name)
    end)

    it("should match StatefulSet kind", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "apiVersion: apps/v1",
        "kind: StatefulSet",
        "metadata:",
        "  name: my-statefulset",
      })

      local result = kubernetes.match(bufnr)
      assert.is_not_nil(result)
      eq("Kubernetes", result.name)
    end)

    it("should match DaemonSet kind", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "apiVersion: apps/v1",
        "kind: DaemonSet",
        "metadata:",
        "  name: my-daemonset",
      })

      local result = kubernetes.match(bufnr)
      assert.is_not_nil(result)
      eq("Kubernetes", result.name)
    end)

    it("should match Ingress kind", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "apiVersion: networking.k8s.io/v1",
        "kind: Ingress",
        "metadata:",
        "  name: my-ingress",
      })

      local result = kubernetes.match(bufnr)
      assert.is_not_nil(result)
      eq("Kubernetes", result.name)
    end)

    it("should match kind anywhere in the file", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "# This is a comment",
        "---",
        "apiVersion: v1",
        "kind: Service",
        "metadata:",
        "  name: test",
      })

      local result = kubernetes.match(bufnr)
      assert.is_not_nil(result)
      eq("Kubernetes", result.name)
    end)

    it("should not match non-Kubernetes YAML", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "foo: bar",
        "baz: qux",
      })

      local result = kubernetes.match(bufnr)
      eq(nil, result)
    end)

    it("should not match kind with unknown type", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "apiVersion: v1",
        "kind: UnknownResourceType",
        "metadata:",
        "  name: test",
      })

      local result = kubernetes.match(bufnr)
      eq(nil, result)
    end)

    it("should not match kind as a nested field", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "metadata:",
        "  kind: Service",
      })

      local result = kubernetes.match(bufnr)
      eq(nil, result)
    end)

    it("should match multi-document with Kubernetes resource", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "---",
        "apiVersion: v1",
        "kind: ConfigMap",
        "metadata:",
        "  name: cm1",
        "---",
        "apiVersion: v1",
        "kind: Secret",
        "metadata:",
        "  name: secret1",
      })

      local result = kubernetes.match(bufnr)
      assert.is_not_nil(result)
      eq("Kubernetes", result.name)
    end)

    it("should not match empty buffer", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

      local result = kubernetes.match(bufnr)
      eq(nil, result)
    end)

    it("should not match kind with trailing content", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "apiVersion: v1",
        "kind: Service # inline comment",
        "metadata:",
        "  name: test",
      })

      local result = kubernetes.match(bufnr)
      eq(nil, result)
    end)
  end)

  describe("handles", function()
    it("should return the Kubernetes schema", function()
      local schemas = kubernetes.handles()
      eq(1, #schemas)
      eq("Kubernetes", schemas[1].name)
      assert.is_true(schemas[1].uri:match("kubernetes%-json%-schema") ~= nil)
    end)
  end)

  describe("resources list", function()
    it("should contain common Kubernetes resources", function()
      local common_resources = {
        "Deployment",
        "Pod",
        "Service",
        "ConfigMap",
        "Secret",
        "Ingress",
        "StatefulSet",
        "DaemonSet",
        "Job",
        "CronJob",
        "ReplicaSet",
        "Namespace",
        "PersistentVolume",
        "PersistentVolumeClaim",
        "ServiceAccount",
        "Role",
        "RoleBinding",
        "ClusterRole",
        "ClusterRoleBinding",
      }

      for _, resource in ipairs(common_resources) do
        local found = false
        for _, r in ipairs(resources) do
          if r == resource then
            found = true
            break
          end
        end
        assert.is_true(found, "Missing resource: " .. resource)
      end
    end)
  end)
end)
