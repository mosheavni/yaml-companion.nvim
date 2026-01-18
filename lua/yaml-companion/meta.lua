---@meta
---@diagnostic disable: duplicate-doc-field

---@class vim.lsp.Client
---@field workspace_did_change_configuration fun(settings: table): boolean|nil

-- Key navigation types

---@class YamlKeyInfo
---@field key string Full dotted key path (e.g., "root.parent.child" or "items[0].name")
---@field value string|nil Scalar value (nil for nested structures)
---@field human string Human-readable format: "key = value" or "key:"
---@field line number 1-indexed line number where key is defined
---@field col number 1-indexed column number where key starts

---@class YamlQuickfixEntry
---@field bufnr number Buffer number
---@field lnum number Line number (1-indexed)
---@field col number Column number (1-indexed)
---@field text string Display text: "key = value" format

---@class KeysConfig
---@field enabled? boolean Enable key navigation features
---@field include_values? boolean Show values in quickfix entries
---@field max_value_length? number Truncate values longer than this in display

---@class Schema
---@field name string | nil
---@field uri string

---@alias SchemaResult { result: Schema[] }

--- Action type for applying schemas (modeline persists in file, lsp is session-only)
---@alias SchemaAction "modeline" | "lsp"

---@class Matcher
---@field match fun(bufnr: number): Schema | nil
---@field handles fun(): Schema[]
---@field health fun()

---@class ModelineAutoAddConfig
---@field on_attach? boolean Auto-add modelines when yamlls attaches
---@field on_save? boolean Auto-add modelines on BufWritePre

---@class ModelineConfig
---@field auto_add? ModelineAutoAddConfig
---@field overwrite_existing? boolean Whether to overwrite existing modelines
---@field validate_urls? boolean HTTP HEAD check before adding (slower)
---@field notify? boolean Show notifications when modelines are added

---@class DatreeConfig
---@field cache_ttl? number Cache TTL in seconds (0 = no cache)
---@field raw_content_base? string Base URL for raw content

---@class ClusterCrdsConfig
---@field enabled? boolean Enable cluster CRD features
---@field fallback? boolean Auto-fallback to cluster when Datree fails
---@field cache_ttl? number Cache expiration in seconds (default: 24h, 0 = never expire)

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
---@field line_number number Line where this CRD document starts (1-indexed)
---@field end_line number Line where this CRD document ends (1-indexed, before next ---)
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
---@field log_level? "debug" | "trace" | "info" | "warn" | "error" | "fatal"
---@field formatting? boolean
---@field cache_dir? string|nil Shared cache directory (default: stdpath("data")/yaml-companion.nvim/)
---@field schemas? Schema[] | SchemaResult
---@field lspconfig? table
---@field builtin_matchers? table
---@field modeline? ModelineConfig Modeline features configuration
---@field datree? DatreeConfig Datree CRD catalog settings
---@field cluster_crds? ClusterCrdsConfig Cluster CRD fetching configuration
---@field core_api_groups? table<string, boolean> Core API groups to skip
---@field keys? KeysConfig Key navigation features configuration

---@class Logger
---@field fmt_debug fun(fmt: string, ...: any)
---@field fmt_error fun(fmt: string, ...: any)
---@field warn fun(message: string)
---@field new fun(config: table, standalone: boolean): Logger

-- Shared utility types

---@class CacheModule
---@field get_dir fun(subdir: string): string Get cache directory (creates if needed)
---@field get_path fun(subdir: string, filename: string): string Build cache file path
---@field is_valid fun(path: string, ttl: number): boolean Check TTL validity
---@field load_json fun(path: string): table|nil, string|nil Load and parse JSON
---@field save_json fun(path: string, data: table): boolean, string|nil Serialize and save JSON
---@field clear fun(path: string) Remove cache file

---@class NotifyModule
---@field info fun(msg: string) Show info notification
---@field warn fun(msg: string) Show warning notification
---@field error fun(msg: string) Show error notification
---@field debug fun(msg: string) Show debug notification

---@class BufferUtilModule
---@field validate_yaml fun(bufnr: number): boolean, string|nil Check if buffer is YAML
---@field current_yaml_buffer fun(): number|nil, string|nil Get current buffer if YAML

---@class ApplySchemaOpts
---@field line_number? number Line number for modeline insertion (default: 1)
---@field notify? boolean Whether to show notification (default: true)
---@field cached? boolean Whether schema came from cache (for messaging)

---@class SchemaActionModule
---@field ACTIONS table[] Available schema actions
---@field apply fun(bufnr: number, schema: Schema, action: SchemaAction, opts?: ApplySchemaOpts): boolean Apply schema
---@field select_and_apply fun(bufnr: number, schema: Schema, opts?: ApplySchemaOpts, callback?: fun(success: boolean, action: SchemaAction|nil)) Prompt and apply
