variable "global_project_id" {
  description = "Proyecto central donde viven las tablas unificadas."
  type        = string
  default     = "swo-billingglobal-prod"
}

variable "global_dataset" {
  description = "Dataset destino de las tablas unificadas en el proyecto global."
  type        = string
  default     = "looker_views_global"
}

variable "location" {
  description = "Location de BigQuery. Debe coincidir con la de los datasets de cada país."
  type        = string
  default     = "EU"
}

variable "countries" {
  description = "Mapa país → project_id. El nombre se usa como valor de la columna 'country'. Incluir SOLO países ya desplegados (con su dataset looker_views)."
  type        = map(string)

  validation {
    condition     = length(var.countries) > 0
    error_message = "Hay que indicar al menos un país en 'countries'."
  }
}

variable "views" {
  description = "Vistas de looker_views a unir. Cada una genera una tabla global y una scheduled query."
  type        = list(string)
  default = [
    "consumos_google_reseller_factura",
    "consumos_por_account",
    "consumos_por_proyecto_new",
    "consumos_support_flex",
    "gcp_billing_adjustment",
    "importes_lecturas",
    "vista_importes_lecturas",
  ]
}

variable "global_service_account_id" {
  description = "Account ID de la SA que ejecuta las scheduled queries del union."
  type        = string
  default     = "bq-global-union"
}

variable "create_service_account" {
  description = "Si Terraform crea la SA. false si ya existe."
  type        = bool
  default     = true
}

variable "manage_country_iam" {
  description = "Si Terraform gestiona el dataViewer de la SA global sobre el looker_views de cada país. Requiere setIamPolicy en cada proyecto de país."
  type        = bool
  default     = true
}

variable "manage_global_project_iam" {
  description = "Si Terraform gestiona el binding de proyecto (bigquery.jobUser) en el proyecto global. Requiere setIamPolicy de proyecto sobre global_project_id; poner false para darlo a mano."
  type        = bool
  default     = true
}

variable "months_back" {
  description = "Meses a retener en las tablas unificadas (ventana móvil)."
  type        = number
  default     = 3
}

variable "schedule" {
  description = "Programación de las scheduled queries (sintaxis de BigQuery Data Transfer)."
  type        = string
  default     = "every day 05:00"
}
