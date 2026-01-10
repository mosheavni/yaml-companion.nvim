---@meta
---@diagnostic disable: duplicate-doc-field

---@class vim.lsp.Client
---@field workspace_did_change_configuration fun(settings: table): boolean|nil

---@class Schema
---@field name string | nil
---@field uri string

---@alias SchemaResult { result: Schema[] }

---@class Matcher
---@field match fun(bufnr: number): Schema | nil
---@field handles fun(): Schema[]
---@field health fun()

---@class ModelineAutoAddConfig
---@field on_attach boolean Auto-add modelines when yamlls attaches
---@field on_save boolean Auto-add modelines on BufWritePre

---@class ModelineConfig
---@field auto_add ModelineAutoAddConfig
---@field overwrite_existing boolean Whether to overwrite existing modelines
---@field validate_urls boolean HTTP HEAD check before adding (slower)

---@class DatreeConfig
---@field cache_ttl number Cache TTL in seconds (0 = no cache)
---@field raw_content_base string Base URL for raw content

---@class ModelineInfo
---@field line_number number Line number where modeline is (1-indexed)
---@field schema_url string The schema URL from the modeline
---@field raw string The raw modeline text

---@class DocumentBoundary
---@field start_line number Start line of document (1-indexed)
---@field end_line number End line of document (1-indexed)

---@class CRDInfo
---@field kind string
---@field apiVersion string
---@field apiGroup string Extracted from apiVersion (e.g., "argoproj.io")
---@field version string Extracted from apiVersion (e.g., "v1alpha1")
---@field line_number number Line where this CRD starts (1-indexed)
---@field is_core boolean True if this is a core K8s resource

---@class AddModelinesResult
---@field added number Number of modelines added
---@field skipped number Number of CRDs skipped (core resources or existing modelines)
---@field errors string[] Any errors encountered

---@class DatreeCatalogEntry
---@field path string e.g., "argoproj.io/application_v1alpha1.json"
---@field name string Display name, e.g., "[datreeio] argoproj.io-application-v1alpha1"
---@field url string Full raw GitHub URL

---@class DatreeCache
---@field entries DatreeCatalogEntry[]
---@field timestamp number os.time() when fetched

---@class ConfigOptions
---@field log_level "debug" | "trace" | "info" | "warn" | "error" | "fatal"
---@field formatting boolean
---@field schemas Schema[] | SchemaResult
---@field lspconfig table
---@field builtin_matchers table
---@field modeline ModelineConfig Modeline features configuration
---@field datree DatreeConfig Datree CRD catalog settings
---@field core_api_groups table<string, boolean> Core API groups to skip

---@class Logger
---@field fmt_debug fun(fmt: string, ...: any)
---@field fmt_error fun(fmt: string, ...: any)
---@field warn fun(message: string)
---@field new fun(config: table, standalone: boolean): Logger
