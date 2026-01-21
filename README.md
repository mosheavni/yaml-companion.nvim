<!-- markdownlint-disable MD013 -->

# yaml-companion.nvim

[![Build](https://github.com/mosheavni/yaml-companion.nvim/actions/workflows/main.yml/badge.svg)](https://github.com/mosheavni/yaml-companion.nvim/actions/workflows/main.yml)
[![Lint](https://github.com/mosheavni/yaml-companion.nvim/actions/workflows/lint.yml/badge.svg)](https://github.com/mosheavni/yaml-companion.nvim/actions/workflows/lint.yml)
[![Neovim](https://img.shields.io/badge/Neovim-0.11+-blueviolet.svg?logo=neovim)](https://neovim.io)

![completion](https://github.com/user-attachments/assets/40509084-c69a-4c8d-8380-9149b439b7ad)
![schema-auto-detect](https://github.com/user-attachments/assets/dc8fd636-aac2-42d2-b3dd-9aa306221d6d)

## Table of Contents

- [Requirements](#️-requirements)
- [Features](#-features)
- [Installation](#-installation)
- [Configuration](#️-configuration)
- [Features & Usage](#-features--usage)
  - [Schema Selection](#schema-selection)
  - [Key Navigation](#key-navigation)
  - [Modeline Features](#modeline-features)
  - [Cluster CRD Integration](#cluster-crd-integration)
  - [Caching](#caching)
- [Commands](#️-commands)
- [Lua API](#lua-api)
- [Health Check](#-health-check)
- [History](#-history)

## ⚡️ Requirements

- Neovim 0.11+
- [yaml-language-server](https://github.com/redhat-developer/yaml-language-server)
- `kubectl` (optional) - for fetching CRD schemas from your Kubernetes cluster
- Treesitter YAML parser (optional) - for key navigation features (`:TSInstall yaml`)

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
  opts = {
    -- Add any options here, or leave empty to use the default settings
    -- lspconfig = {
    --   settings = { ... }
    -- },
  },
  config = function(_, opts)
    local cfg = require("yaml-companion").setup(opts)
    vim.lsp.config("yamlls", cfg)
    vim.lsp.enable("yamlls")
  end,
}
```

## ⚙️ Configuration

**yaml-companion** comes with the following defaults (pass these to `opts`):

```lua
{
  -- Shared cache directory for all cached data (datree catalog, cluster CRD schemas)
  cache_dir = nil, -- Override location (default: stdpath("data")/yaml-companion.nvim/)

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

  -- Key navigation features
  keys = {
    enabled = true, -- Enable key navigation features (creates :YamlKeys command)
    include_values = false, -- Show values in quickfix entries
    max_value_length = 50, -- Truncate long values in display
  },

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
    cache_ttl = 3600, -- Cache TTL in seconds (0 = never expire, -1 = disable)
    raw_content_base = "https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/",
  },

  -- Cluster CRD features
  cluster_crds = {
    enabled = true, -- Enable cluster CRD features
    fallback = false, -- Auto-fallback to cluster when Datree doesn't have schema
    cache_ttl = 86400, -- Cache expiration in seconds (default: 24h, 0 = never expire)
  },

  -- Customize which API groups are considered "core" (skipped by CRD detection)
  core_api_groups = {
    [""] = true,
    ["apps"] = true,
    ["batch"] = true,
    ["networking.k8s.io"] = true,
    -- ... add or remove as needed
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

## 🚀 Features & Usage

### Schema Selection

yaml-companion automatically detects and applies JSON schemas to your YAML files. Schemas are resolved from multiple sources in this order:

1. **LSP-provided schema** - from yaml-language-server
2. **User-defined schemas** - from your config's `schemas` table
3. **Matcher-detected schemas** - builtin matchers for Kubernetes and cloud-init
4. **SchemaStore schemas** - from the JSON Schema Store

#### Automatic Detection

**Kubernetes:** Detects Kubernetes manifests by scanning for `kind:` and `apiVersion:` fields. Core resources (Deployments, Services, ConfigMaps, etc.) are matched to the appropriate Kubernetes JSON schema.

**Cloud-init:** Detects cloud-config files by checking for `#cloud-config` header comment.

Both matchers can be disabled via config:

```lua
builtin_matchers = {
  kubernetes = { enabled = false },
  cloud_init = { enabled = false },
}
```

#### Manual Selection

Open a picker to manually select from all available schemas:

```lua
require("yaml-companion").open_ui_select()
```

This uses `vim.ui.select` so you can use the picker of your choice (e.g., with [dressing.nvim](https://github.com/stevearc/dressing.nvim)).

#### Progress Notifications

![fidget-schema](https://github.com/user-attachments/assets/951534cd-651e-4bed-af39-804fd1fa0780)

When a schema is applied (either automatically or manually), yaml-companion sends LSP progress notifications (`$/progress`). This integrates with progress UI plugins like [fidget.nvim](https://github.com/j-hui/fidget.nvim), showing a brief "YAML Schema: \<schema_name\> schema applied" message.

#### Statusline Integration

Show the current schema in your statusline:

```lua
local function get_schema()
  local schema = require("yaml-companion").get_buf_schema(0)
  if schema.result[1].name == "none" then
    return ""
  end
  return schema.result[1].name
end
```

---

### Key Navigation

Navigate YAML keys using treesitter. Requires the YAML treesitter parser (`:TSInstall yaml`).

#### Quickfix List

Get all YAML keys in a quickfix list for easy navigation:

```vim
:YamlKeys
```

Or via Lua:

```lua
require("yaml-companion").get_keys_quickfix()
```

Each entry shows the full dotted key path:

- `.metadata.name`
- `.spec.containers[0].image`
- `.spec.replicas`

#### Get Key at Cursor

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

**Example keymaps:**

```lua
vim.keymap.set("n", "<leader>yk", function()
  local info = require("yaml-companion").get_key_at_cursor()
  if info then
    vim.fn.setreg("+", info.key)
    vim.notify("Copied: " .. info.key)
  end
end, { desc = "Copy YAML key path" })

vim.keymap.set("n", "<leader>yv", function()
  local info = require("yaml-companion").get_key_at_cursor()
  if info and info.value then
    vim.fn.setreg("+", info.value)
    vim.notify("Copied: " .. info.value)
  end
end, { desc = "Copy YAML value" })
```

---

### Modeline Features

Modelines are special YAML comments that tell yaml-language-server which schema to use:

```yaml
# yaml-language-server: $schema=https://example.com/schema.json
apiVersion: v1
kind: ConfigMap
```

Modelines persist in the file, ensuring everyone editing it gets the same schema support.

#### Browse Datree Schemas

Browse the [datreeio/CRDs-catalog](https://github.com/datreeio/CRDs-catalog) and select a schema:

```vim
:YamlBrowseDatreeSchemas
```

Or via Lua:

```lua
require("yaml-companion").open_datree_crd_select()
```

This opens a picker to select a CRD schema, then asks how to apply it:

- **Add as modeline (persisted in file)** - Adds a comment at the top of your file
- **Set as LSP schema (session only)** - Sends schema to yamlls for the current buffer

**Direct action (skip the second prompt):**

```vim
:YamlBrowseDatreeSchemas modeline  " Add as modeline
:YamlBrowseDatreeSchemas lsp       " Set as LSP schema
```

Or via Lua:

```lua
require("yaml-companion").open_datree_crd_select("modeline")
require("yaml-companion").open_datree_crd_select("lsp")
```

#### Auto-detect CRDs

Detect Custom Resource Definitions in the current buffer and add schema modelines automatically:

```vim
:YamlAddCRDModelines
```

Or via Lua:

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

**Enable automatic modeline addition:**

```lua
modeline = {
  auto_add = {
    on_attach = true, -- Auto-add modelines when yamlls attaches
    on_save = true, -- Auto-add modelines before saving
  },
}
```

---

### Cluster CRD Integration

For CRDs that are not available in the Datree catalog (e.g., custom/internal CRDs specific to your organization),
yaml-companion can fetch schemas directly from your Kubernetes cluster using `kubectl`.

#### Setup

Enable cluster CRD features in your config:

```lua
cluster_crds = {
  enabled = true,
}
```

Requirements:

- `kubectl` must be installed and in your PATH
- kubectl must be configured with access to your cluster
- The CRDs must be installed in your cluster

#### Fetch CRD for Current Buffer

Fetch the schema for CRDs detected in your current buffer:

```vim
:YamlFetchClusterCRD
```

Or via Lua:

```lua
require("yaml-companion").fetch_cluster_crd(0)
```

This command:

1. Detects CRDs in your buffer (by parsing `apiVersion` and `kind`)
2. Looks up the CRD in your cluster via `kubectl get crd`
3. Extracts the OpenAPI schema from the CRD
4. Caches it locally
5. Adds a modeline pointing to the cached schema

#### Browse All Cluster CRDs

Browse and select from all CRDs installed in your cluster:

```vim
:YamlBrowseClusterCRDs
```

Or via Lua:

```lua
require("yaml-companion").open_cluster_crd_select()
```

This opens a picker showing all CRDs in your cluster. After selecting, you choose how to apply it:

- **Add as modeline (persisted in file)** - Adds a comment at the top of your file
- **Set as LSP schema (session only)** - Sends schema to yamlls for the current buffer

**Direct action (skip the second prompt):**

```vim
:YamlBrowseClusterCRDs modeline  " Add as modeline
:YamlBrowseClusterCRDs lsp       " Set as LSP schema
```

Or via Lua:

```lua
require("yaml-companion").open_cluster_crd_select("modeline")
require("yaml-companion").open_cluster_crd_select("lsp")
```

#### Auto-Fallback Mode

Enable automatic fallback to cluster CRD fetching when Datree doesn't have a schema:

```lua
cluster_crds = {
  enabled = true,
  fallback = true, -- Auto-fallback to cluster when Datree doesn't have schema
},
modeline = {
  auto_add = {
    on_attach = true, -- or on_save = true
  },
}
```

With this setup:

1. When a CRD is detected, yaml-companion first checks the Datree catalog
2. If Datree doesn't have the schema, it automatically fetches from your cluster
3. The schema is cached locally for future use

> [!NOTE]
> When `fallback = true`, `modeline.validate_urls` is automatically set to `true` (to check if
> Datree URLs exist before using them). If you explicitly set `validate_urls = false` while `fallback = true`,
> the plugin will throw an error at startup.

---

### Caching

yaml-companion caches data to improve performance and enable offline usage.

#### Cache Location

By default, caches are stored in:

```tree
~/.local/share/nvim/yaml-companion.nvim/
├── crd-cache/          # Cluster CRD schemas (per kubectl context)
│   └── <context>/
│       └── <crd-name>.json
└── datree-catalog.json # Datree CRD catalog index
```

Override the location:

```lua
cache_dir = "/path/to/custom/cache",
```

#### Cache TTL

Configure how long cached data remains valid:

```lua
datree = {
  cache_ttl = 3600, -- Datree catalog TTL in seconds (default: 1 hour)
                    -- 0 = never expire, -1 = disable caching
},
cluster_crds = {
  cache_ttl = 86400, -- Cluster CRD schemas TTL (default: 24 hours)
                     -- 0 = never expire
},
```

#### Clearing Cache

To manually clear the cache, delete the cache directory:

```bash
rm -rf ~/.local/share/nvim/yaml-companion.nvim/
```

Or clear only cluster CRD schemas:

```bash
rm -rf ~/.local/share/nvim/yaml-companion.nvim/crd-cache/
```

## ⌨️ Commands

| Command                             | Description                                                                          |
| ----------------------------------- | ------------------------------------------------------------------------------------ |
| `:YamlKeys`                         | Open quickfix with all YAML keys in the buffer                                       |
| `:YamlBrowseDatreeSchemas [action]` | Browse Datree CRD catalog. Optional: `modeline` or `lsp` to skip action prompt       |
| `:YamlAddCRDModelines`              | Detect CRDs in buffer and add schema modelines                                       |
| `:YamlFetchClusterCRD`              | Fetch CRD schema from Kubernetes cluster for current buffer                          |
| `:YamlBrowseClusterCRDs [action]`   | Browse all CRDs in your cluster. Optional: `modeline` or `lsp` to skip action prompt |

## Lua API

All public functions are available via `require("yaml-companion")`:

| Function                           | Description                                                                                            |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `setup(opts)`                      | Initialize the plugin with configuration options                                                       |
| `get_buf_schema(bufnr)`            | Get the current schema for a buffer                                                                    |
| `set_buf_schema(bufnr, schema)`    | Set the schema for a buffer                                                                            |
| `open_ui_select()`                 | Open schema picker (all available schemas)                                                             |
| `open_datree_crd_select(action?)`  | Browse Datree catalog. If action is nil, prompts user; if `"modeline"` or `"lsp"`, applies directly    |
| `open_cluster_crd_select(action?)` | Browse CRDs from cluster. If action is nil, prompts user; if `"modeline"` or `"lsp"`, applies directly |
| `fetch_cluster_crd(bufnr)`         | Fetch CRD schema from cluster for buffer                                                               |
| `add_crd_modelines(bufnr, opts)`   | Auto-detect CRDs and add modelines                                                                     |
| `get_modeline(bufnr)`              | Get modeline info from a buffer                                                                        |
| `get_keys_quickfix(bufnr, opts)`   | Get all YAML keys in quickfix format                                                                   |
| `get_key_at_cursor()`              | Get key info at current cursor position                                                                |
| `load_matcher(name)`               | Load a custom matcher                                                                                  |

## 🩺 Health Check

Run `:checkhealth yaml-companion` to verify your setup:

- yaml-language-server availability
- kubectl availability (for cluster CRD features)
- Treesitter YAML parser (for key navigation)
- Cluster connectivity

## 📜 History

This repository was originally forked from [someone-stole-my-name/yaml-companion.nvim](https://github.com/someone-stole-my-name/yaml-companion.nvim). It has since been unforked and is now maintained independently. The original commit history has been preserved.
