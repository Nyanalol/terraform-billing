# ─── APIs del proyecto ───────────────────────────────────────────────────────
# Habilita las APIs necesarias para el despliegue (paso 1 del checklist, que hoy
# se hace a mano). disable_on_destroy = false: al destruir recursos NO se apagan
# las APIs (otros recursos del proyecto podrían depender de ellas).

locals {
  required_apis = [
    "bigquery.googleapis.com",
    "bigquerydatatransfer.googleapis.com", # scheduled queries
    "storage.googleapis.com",              # bucket de staging / HMAC
  ]
}

resource "google_project_service" "required" {
  for_each = toset(local.required_apis)

  project = var.project_id
  service = each.value

  disable_on_destroy         = false
  disable_dependent_services = false
}
