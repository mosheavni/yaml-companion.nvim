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

> All commands and their Lua equivalents are listed in [Commands](#️-commands) and [Lua API](#lua-api).

### Schema Selection

Schemas are auto-detected and applied, resolved from these sources in order:

1. **LSP-provided** — from yaml-language-server
2. **User-defined** — from your config's `schemas` table
3. **Matcher-detected** — builtin Kubernetes and cloud-init matchers
4. **SchemaStore** — from the JSON Schema Store

**Auto-detection:** Kubernetes manifests are detected via `kind:`/`apiVersion:` fields (core resources map to the appropriate Kubernetes schema); cloud-config files via the `#cloud-config` header. Disable either matcher with `builtin_matchers.<name>.enabled = false`.

**Manual selection:** `open_ui_select()` opens a `vim.ui.select` picker of all available schemas (works with any picker, e.g. [dressing.nvim](https://github.com/stevearc/dressing.nvim)).

**Progress notifications:** Applying a schema sends an LSP `$/progress` notification, integrating with UIs like [fidget.nvim](https://github.com/j-hui/fidget.nvim).

**Statusline:**

```lua
local function get_schema()
  local schema = require("yaml-companion").get_buf_schema(0)
  if schema.result[1].name == "none" then
    return ""
  end
  return schema.result[1].name
end
```

### Key Navigation

Navigate YAML keys using treesitter (`:TSInstall yaml`).

- `:YamlKeys` — populate the quickfix list with every key's dotted path (`.spec.containers[0].image`).
- `get_key_at_cursor()` — returns `{ key, value, human, line, col }` for the cursor position.

Example keymap (copy the key path under the cursor):

```lua
vim.keymap.set("n", "<leader>yk", function()
  local info = require("yaml-companion").get_key_at_cursor()
  if info then
    vim.fn.setreg("+", info.key)
  end
end, { desc = "Copy YAML key path" })
```

### Modeline Features

Modelines are YAML comments that pin a schema and persist in the file:

```yaml
# yaml-language-server: $schema=https://example.com/schema.json
```

- `:YamlBrowseDatreeSchemas [modeline|lsp]` — browse the [datreeio/CRDs-catalog](https://github.com/datreeio/CRDs-catalog) and apply a schema. Without an argument you're prompted to add it as a **modeline** (persisted) or set it as the **LSP schema** (session only).
- `:YamlAddCRDModelines` — detect non-core CRDs in the buffer (by `kind:`/`apiVersion:`) and add Datree modelines. Core resources are skipped (handled by the kubernetes matcher).

```lua
require("yaml-companion").add_crd_modelines(0, { dry_run = true }) -- preview
require("yaml-companion").add_crd_modelines(0, { overwrite = true }) -- overwrite existing
```

Add modelines automatically:

```lua
modeline = { auto_add = { on_attach = true, on_save = true } }
```

### Cluster CRD Integration

For CRDs not in the Datree catalog (custom/internal), fetch schemas directly from your cluster via `kubectl` — which must be installed, configured for cluster access, and the CRDs installed.

```lua
cluster_crds = { enabled = true }
```

- `:YamlFetchClusterCRD` — detect CRDs in the buffer, fetch their OpenAPI schema via `kubectl get crd`, cache it, and add a modeline.
- `:YamlBrowseClusterCRDs [modeline|lsp]` — browse all cluster CRDs and apply one (same prompt as Datree).

**Auto-fallback** to the cluster when Datree lacks a schema:

```lua
cluster_crds = { enabled = true, fallback = true },
modeline = { auto_add = { on_attach = true } },
```

> [!NOTE]
> With `fallback = true`, `modeline.validate_urls` is forced to `true`. Explicitly setting `validate_urls = false` alongside `fallback = true` errors at startup.

### Caching

Caches live in `~/.local/share/nvim/yaml-companion.nvim/` — `crd-cache/<context>/<crd>.json` for cluster CRD schemas and `datree-catalog.json` for the Datree index. Override with `cache_dir`.

TTLs (seconds): `datree.cache_ttl` (default `3600`; `0` = never, `-1` = disable) and `cluster_crds.cache_ttl` (default `86400`; `0` = never).

Clear by deleting the directory:

```bash
rm -rf ~/.local/share/nvim/yaml-companion.nvim/
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
