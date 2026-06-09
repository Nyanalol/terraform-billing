# ─── Dataset destino de las tablas unificadas ────────────────────────────────

resource "google_bigquery_dataset" "global" {
  project                    = var.global_project_id
  dataset_id                 = var.global_dataset
  friendly_name              = "Looker Views Global"
  description                = "Tablas unificadas (UNION ALL) de los looker_views de todos los países, para el Data Studio único."
  location                   = var.location
  delete_contents_on_destroy = false

  labels = {
    managed_by = "terraform"
    scope      = "global"
  }
}
