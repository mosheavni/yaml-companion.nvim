local M = {}

local _matchers = require("yaml-companion._matchers")
M.ctx = {}

M.setup = function(opts)
  local config = require("yaml-companion.config")
  local context = require("yaml-companion.context")

  local function on_attach(client, bufnr)
    context.setup(bufnr, client)
  end

  config.setup(opts, on_attach)
  M.ctx = context

  -- Track which clients we've already notified
  local notified_clients = {}

  -- Register LspAttach autocmd for native vim.lsp.config/vim.lsp.enable support
  -- This ensures context.setup is called regardless of how yamlls is started
  vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("yaml-companion", { clear = true }),
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if client and client.name == "yamlls" then
        -- Send schema selection notification if we haven't already for this client
        -- This is needed for native vim.lsp.config where on_init might not be called
        if not notified_clients[client.id] then
          notified_clients[client.id] = true
          client:notify("yaml/supportSchemaSelection", { {} })
        end
        on_attach(client, args.buf)
      end
    end,
  })

  require("yaml-companion.log").new({ level = config.options.log_level }, true)
  return config.options.lspconfig
end

--- Set the schema used for a buffer.
---@param bufnr number: Buffer number
---@param schema SchemaResult | Schema
M.set_buf_schema = function(bufnr, schema)
  M.ctx.schema(bufnr, schema)
end

--- Get the schema used for a buffer.
---@param bufnr number: Buffer number
M.get_buf_schema = function(bufnr)
  -- TODO: remove the result and instead return a Schema directly
  -- this will break existing clients :/
  return { result = { M.ctx.schema(bufnr) } }
end

--- Loads a matcher.
---@param name string: Name of the matcher
M.load_matcher = function(name)
  return _matchers.load(name)
end

--- Opens a vim.ui.select menu to choose a schema
M.open_ui_select = function()
  require("yaml-companion.select.ui").open_ui_select()
end

return M
