<!-- markdownlint-disable MD013 -->

# yaml-companion.nvim

[![Build](https://github.com/mosheavni/yaml-companion.nvim/actions/workflows/main.yml/badge.svg)](https://github.com/mosheavni/yaml-companion.nvim/actions/workflows/main.yml)
[![Lint](https://github.com/mosheavni/yaml-companion.nvim/actions/workflows/super-linter.yml/badge.svg)](https://github.com/mosheavni/yaml-companion.nvim/actions/workflows/super-linter.yml)
[![Neovim](https://img.shields.io/badge/Neovim-0.11+-blueviolet.svg?logo=neovim)](https://neovim.io)

![statusbar](https://github.com/user-attachments/assets/15ea0970-d155-4a58-9d2c-a4a02417f6ba)

## ⚡️ Requirements

- Neovim 0.11+
- [yaml-language-server](https://github.com/redhat-developer/yaml-language-server)
- `kubectl` (optional) - for fetching CRD schemas from your Kubernetes cluster

## ✨ Features

- Builtin Kubernetes manifest autodetection
- Get/Set specific JSON schema per buffer
- Extendable autodetection + Schema Store support
- CRD modeline support with [Datree CRD catalog](https://github.com/datreeio/CRDs-catalog) integration
- Auto-detect Custom Resource Definitions and add schema modelines
- Fetch CRD schemas directly from your Kubernetes cluster (for CRDs not in Datree)
- Key navigation: Browse all YAML keys in quickfix, get key/value at cursor

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

## Commands

| Command | Description |
|---------|-------------|
| `:YamlKeys` | Open quickfix with all YAML keys in the buffer |
| `:YamlFetchClusterCRD` | Fetch CRD schema from Kubernetes cluster for current buffer |
| `:YamlBrowseClusterCRDs` | Browse all CRDs in your cluster and select one to fetch |

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

## Key Navigation

Navigate YAML keys using treesitter. Requires the YAML treesitter parser (`:TSInstall yaml`).

### Quickfix List

Get all YAML keys in a quickfix list for easy navigation:

```lua
-- Open quickfix with all keys
require("yaml-companion").get_keys_quickfix()

-- Or use the command
:YamlKeys
```

Each entry shows the full dotted key path:

- `.metadata.name`
- `.spec.containers[0].image`
- `.spec.replicas`

### Get Key at Cursor (API)

Get the YAML key and value at the current cursor position:

```lua
local info = require("yaml-companion").get_key_at_cursor()
if info then
  print(info.key) -- ".spec.containers[0].name"
  print(info.value) -- "my-container"
  print(info.human) -- ".spec.containers[0].name = my-container"
  print(info.line) -- 15
  print(info.col) -- 5
end
```

This API is useful for building custom integrations. For example, to copy the current key path to clipboard:

```lua
vim.keymap.set("n", "<leader>yk", function()
  local info = require("yaml-companion").get_key_at_cursor()
  if info then
    vim.fn.setreg("+", info.key)
    vim.notify("Copied: " .. info.key)
  end
end, { desc = "Copy YAML key path" })

-- Or to copy the value:
vim.keymap.set("n", "<leader>yv", function()
  local info = require("yaml-companion").get_key_at_cursor()
  if info and info.value then
    vim.fn.setreg("+", info.value)
    vim.notify("Copied: " .. info.value)
  end
end, { desc = "Copy YAML value" })
```

### Key Navigation Configuration

```lua
require("yaml-companion").setup({
  keys = {
    enabled = true, -- Enable key navigation features (creates :YamlKeys command)
    include_values = false, -- Show values in quickfix entries (default: false)
    max_value_length = 50, -- Truncate long values in display (when include_values = true)
  },
})
```

**Note:** Treesitter with YAML parser is required. Check with `:checkhealth yaml-companion`.

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

## Cluster CRD Schemas

For CRDs that are not available in the Datree catalog (e.g., custom/internal CRDs specific to your cluster),
yaml-companion can fetch schemas directly from your Kubernetes cluster using `kubectl`.

### Requirements

- `kubectl` must be installed and configured with access to your cluster
- The CRDs must be installed in your cluster

### Usage

**Fetch schema for CRDs detected in current buffer:**

```vim
:YamlFetchClusterCRD
```

This command:
1. Detects CRDs in your current buffer (by parsing `apiVersion` and `kind`)
2. Looks up the CRD in your cluster
3. Extracts the OpenAPI schema from the CRD
4. Caches it locally
5. Adds a modeline pointing to the cached schema

**Browse all CRDs in your cluster:**

```vim
:YamlBrowseClusterCRDs
```

This opens a picker showing all CRDs installed in your cluster. Select one to fetch its schema.

### Programmatic API

```lua
-- Fetch CRD schema for current buffer
require("yaml-companion").fetch_cluster_crd()

-- Open cluster CRD picker
require("yaml-companion").open_cluster_crd_select()
```

### Configuration

```lua
require("yaml-companion").setup({
  cluster_crds = {
    enabled = true,   -- Enable cluster CRD features (default: true)
    fallback = false, -- Auto-fallback to cluster when Datree doesn't have schema
    cache_dir = nil,  -- Override cache location (default: stdpath("data")/yaml-companion.nvim/crd-cache/)
    cache_ttl = 86400, -- Cache expiration in seconds (default: 24h, 0 = never expire)
  },
})
```

### How It Works

1. When you run `:YamlFetchClusterCRD`, the plugin parses your buffer to find `kind:` and `apiVersion:` fields
2. It maps these to a CRD name (e.g., `Application` with `argoproj.io/v1alpha1` → `applications.argoproj.io`)
3. It runs `kubectl get crd <name> -o json` to fetch the CRD definition
4. It extracts the OpenAPI v3 schema from the CRD's stored version
5. The schema is cached locally at `~/.local/share/nvim/yaml-companion.nvim/crd-cache/<context>/`
6. A modeline is added to your file: `# yaml-language-server: $schema=file:///path/to/cached/schema.json`

### Auto-Fallback Mode

If you enable `cluster_crds.fallback = true`, the plugin will automatically try to fetch schemas from
your cluster when the Datree catalog doesn't have them. This works with the `modeline.auto_add.on_attach`
and `modeline.auto_add.on_save` features.

**Note:** When `fallback = true`, `modeline.validate_urls` is automatically set to `true` (to check if
Datree URLs exist before using them). If you explicitly set `validate_urls = false` while `fallback = true`,
the plugin will throw an error at startup.

### Health Check

Run `:checkhealth yaml-companion` to verify kubectl is available and your cluster is accessible.
