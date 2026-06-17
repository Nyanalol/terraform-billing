variable "project_id" {
  description = "GCP project ID where the BigQuery datasets will be created."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id no parece un ID de proyecto GCP válido (6-30 chars, minúsculas/números/guiones, empieza por letra)."
  }
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

  validation {
    # Los IDs de cuenta pagadora tienen el formato XXXXXX-YYYYYY-ZZZZZZ (hex).
    condition = alltrue([
      for id in keys(var.payer_billing_accounts) :
      can(regex("^[0-9A-Fa-f]{6}-[0-9A-Fa-f]{6}-[0-9A-Fa-f]{6}$", id))
    ])
    error_message = "Cada payer_billing_account_id debe tener el formato XXXXXX-YYYYYY-ZZZZZZ (3 grupos hex de 6, sin el prefijo 'billingAccounts/')."
  }
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

# ─── Service Account (bigquery-talend) ───────────────────────────────────────
# Terraform crea la SA y le asigna los permisos (pasos 5, 8, 10, 12 del checklist):
#   - En su propio proyecto: owner + bigquery.admin + bigquery.connectionUser
#   - En el proyecto de España (cruzado): dataViewer + jobUser
variable "service_account_id" {
  description = "Account ID de la SA de Talend (antes de la @). Email: <id>@<project_id>.iam.gserviceaccount.com."
  type        = string
  default     = "bigquery-talend"
}

variable "create_service_account" {
  description = "Si Terraform debe CREAR la SA. Poner false si la SA ya existe en el proyecto (p.ej. Hong Kong, creada a mano)."
  type        = bool
  default     = true
}

variable "spain_project_id" {
  description = "Project ID del proyecto de España para los permisos cruzados de la SA."
  type        = string
  default     = "ip-billing-prod"
}

variable "manage_spain_iam" {
  description = "Si Terraform gestiona los bindings IAM cruzados en el proyecto de España. Requiere setIamPolicy sobre ese proyecto."
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

# ─── Metadato para generar el config de Talend (NO lo usa Terraform) ──────────
# Cláusula COMPLETA de Empresa_IP__c del país (para la línea sf_opp_query_condition del
# config_billing). Puede ser una sola o varias con OR. Lo lee generate-config-billing.ps1.
# Ejemplos:
#   sf_empresa_ip = "Empresa_IP__c='001IV00001PehnLYAR'"
#   sf_empresa_ip = "(Empresa_IP__c='0015700001lTrioAAC' OR Empresa_IP__c='001IV00001TJUpHYAX')"
variable "sf_empresa_ip" {
  description = "Cláusula Empresa_IP__c del país (una o varias con OR) para el config de Talend. Terraform no lo usa."
  type        = string
  default     = ""
}
