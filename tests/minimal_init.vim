set rtp+=.
set rtp+=../plenary.nvim/
set rtp+=../nvim-lspconfig/
set rtp+=tests/dummy_matcher/

runtime! plugin/plenary.vim

lua << EOF
require("yaml-companion").load_matcher("dummy")
vim.lsp.log.set_level("debug")

-- Helper function to setup yamlls with the new vim.lsp.config API
function SetupYamlls(config)
  config = config or {}

  -- Set up custom handlers for yaml-language-server notifications
  if config.handlers then
    for method, handler in pairs(config.handlers) do
      vim.lsp.handlers[method] = handler
    end
  end

  -- Build the merged config
  local merged = {
    cmd = { 'yaml-language-server', '--stdio' },
    filetypes = { 'yaml', 'yaml.docker-compose', 'yaml.gitlab' },
    root_markers = { '.git' },
    settings = config.settings,
    flags = config.flags,
    single_file_support = config.single_file_support,
  }

  -- Set up on_init callback for sending yaml/supportSchemaSelection
  if config.on_init then
    merged.on_init = config.on_init
  end

  -- Set up on_attach callback for context setup
  if config.on_attach then
    merged.on_attach = config.on_attach
  end

  vim.lsp.config('yamlls', merged)
  vim.lsp.enable('yamlls')
end
EOF
