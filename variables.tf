variable "project_id" {
  description = "GCP project ID where the BigQuery datasets will be created."
  type        = string
}

variable "country" {
  description = "Short identifier for the country (used in labels and resource descriptions, e.g. \"spain\")."
  type        = string
}

variable "billing_cloud_platform_dataset" {
  description = "Dataset ID for the billing cloud platform dataset."
  type        = string
  default     = "BILLING_CLOUD_PLATFORM"
}

variable "location" {
  description = "BigQuery location (e.g. \"EU\", \"US\", \"europe-west1\")."
  type        = string
  default     = "EU"
}

variable "scheduled_query_service_account" {
  description = "Service account email for workspace_sku_sf and maps_services queries. Leave empty to use caller credentials."
  type        = string
  default     = ""
}

# ─── Cuentas pagadoras ────────────────────────────────────────────────────────
# Mapa de payer_billing_account_id → nombre visible en los dashboards.
# Sustituye los bloques CASE WHEN que antes estaban hardcodeados en las vistas.
# Terraform carga estos datos en la tabla payer_billing_accounts al hacer apply.
# Añade una entrada por cada cuenta pagadora del país (puede ser 1 o varias).
variable "payer_billing_accounts" {
  description = "Map of payer_billing_account_id → account_name. Populates the payer_billing_accounts lookup table used by all billing views."
  type        = map(string)
  default     = {}
}

# ─── Símbolos de divisa ───────────────────────────────────────────────────────
# Mapa de CurrencyIsoCode → símbolo a mostrar en las vistas de Looker.
# Sustituye el CASE WHEN hardcodeado en importes_lecturas y vista_importes_lecturas.
# Si una divisa no aparece en el mapa, las vistas usan '€' como fallback.
variable "currency_symbols" {
  description = "Map of CurrencyIsoCode → display symbol (e.g. {\"USD\" = \"$\", \"GBP\" = \"£\"}). Populates the currency_symbols lookup table used by the importes_lecturas views."
  type        = map(string)
  default     = {}
}

variable "ext_maps_services_sheet_url" {
  description = "URL of the Google Sheet that backs the ext_maps_services external table."
  type        = string
  default     = "https://docs.google.com/spreadsheets/d/1U_GZoqKomDdsPfpdR09OKnbjeG5NzPEIGG1iiWE_m0M/edit?usp=sharing"
}

variable "ext_workspace_sku_sf_sheet_url" {
  description = "URL of the Google Sheet that backs the ext_workspace_sku_sf external table."
  type        = string
  default     = "https://docs.google.com/spreadsheets/d/1uPYZPp3iDAv-hojOJN8b1_MHn9qQJ1NVTRUC_eDgLYU/edit?gid=494423533#gid=494423533"
}

variable "sku_third_party_migration_service_account" {
  description = "Service account email for the sku_third_party migration query. Leave empty if not applicable."
  type        = string
  default     = ""
}
