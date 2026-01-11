<!-- markdownlint-disable MD013 -->

# yaml-companion.nvim

[![Build](https://github.com/mosheavni/yaml-companion.nvim/actions/workflows/main.yml/badge.svg)](https://github.com/mosheavni/yaml-companion.nvim/actions/workflows/main.yml)
[![Lint](https://github.com/mosheavni/yaml-companion.nvim/actions/workflows/super-linter.yml/badge.svg)](https://github.com/mosheavni/yaml-companion.nvim/actions/workflows/super-linter.yml)
[![Neovim](https://img.shields.io/badge/Neovim-0.11+-blueviolet.svg?logo=neovim)](https://neovim.io)

![statusbar](https://github.com/user-attachments/assets/15ea0970-d155-4a58-9d2c-a4a02417f6ba)

## ⚡️ Requirements

- Neovim 0.11+
- [yaml-language-server](https://github.com/redhat-developer/yaml-language-server)

## ✨ Features

- Builtin Kubernetes manifest autodetection
- Get/Set specific JSON schema per buffer
- Extendable autodetection + Schema Store support
- CRD modeline support with [Datree CRD catalog](https://github.com/datreeio/CRDs-catalog) integration
- Auto-detect Custom Resource Definitions and add schema modelines

## 📦 Installation

Install the plugin with your preferred package manager:

### lazy.nvim

```lua
{
  "mosheavni/yaml-companion.nvim",
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

### Setup (Neovim 0.11+ required)

```lua
local cfg = require("yaml-companion").setup({
  -- Add any options here, or leave empty to use the default settings
  -- lspconfig = {
  --   settings = { ... }
  -- },
})
vim.lsp.config("yamlls", cfg)
vim.lsp.enable("yamlls")
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

## Modeline Features

yaml-companion provides tools for working with YAML modelines (`# yaml-language-server: $schema=...`)
to provide schema support for Custom Resource Definitions (CRDs).

### Datree CRD Schema Picker

Browse the [datreeio/CRDs-catalog](https://github.com/datreeio/CRDs-catalog) and add a modeline to the current buffer:

```lua
require("yaml-companion").open_datree_crd_select()
```

This fetches the catalog from GitHub (cached for 1 hour) and presents a picker to select a CRD schema.
When selected, a modeline is added at the top of your file:

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/argoproj.io/application_v1alpha1.json
apiVersion: argoproj.io/v1alpha1
kind: Application
```

### Auto-detect CRDs

Detect Custom Resource Definitions in the current buffer and add schema modelines automatically:

```lua
-- Add modelines for all detected CRDs
require("yaml-companion").add_crd_modelines()

-- Preview what would be added (dry run)
require("yaml-companion").add_crd_modelines(0, { dry_run = true })

-- Overwrite existing modelines
require("yaml-companion").add_crd_modelines(0, { overwrite = true })
```

This parses the buffer for `kind:` and `apiVersion:` fields, identifies non-core Kubernetes resources,
and adds modelines pointing to the appropriate schema in the Datree CRD catalog.

Core Kubernetes resources (Deployments, Services, ConfigMaps, etc.) are skipped since they're
handled by the builtin kubernetes matcher.

### Modeline Configuration

```lua
require("yaml-companion").setup({
  -- Modeline features
  modeline = {
    auto_add = {
      on_attach = false, -- Auto-add modelines when yamlls attaches
      on_save = false, -- Auto-add modelines before saving
    },
    overwrite_existing = false, -- Whether to overwrite existing modelines
    validate_urls = false, -- Check if schema URL exists (slower)
    notify = true, -- Show notifications when modelines are added
  },

  -- Datree CRD catalog settings
  datree = {
    cache_ttl = 3600, -- Cache catalog for 1 hour (0 = no cache)
    raw_content_base = "https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/",
  },

  -- Customize which API groups are considered "core" (skipped by CRD detection)
  -- These are handled by the builtin kubernetes matcher
  core_api_groups = {
    [""] = true,
    ["apps"] = true,
    ["batch"] = true,
    ["networking.k8s.io"] = true,
    -- ... add or remove as needed
  },
})
```
