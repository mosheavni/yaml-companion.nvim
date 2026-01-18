local M = {}
local handlers = require("vim.lsp.handlers")
local matchers = require("yaml-companion._matchers")

--- Chains two callbacks, running the hook after the original
---@param original function|nil
---@param hook function
---@return function
local function add_hook_after(original, hook)
  if original then
    return function(...)
      original(...)
      return hook(...)
    end
  else
    return hook
  end
end

---@type ConfigOptions
M.defaults = {
  log_level = "info",
  formatting = true,
  -- Shared cache directory for all cached data (datree catalog, cluster CRD schemas)
  cache_dir = nil, -- Override location (default: stdpath("data")/yaml-companion.nvim/)
  builtin_matchers = {
    kubernetes = { enabled = true },
    cloud_init = { enabled = true },
  },
  schemas = {},
  -- Modeline features configuration
  modeline = {
    auto_add = {
      on_attach = false, -- Auto-add modelines when yamlls attaches
      on_save = false, -- Auto-add modelines on BufWritePre
    },
    overwrite_existing = false, -- Whether to overwrite existing modelines
    validate_urls = false, -- HTTP HEAD check before adding (slower)
    notify = true, -- Show notifications when modelines are added
  },
  -- Datree CRD catalog settings
  datree = {
    cache_ttl = 3600, -- Cache TTL in seconds (0 = no cache, for both memory and file cache)
    raw_content_base = "https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/",
  },
  -- Cluster CRD fetching configuration
  cluster_crds = {
    enabled = true, -- Enable cluster CRD features
    fallback = false, -- Auto-fallback to cluster when Datree fails
    cache_ttl = 86400, -- Cache expiration in seconds (default: 24h, 0 = never expire)
  },
  -- Key navigation features configuration
  keys = {
    enabled = true, -- Enable key navigation features
    include_values = false, -- Show values in quickfix entries
    max_value_length = 50, -- Truncate values longer than this in display
  },
  -- Core API groups to skip (configurable by users)
  -- These are handled by the builtin kubernetes matcher
  core_api_groups = {
    [""] = true,
    ["admissionregistration.k8s.io"] = true,
    ["apiextensions.k8s.io"] = true,
    ["apps"] = true,
    ["autoscaling"] = true,
    ["batch"] = true,
    ["certificates.k8s.io"] = true,
    ["coordination.k8s.io"] = true,
    ["discovery.k8s.io"] = true,
    ["events.k8s.io"] = true,
    ["flowcontrol.apiserver.k8s.io"] = true,
    ["networking.k8s.io"] = true,
    ["node.k8s.io"] = true,
    ["policy"] = true,
    ["rbac.authorization.k8s.io"] = true,
    ["scheduling.k8s.io"] = true,
    ["storage.k8s.io"] = true,
  },
  lspconfig = {
    flags = {
      debounce_text_changes = 150,
    },
    single_file_support = true,
    settings = {
      redhat = { telemetry = { enabled = false } },
      yaml = {
        validate = true,
        format = { enable = true },
        hover = true,
        schemaStore = {
          enable = true,
          url = "https://www.schemastore.org/api/json/catalog.json",
        },
        schemaDownload = { enable = true },
        schemas = { result = {} },
        trace = { server = "debug" },
      },
    },
  },
}

---@type ConfigOptions
M.options = vim.deepcopy(M.defaults)

function M.setup(options)
  if options == nil then
    options = {}
  end

  if options.lspconfig == nil then
    options.lspconfig = {}
  end

  ---@type ConfigOptions
  M.options = vim.tbl_deep_extend("force", M.options, options or {})

  -- Validate cluster_crds.fallback and modeline.validate_urls configuration
  if M.options.cluster_crds and M.options.cluster_crds.fallback then
    -- Check if user explicitly set validate_urls to false
    local user_explicitly_set_validate_urls = options.modeline
      and options.modeline.validate_urls ~= nil
    local user_set_validate_urls_false = user_explicitly_set_validate_urls
      and options.modeline.validate_urls == false

    if user_set_validate_urls_false then
      error(
        "yaml-companion: Invalid configuration - cluster_crds.fallback=true requires "
          .. "modeline.validate_urls=true. Cannot explicitly set validate_urls=false when fallback is enabled."
      )
    end

    -- Auto-enable validate_urls when fallback is true
    M.options.modeline.validate_urls = true
  end

  -- Preserve user's on_attach callback if provided
  -- yaml-companion's setup runs via LspAttach autocmd, not through lspconfig on_attach
  M.options.lspconfig.on_attach = options.lspconfig.on_attach

  local all_schemas = vim.deepcopy(M.options.schemas)
  -- Handle legacy format: { result = { schema1, schema2, ... } }
  if all_schemas and all_schemas.result and type(all_schemas.result) == "table" then
    all_schemas = all_schemas.result
  end
  local collected_uris = {}
  M.options.schemas = {}
  for _, schema in pairs(all_schemas) do
    if not schema.uri then
      schema.uri = schema["url"] -- legacy fallback
    end
    if not collected_uris[schema.uri] then
      vim.list_extend(M.options.schemas, { schema })
      collected_uris[schema.uri] = true
    end
  end

  M.options.lspconfig.on_init = add_hook_after(options.lspconfig.on_init, function(client)
    client:notify("yaml/supportSchemaSelection", { {} })
    return true
  end)

  for name, matcher in pairs(M.options.builtin_matchers) do
    if matcher.enabled then
      matchers.load(name)
    end
  end

  local store_initialized_handler = require("yaml-companion.lsp.handler").store_initialized

  -- Register handler both in lspconfig options (for lspconfig users)
  -- and globally (for native vim.lsp.config users)
  handlers["yaml/schema/store/initialized"] = store_initialized_handler

  -- Merge user's handlers with the required yaml-companion handler
  -- User's handlers take precedence for any conflicts
  local user_handlers = options.lspconfig.handlers or {}
  M.options.lspconfig.handlers = vim.tbl_deep_extend(
    "force",
    { ["yaml/schema/store/initialized"] = store_initialized_handler },
    user_handlers
  )

  -- Also register globally for native vim.lsp.config/vim.lsp.enable support
  vim.lsp.handlers["yaml/schema/store/initialized"] = store_initialized_handler
end

return M
