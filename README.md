# yaml-companion.nvim [![Build](https://github.com/mosheavni/yaml-companion.nvim/actions/workflows/main.yml/badge.svg)](https://github.com/mosheavni/yaml-companion.nvim/actions/workflows/main.yml)

![statusbar](https://github.com/user-attachments/assets/15ea0970-d155-4a58-9d2c-a4a02417f6ba)

## ⚡️ Requirements

- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- [yaml-language-server](https://github.com/redhat-developer/yaml-language-server)

## ✨ Features

- Builtin Kubernetes manifest autodetection
- Get/Set specific JSON schema per buffer
- Extendable autodetection + Schema Store support

## 📦 Installation

Install the plugin with your preferred package manager:

### lazy.nvim

```lua
{
  "mosheavni/yaml-companion.nvim",
  dependencies = {
    { "nvim-lua/plenary.nvim" },
  },
}
```

## ⚙️ Configuration

**yaml-companion** comes with the following defaults:

```lua
{
  -- Built in file matchers
  builtin_matchers = {
    -- Detects Kubernetes files based on content
    kubernetes = { enabled = true },
    cloud_init = { enabled = true }
  },

  -- Additional schemas available in the picker
  schemas = {
    --{
      --name = "Kubernetes 1.32.1",
      --uri = "https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/v1.32.1-standalone-strict/all.json",
    --},
  },

  -- Pass any additional options that will be merged in the final LSP config
  lspconfig = {
    flags = {
      debounce_text_changes = 150,
    },
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
        schemas = {},
        trace = { server = "debug" },
      },
    },
  },
}
```

### Using Neovim's native LSP API (Neovim 0.11+)

```lua
local cfg = require("yaml-companion").setup({
  -- Add any options here, or leave empty to use the default settings
  -- lspconfig = {
  --   cmd = {"yaml-language-server"}
  -- },
})
vim.lsp.config("yamlls", cfg)
vim.lsp.enable("yamlls")
```

### Using nvim-lspconfig (legacy)

```lua
local cfg = require("yaml-companion").setup({
  -- Add any options here, or leave empty to use the default settings
  -- lspconfig = {
  --   cmd = {"yaml-language-server"}
  -- },
})
require("lspconfig")["yamlls"].setup(cfg)
```

## 🚀 Usage

### Select a schema for the current buffer

No mappings included, you need to map it yourself or call it manually:

```lua
require("yaml-companion").open_ui_select()
```

This uses `vim.ui.select` so you can use the picker of your choice (e.g., with [dressing.nvim](https://github.com/stevearc/dressing.nvim)).

### Get the schema name for the current buffer

You can show the current schema in your statusline using a function like:

```lua
local function get_schema()
  local schema = require("yaml-companion").get_buf_schema(0)
  if schema.result[1].name == "none" then
    return ""
  end
  return schema.result[1].name
end
```
