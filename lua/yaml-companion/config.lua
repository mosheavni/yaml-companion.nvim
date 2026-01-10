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
  builtin_matchers = {
    kubernetes = { enabled = true },
    cloud_init = { enabled = true },
  },
  schemas = {},
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

function M.setup(options, on_attach)
  if options == nil then
    options = {}
  end

  if options.lspconfig == nil then
    options.lspconfig = {}
  end

  M.options = vim.tbl_deep_extend("force", M.options, options or {})

  M.options.lspconfig.on_attach = add_hook_after(options.lspconfig.on_attach, on_attach)

  local all_schemas = vim.deepcopy(M.options.schemas)
  -- Handle legacy format: { result = { schema1, schema2, ... } }
  if all_schemas.result and type(all_schemas.result) == "table" then
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
  M.options.lspconfig.handlers = handlers

  -- Also register globally for native vim.lsp.config/vim.lsp.enable support
  vim.lsp.handlers["yaml/schema/store/initialized"] = store_initialized_handler
end

return M
