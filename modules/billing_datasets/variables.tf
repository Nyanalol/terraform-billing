variable "project_id" {
  description = "The GCP project ID where BigQuery datasets will be created."
  type        = string
}

variable "country" {
  description = "Country identifier (used in descriptions and labels)."
  type        = string
}

variable "billing_cloud_platform_dataset" {
  description = "Dataset ID for the billing cloud platform dataset."
  type        = string
  default     = "BILLING_CLOUD_PLATFORM"
}

variable "location" {
  description = "BigQuery dataset location (e.g. EU, US, europe-west1)."
  type        = string
  default     = "EU"
}

variable "scheduled_query_service_account" {
  description = "Service account email used to execute the scheduled query. Leave empty to use the caller credentials."
  type        = string
  default     = ""
}

variable "payer_billing_accounts" {
  description = "Map of payer_billing_account_id → account_name. Defines the account labels used across all billing views. Terraform will load this data into the payer_billing_accounts lookup table on apply."
  type        = map(string)
  default     = {}
}

variable "currency_symbols" {
  description = "Map of CurrencyIsoCode → display symbol (e.g. {\"USD\" = \"$\", \"GBP\" = \"£\"}). Populates the currency_symbols lookup table used by the importes_lecturas views."
  type        = map(string)
  default     = {}
}
variable "ext_maps_services_sheet_url" {
  description = "URL of the Google Sheet that backs the ext_maps_services external table."
  type        = string
  default     = "https://docs.google.com/spreadsheets/d/XXXX"
}

variable "ext_workspace_sku_sf_sheet_url" {
  description = "URL of the Google Sheet that backs the ext_workspace_sku_sf external table."
  type        = string
  default     = "https://docs.google.com/spreadsheets/d/XXXX"
}
variable "sku_third_party_migration_service_account" {
  description = "Service account email used to execute the sku_third_party migration scheduled query. Leave empty to use the caller credentials."
  type        = string
  default     = ""
}
