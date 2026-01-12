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
      ---@diagnostic disable-next-line: param-type-mismatch
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
      -- Use the actual URL that would be generated for Application
      local correct_url =
        "https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/argoproj.io/application_v1alpha1.json"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "# yaml-language-server: $schema=" .. correct_url,
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

    it("should not create duplicates when called multiple times", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "apiVersion: argoproj.io/v1alpha1",
        "kind: Application",
        "metadata:",
        "  name: my-app",
      })

      -- Call add_modelines multiple times
      local result1 = detector.add_modelines(bufnr)
      local result2 = detector.add_modelines(bufnr)
      local result3 = detector.add_modelines(bufnr)

      -- First call should add, subsequent calls should skip
      eq(1, result1.added)
      eq(0, result2.added)
      eq(0, result3.added)
      eq(1, result2.skipped)
      eq(1, result3.skipped)

      -- Should only have ONE modeline
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local modeline_count = 0
      for _, line in ipairs(lines) do
        if line:match("yaml%-language%-server.*%$schema=") then
          modeline_count = modeline_count + 1
        end
      end
      eq(1, modeline_count)
    end)

    it("should not create duplicates when called rapidly in sequence", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "apiVersion: external-secrets.io/v1",
        "kind: ExternalSecret",
        "metadata:",
        "  name: test",
      })

      -- Simulate rapid sequential calls (what might happen with on_attach + on_save)
      for _ = 1, 5 do
        detector.add_modelines(bufnr)
      end

      -- Count modelines - should be exactly 1
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local modeline_count = 0
      for _, line in ipairs(lines) do
        if line:match("yaml%-language%-server.*%$schema=") then
          modeline_count = modeline_count + 1
        end
      end
      eq(1, modeline_count)
    end)

    it("should handle pre-existing modeline without creating duplicates", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/external-secrets.io/externalsecret_v1.json",
        "apiVersion: external-secrets.io/v1",
        "kind: ExternalSecret",
        "metadata:",
        "  name: test",
      })

      -- Call multiple times
      detector.add_modelines(bufnr)
      detector.add_modelines(bufnr)

      -- Count modelines - should still be exactly 1
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local modeline_count = 0
      for _, line in ipairs(lines) do
        if line:match("yaml%-language%-server.*%$schema=") then
          modeline_count = modeline_count + 1
        end
      end
      eq(1, modeline_count)
      eq(5, #lines) -- Should not have grown
    end)

    it("should only report added=1 once even with concurrent-like calls", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "apiVersion: argoproj.io/v1alpha1",
        "kind: Application",
        "metadata:",
        "  name: my-app",
      })

      -- Simulate what happens when on_attach is called multiple times
      -- Only the first call should have added=1, subsequent calls should have added=0
      local results = {}
      for i = 1, 3 do
        results[i] = detector.add_modelines(bufnr)
      end

      -- First call adds
      eq(1, results[1].added)
      eq(0, results[1].skipped)

      -- Subsequent calls skip (added=0 prevents duplicate notifications)
      eq(0, results[2].added)
      eq(1, results[2].skipped)
      eq(0, results[3].added)
      eq(1, results[3].skipped)

      -- Verify only 1 modeline exists
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local modeline_count = 0
      for _, line in ipairs(lines) do
        if line:match("yaml%-language%-server.*%$schema=") then
          modeline_count = modeline_count + 1
        end
      end
      eq(1, modeline_count)
    end)

    -- Test case based on real-world file with 5 documents:
    -- CRD, CRD, CRD, CRD, core Deployment
    it("should handle complex multi-doc with 5 documents and mixed resources", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "---",
        "apiVersion: networking.istio.io/v1alpha3",
        "kind: DestinationRule",
        "metadata:",
        "  name: test-rule",
        "spec:",
        "  host: test.svc.local",
        "---",
        "apiVersion: argoproj.io/v1alpha1",
        "kind: Application",
        "metadata:",
        "  name: argocd",
        "spec:",
        "  project: default",
        "---",
        "apiVersion: external-secrets.io/v1",
        "kind: ExternalSecret",
        "metadata:",
        "  name: my-secret",
        "spec:",
        "  data: []",
        "---",
        "apiVersion: argoproj.io/v1alpha1",
        "kind: AppProject",
        "metadata:",
        "  name: my-project",
        "spec:",
        "  destinations: []",
        "---",
        "apiVersion: apps/v1",
        "kind: Deployment",
        "metadata:",
        "  name: my-app",
        "spec:",
        "  replicas: 1",
      })

      local result = detector.add_modelines(bufnr)

      -- 4 CRDs should get modelines, 1 Deployment should be skipped
      eq(4, result.added)
      eq(1, result.skipped)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      -- Verify modelines are at correct positions (after each ---)
      assert.is_truthy(lines[2]:match("yaml%-language%-server.*istio"))
      assert.is_truthy(lines[10]:match("yaml%-language%-server.*argoproj.*application"))
      assert.is_truthy(lines[18]:match("yaml%-language%-server.*external%-secrets"))
      assert.is_truthy(lines[26]:match("yaml%-language%-server.*argoproj.*appproject"))

      -- Deployment should NOT have a modeline
      assert.is_falsy(lines[34]:match("yaml%-language%-server"))
    end)

    -- Test case: document with metadata/spec BEFORE apiVersion/kind (unusual but valid YAML)
    it("should handle documents with unusual field ordering", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "---",
        "metadata:",
        "  name: my-secret",
        "spec:",
        "  data:",
        "    - remoteRef:",
        "        key: mykey",
        "  secretStoreRef:",
        "    kind: ClusterSecretStore", -- nested kind: should NOT be matched
        "    name: azure-backend",
        "apiVersion: external-secrets.io/v1",
        "kind: ExternalSecret",
        "---",
        "apiVersion: apps/v1",
        "kind: Deployment",
        "metadata:",
        "  name: my-app",
      })

      local crds = detector.detect_crds(bufnr)

      -- Should detect ExternalSecret (nested kind: ClusterSecretStore should be ignored)
      eq(2, #crds)
      eq("ExternalSecret", crds[1].kind)
      eq(2, crds[1].line_number) -- Document starts at line 2 (after ---)
      eq(12, crds[1].end_line) -- Document ends at line 12 (before next ---)

      eq("Deployment", crds[2].kind)
      eq(true, crds[2].is_core)

      -- Add modelines
      local result = detector.add_modelines(bufnr)
      eq(1, result.added) -- Only ExternalSecret, Deployment is core
      eq(1, result.skipped)

      -- Verify modeline is at document start, not in the middle
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.is_truthy(lines[2]:match("yaml%-language%-server.*externalsecret"))
      -- The nested kind: ClusterSecretStore line should still be intact
      assert.is_truthy(lines[10]:match("kind: ClusterSecretStore"))
    end)

    -- Test: modeline with CORRECT URL exists in wrong position
    -- Should not add duplicate even if position is wrong
    it("should find matching modeline anywhere in document and not add duplicate", function()
      -- Use the actual URL that would be generated for ExternalSecret
      local correct_url =
        "https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/external-secrets.io/externalsecret_v1.json"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "---",
        "apiVersion: external-secrets.io/v1",
        "kind: ExternalSecret",
        "metadata:",
        "  name: my-secret",
        "spec:",
        "  data: []",
        "# yaml-language-server: $schema=" .. correct_url, -- Wrong position but correct URL
        "  more: data",
        "---",
      })

      -- CRD detected at line 2
      local crds = detector.detect_crds(bufnr)
      eq(1, #crds)
      eq("ExternalSecret", crds[1].kind)

      -- Should NOT add another modeline because one with same URL exists
      local result = detector.add_modelines(bufnr)
      eq(0, result.added)
      eq(1, result.skipped)

      -- Verify only 1 modeline exists
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local modeline_count = 0
      for _, line in ipairs(lines) do
        if line:match("yaml%-language%-server.*%$schema=") then
          modeline_count = modeline_count + 1
        end
      end
      eq(1, modeline_count)
    end)

    -- Test: modeline with DIFFERENT URL exists (wrong schema in document)
    -- Should add the correct modeline at document start
    it("should add correct modeline even if different schema modeline exists", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "---",
        "apiVersion: external-secrets.io/v1",
        "kind: ExternalSecret",
        "metadata:",
        "  name: my-secret",
        "spec:",
        "  data: []",
        "# yaml-language-server: $schema=https://example.com/wrong-schema.json", -- Different schema!
        "  more: data",
        "---",
      })

      -- Should add the correct modeline because existing one is for different schema
      local result = detector.add_modelines(bufnr)
      eq(1, result.added)
      eq(0, result.skipped)

      -- Verify 2 modelines exist (wrong one + correct one)
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local modeline_count = 0
      for _, line in ipairs(lines) do
        if line:match("yaml%-language%-server.*%$schema=") then
          modeline_count = modeline_count + 1
        end
      end
      eq(2, modeline_count)

      -- First modeline should be at line 2 (document start) with correct URL
      assert.is_truthy(lines[2]:match("externalsecret_v1%.json"))
    end)

    -- Test: verify end_line is tracked correctly for multi-doc
    it("should track document boundaries correctly", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "---", -- 1
        "apiVersion: argoproj.io/v1alpha1", -- 2
        "kind: Application", -- 3
        "metadata:", -- 4
        "  name: app1", -- 5
        "---", -- 6 (separator)
        "apiVersion: external-secrets.io/v1", -- 7
        "kind: ExternalSecret", -- 8
        "metadata:", -- 9
        "  name: secret1", -- 10
        "spec:", -- 11
        "  manyLines: here", -- 12
        "  more: data", -- 13
        "  even: more", -- 14
        "  data: here", -- 15
        "---", -- 16 (separator)
        "apiVersion: apps/v1", -- 17
        "kind: Deployment", -- 18
      })

      local crds = detector.detect_crds(bufnr)
      eq(3, #crds)

      -- First doc: lines 2-5 (separator at 6)
      eq("Application", crds[1].kind)
      eq(2, crds[1].line_number)
      eq(5, crds[1].end_line)

      -- Second doc: lines 7-15 (separator at 16)
      eq("ExternalSecret", crds[2].kind)
      eq(7, crds[2].line_number)
      eq(15, crds[2].end_line)

      -- Third doc: lines 17 to end
      eq("Deployment", crds[3].kind)
      eq(17, crds[3].line_number)
      eq(18, crds[3].end_line)
    end)

    -- Regression test: narrow search range would have caused duplicates
    it("should search entire document to prevent modelines at wrong positions", function()
      -- Create a document with 20+ lines (beyond the old +5 search range)
      local lines = {
        "---",
        "apiVersion: argoproj.io/v1alpha1",
        "kind: Application",
        "metadata:",
        "  name: very-long-document",
      }
      -- Add 15 more lines to make it longer than the old search range
      for i = 1, 15 do
        table.insert(lines, "  line" .. i .. ": value" .. i)
      end
      table.insert(lines, "---")

      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- First call adds modeline at line 2
      local result1 = detector.add_modelines(bufnr)
      eq(1, result1.added)

      -- Second call should find it even though it's far from target_line
      local result2 = detector.add_modelines(bufnr)
      eq(0, result2.added)
      eq(1, result2.skipped)

      -- Third call to be sure
      local result3 = detector.add_modelines(bufnr)
      eq(0, result3.added)
      eq(1, result3.skipped)

      -- Verify only 1 modeline exists
      local final_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local modeline_count = 0
      for _, line in ipairs(final_lines) do
        if line:match("yaml%-language%-server.*%$schema=") then
          modeline_count = modeline_count + 1
        end
      end
      eq(1, modeline_count)
    end)
  end)
end)
