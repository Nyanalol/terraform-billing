# ─── Service Account de las scheduled queries del union ──────────────────────
# Ejecuta las scheduled queries por impersonación (service_account_name), SIN JSON key,
# así que no le afecta la org policy iam.disableServiceAccountKeyCreation.
# Quien aplica necesita roles/iam.serviceAccountTokenCreator sobre esta SA.

resource "google_service_account" "global" {
  count = var.create_service_account ? 1 : 0

  project      = var.global_project_id
  account_id   = var.global_service_account_id
  display_name = "BigQuery Global Union (scheduled queries)"
  description  = "SA que materializa las tablas UNION ALL multi-país. Gestionada por Terraform."
}

# Lanzar jobs en el proyecto global (la query corre aquí).
# Es IAM de proyecto: requiere setIamPolicy sobre global_project_id. Si la cuenta que aplica
# no lo tiene, poner manage_global_project_iam = false y que un admin del proyecto lo dé a mano.
resource "google_project_iam_member" "global_job_user" {
  count = var.manage_global_project_iam ? 1 : 0

  project    = var.global_project_id
  role       = "roles/bigquery.jobUser"
  member     = local.global_sa_member
  depends_on = [google_service_account.global]
}

# Escribir las tablas del union en el dataset global (scope dataset, mínimo privilegio).
resource "google_bigquery_dataset_iam_member" "global_data_editor" {
  project    = var.global_project_id
  dataset_id = google_bigquery_dataset.global.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = local.global_sa_member
  depends_on = [google_service_account.global]
}

# Leer los datos de cada país (cross-project). Se concede a NIVEL DE PROYECTO porque las
# looker_views leen por dentro de otros datasets (billing_views, BILLING_*_CLOUD_PLATFORM):
# consultar una vista exige acceso también a sus tablas subyacentes, no solo a looker_views.
# Es solo lectura. Requiere setIamPolicy de proyecto en cada país; opt-out con manage_country_iam = false.
resource "google_project_iam_member" "country_viewer" {
  for_each = var.manage_country_iam ? var.countries : {}

  project    = each.value
  role       = "roles/bigquery.dataViewer"
  member     = local.global_sa_member
  depends_on = [google_service_account.global]
}
