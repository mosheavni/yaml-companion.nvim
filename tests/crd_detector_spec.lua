--# selene: allow(undefined_variable)
local eq = assert.are.same

local detector = require("yaml-companion.modeline.crd_detector")

describe("CRD detector:", function()
  describe("parse_api_version", function()
    it("should parse group/version format", function()
      local group, version = detector.parse_api_version("argoproj.io/v1alpha1")
      eq("argoproj.io", group)
      eq("v1alpha1", version)
    end)

    it("should parse core API version", function()
      local group, version = detector.parse_api_version("v1")
      eq("", group)
      eq("v1", version)
    end)

    it("should parse apps API version", function()
      local group, version = detector.parse_api_version("apps/v1")
      eq("apps", group)
      eq("v1", version)
    end)

    it("should handle nil input", function()
      local group, version = detector.parse_api_version(nil)
      eq("", group)
      eq("", version)
    end)

    it("should parse networking.k8s.io API", function()
      local group, version = detector.parse_api_version("networking.k8s.io/v1")
      eq("networking.k8s.io", group)
      eq("v1", version)
    end)
  end)

  describe("is_core_api_group", function()
    it("should identify empty string as core", function()
      eq(true, detector.is_core_api_group(""))
    end)

    it("should identify apps as core", function()
      eq(true, detector.is_core_api_group("apps"))
    end)

    it("should identify batch as core", function()
      eq(true, detector.is_core_api_group("batch"))
    end)

    it("should identify networking.k8s.io as core", function()
      eq(true, detector.is_core_api_group("networking.k8s.io"))
    end)

    it("should identify argoproj.io as non-core", function()
      eq(false, detector.is_core_api_group("argoproj.io"))
    end)

    it("should identify cert-manager.io as non-core", function()
      eq(false, detector.is_core_api_group("cert-manager.io"))
    end)

    it("should identify external-secrets.io as non-core", function()
      eq(false, detector.is_core_api_group("external-secrets.io"))
    end)
  end)

  describe("build_crd_schema_url", function()
    it("should build correct URL for ArgoCD Application", function()
      local crd = {
        apiGroup = "argoproj.io",
        kind = "Application",
        version = "v1alpha1",
        is_core = false,
      }
      local url = detector.build_crd_schema_url(crd)
      eq(
        "https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/argoproj.io/application_v1alpha1.json",
        url
      )
    end)

    it("should build correct URL for cert-manager Certificate", function()
      local crd = {
        apiGroup = "cert-manager.io",
        kind = "Certificate",
        version = "v1",
        is_core = false,
      }
      local url = detector.build_crd_schema_url(crd)
      eq(
        "https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/cert-manager.io/certificate_v1.json",
        url
      )
    end)

    it("should return nil for core resources", function()
      local crd = {
        apiGroup = "apps",
        kind = "Deployment",
        version = "v1",
        is_core = true,
      }
      local url = detector.build_crd_schema_url(crd)
      eq(nil, url)
    end)

    it("should return nil for empty apiGroup", function()
      local crd = {
        apiGroup = "",
        kind = "ConfigMap",
        version = "v1",
        is_core = false,
      }
      local url = detector.build_crd_schema_url(crd)
      eq(nil, url)
    end)
  end)

  describe("detect_crds", function()
    local bufnr

    before_each(function()
      bufnr = vim.api.nvim_create_buf(false, true)
    end)

    after_each(function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end)

    it("should detect single CRD", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "apiVersion: argoproj.io/v1alpha1",
        "kind: Application",
        "metadata:",
        "  name: my-app",
      })

      local crds = detector.detect_crds(bufnr)
      eq(1, #crds)
      eq("Application", crds[1].kind)
      eq("argoproj.io/v1alpha1", crds[1].apiVersion)
      eq("argoproj.io", crds[1].apiGroup)
      eq("v1alpha1", crds[1].version)
      eq(false, crds[1].is_core)
    end)

    it("should detect core resource", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "apiVersion: apps/v1",
        "kind: Deployment",
        "metadata:",
        "  name: my-deployment",
      })

      local crds = detector.detect_crds(bufnr)
      eq(1, #crds)
      eq("Deployment", crds[1].kind)
      eq(true, crds[1].is_core)
    end)

    it("should detect multiple resources in multi-doc", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "apiVersion: apps/v1",
        "kind: Deployment",
        "---",
        "apiVersion: argoproj.io/v1alpha1",
        "kind: Application",
        "---",
        "apiVersion: v1",
        "kind: Service",
      })

      local crds = detector.detect_crds(bufnr)
      eq(3, #crds)

      eq("Deployment", crds[1].kind)
      eq(true, crds[1].is_core)

      eq("Application", crds[2].kind)
      eq(false, crds[2].is_core)

      eq("Service", crds[3].kind)
      eq(true, crds[3].is_core)
    end)

    it("should handle leading document separator", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "---",
        "apiVersion: argoproj.io/v1alpha1",
        "kind: Application",
      })

      local crds = detector.detect_crds(bufnr)
      eq(1, #crds)
      eq("Application", crds[1].kind)
    end)

    it("should return empty for non-K8s content", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "foo: bar",
        "baz: qux",
      })

      local crds = detector.detect_crds(bufnr)
      eq(0, #crds)
    end)
  end)

  describe("add_modelines", function()
    local bufnr

    before_each(function()
      bufnr = vim.api.nvim_create_buf(false, true)
    end)

    after_each(function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end)

    it("should add modeline for CRD", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "apiVersion: argoproj.io/v1alpha1",
        "kind: Application",
        "metadata:",
        "  name: my-app",
      })

      local result = detector.add_modelines(bufnr)
      eq(1, result.added)
      eq(0, result.skipped)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.is_truthy(lines[1]:match("yaml%-language%-server.*argoproj%.io/application_v1alpha1"))
    end)

    it("should skip core resources", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "apiVersion: apps/v1",
        "kind: Deployment",
        "metadata:",
        "  name: my-deployment",
      })

      local result = detector.add_modelines(bufnr)
      eq(0, result.added)
      eq(1, result.skipped)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      eq("apiVersion: apps/v1", lines[1])
    end)

    it("should not add duplicate modelines", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "# yaml-language-server: $schema=https://example.com/schema.json",
        "apiVersion: argoproj.io/v1alpha1",
        "kind: Application",
      })

      local result = detector.add_modelines(bufnr)
      eq(0, result.added)
      eq(1, result.skipped)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      -- Should still have only 3 lines
      eq(3, #lines)
    end)

    it("should handle dry_run option", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "apiVersion: argoproj.io/v1alpha1",
        "kind: Application",
      })

      local result = detector.add_modelines(bufnr, { dry_run = true })
      eq(1, result.added)

      -- Buffer should be unchanged
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      eq(2, #lines)
      eq("apiVersion: argoproj.io/v1alpha1", lines[1])
    end)

    it("should handle multi-doc with mixed resources", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "apiVersion: apps/v1",
        "kind: Deployment",
        "---",
        "apiVersion: argoproj.io/v1alpha1",
        "kind: Application",
      })

      local result = detector.add_modelines(bufnr)
      eq(1, result.added)
      eq(1, result.skipped)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      -- Modeline should be added before the CRD, not the Deployment
      assert.is_truthy(lines[4]:match("yaml%-language%-server"))
    end)
  end)
end)
