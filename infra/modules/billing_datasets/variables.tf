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
  description = "URL of the Google Sheet that backs the ext_maps_services external table (lookup global SWO, igual para todos los países)."
  type        = string
  # URL real tomada del estado desplegado de HK (antes era placeholder XXXX -> external table rota).
  default = "https://docs.google.com/spreadsheets/d/1U_GZoqKomDdsPfpdR09OKnbjeG5NzPEIGG1iiWE_m0M/edit?usp=sharing"
}

variable "ext_workspace_sku_sf_sheet_url" {
  description = "URL of the Google Sheet that backs the ext_workspace_sku_sf external table (lookup global SWO, igual para todos los países)."
  type        = string
  # URL real tomada del estado desplegado de HK (antes era placeholder XXXX -> external table rota).
  default = "https://docs.google.com/spreadsheets/d/1uPYZPp3iDAv-hojOJN8b1_MHn9qQJ1NVTRUC_eDgLYU/edit?gid=494423533#gid=494423533"
}
variable "sku_third_party_migration_service_account" {
  description = "Service account email used to execute the sku_third_party migration scheduled query. Leave empty to use the caller credentials."
  type        = string
  default     = ""
}

# ─── Service Account (bigquery-talend) ───────────────────────────────────────
variable "service_account_id" {
  description = "Account ID (parte antes de la @) de la SA de Talend. Email resultante: <id>@<project_id>.iam.gserviceaccount.com."
  type        = string
  default     = "bigquery-talend"
}

variable "create_service_account" {
  description = "Si Terraform debe CREAR la SA. Poner false en países donde la SA ya existe (creada a mano antes de Terraform); los bindings IAM se gestionan igual."
  type        = bool
  default     = true
}

variable "spain_project_id" {
  description = "Project ID del proyecto de España, donde la SA del país necesita permisos cruzados (dataViewer + jobUser) para Maps y la migración de sku_third_party."
  type        = string
  default     = "ip-billing-prod"
}

variable "manage_spain_iam" {
  description = "Si Terraform gestiona los bindings IAM cruzados en el proyecto de España. Requiere setIamPolicy sobre spain_project_id. Poner false para darlos a mano."
  type        = bool
  default     = true
}

# ─── Staging bucket + HMAC (pasos 15-16) ─────────────────────────────────────
variable "staging_bucket_name" {
  description = "Nombre del bucket de staging de Talend (gcp-billing-process-staging-<código>). Vacío = no crear bucket."
  type        = string
  default     = ""
}

variable "create_hmac_key" {
  description = "Si Terraform crea la clave HMAC (access/secret key) para la SA. El secret queda en el estado como output sensible."
  type        = bool
  default     = true
}
