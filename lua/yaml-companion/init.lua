local M = {}

local _matchers = require("yaml-companion._matchers")
M.ctx = {}

M.setup = function(opts)
  local config = require("yaml-companion.config")
  local context = require("yaml-companion.context")

  local function on_attach(client, bufnr)
    context.setup(bufnr, client)

    -- Auto-add modelines on attach if configured
    if
      config.options.modeline
      and config.options.modeline.auto_add
      and config.options.modeline.auto_add.on_attach
    then
      vim.schedule(function()
        local crd_detector = require("yaml-companion.modeline.crd_detector")
        local modeline_opts = { overwrite = config.options.modeline.overwrite_existing }
        -- Use async version if cluster fallback is enabled
        if config.options.cluster_crds and config.options.cluster_crds.fallback then
          crd_detector.add_modelines_with_fallback(bufnr, modeline_opts)
        else
          crd_detector.add_modelines(bufnr, modeline_opts)
        end
      end)
    end
  end

  config.setup(opts, on_attach)
  M.ctx = context

  -- Track which clients we've already notified
  local notified_clients = {}

  -- Create augroup for yaml-companion autocmds
  local augroup = vim.api.nvim_create_augroup("yaml-companion", { clear = true })

  -- Register LspAttach autocmd for native vim.lsp.config/vim.lsp.enable support
  -- This ensures context.setup is called regardless of how yamlls is started
  vim.api.nvim_create_autocmd("LspAttach", {
    group = augroup,
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if client and client.name == "yamlls" then
        -- Send schema selection notification if we haven't already for this client
        -- This is needed for native vim.lsp.config where on_init might not be called
        if not notified_clients[client.id] then
          notified_clients[client.id] = true
          ---@diagnostic disable-next-line: param-type-mismatch
          client:notify("yaml/supportSchemaSelection", { {} })
        end
        on_attach(client, args.buf)
      end
    end,
  })

  -- Auto-add modelines on save if configured
  if
    config.options.modeline
    and config.options.modeline.auto_add
    and config.options.modeline.auto_add.on_save
  then
    vim.api.nvim_create_autocmd("BufWritePre", {
      group = augroup,
      pattern = { "*.yaml", "*.yml" },
      callback = function(args)
        local crd_detector = require("yaml-companion.modeline.crd_detector")
        local modeline_opts = { overwrite = config.options.modeline.overwrite_existing }
        -- Use async version if cluster fallback is enabled
        if config.options.cluster_crds and config.options.cluster_crds.fallback then
          crd_detector.add_modelines_with_fallback(args.buf, modeline_opts)
        else
          crd_detector.add_modelines(args.buf, modeline_opts)
        end
      end,
    })
  end

  require("yaml-companion.log").new({ level = config.options.log_level }, true)

  -- Register :YamlKeys user command if key navigation is enabled
  if config.options.keys and config.options.keys.enabled then
    vim.api.nvim_create_user_command("YamlKeys", function()
      require("yaml-companion.keys").quickfix(0, { open = true })
    end, {
      desc = "List all YAML keys in quickfix",
    })
  end

  -- Register cluster CRD commands if feature is enabled
  if config.options.cluster_crds and config.options.cluster_crds.enabled then
    vim.api.nvim_create_user_command("YamlFetchClusterCRD", function()
      require("yaml-companion.kubectl").fetch_from_buffer()
    end, {
      desc = "Fetch CRD schema from Kubernetes cluster",
    })

    vim.api.nvim_create_user_command("YamlBrowseClusterCRDs", function()
      require("yaml-companion.kubectl").open_crd_select()
    end, {
      desc = "Browse and select CRD schemas from Kubernetes cluster",
    })
  end

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

--- Opens a vim.ui.select menu to browse Datree CRD catalog and add modeline
M.open_datree_crd_select = function()
  require("yaml-companion.modeline.datree").open_select()
end

--- Detect CRDs in a buffer and add schema modelines for non-core resources
---@param bufnr? number Buffer number (defaults to current buffer)
---@param options? { dry_run: boolean, overwrite: boolean }
---@return { added: number, skipped: number, errors: string[] }
M.add_crd_modelines = function(bufnr, options)
  bufnr = bufnr or 0
  return require("yaml-companion.modeline.crd_detector").add_modelines(bufnr, options)
end

--- Get modeline info from a buffer
---@param bufnr? number Buffer number (defaults to current buffer)
---@return ModelineInfo|nil
M.get_modeline = function(bufnr)
  return require("yaml-companion.modeline").find_modeline(bufnr or 0)
end

--- Get all YAML keys in quickfix list
--- Requires treesitter YAML parser to be installed (:TSInstall yaml)
---@param bufnr? number Buffer number (defaults to current buffer)
---@param opts? { open: boolean } Options (open=true to open quickfix window, default: true)
---@return YamlQuickfixEntry[] entries List of quickfix entries
M.get_keys_quickfix = function(bufnr, opts)
  return require("yaml-companion.keys").quickfix(bufnr, opts)
end

--- Get key at cursor position
--- Requires treesitter YAML parser to be installed (:TSInstall yaml)
---@return YamlKeyInfo|nil info Key info at cursor, or nil if not found
M.get_key_at_cursor = function()
  return require("yaml-companion.keys").at_cursor()
end

--- Fetch CRD schema from cluster for current buffer
--- Requires kubectl to be installed and configured
---@param bufnr? number Buffer number (defaults to current buffer)
M.fetch_cluster_crd = function(bufnr)
  require("yaml-companion.kubectl").fetch_from_buffer(bufnr)
end

--- Open picker to browse CRDs in cluster
--- Requires kubectl to be installed and configured
M.open_cluster_crd_select = function()
  require("yaml-companion.kubectl").open_crd_select()
end

return M
