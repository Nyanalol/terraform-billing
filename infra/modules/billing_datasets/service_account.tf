# ─── Service Account: bigquery-talend ────────────────────────────────────────
# SA que usan Talend y las scheduled queries de billing (paso 5 del checklist).
# Terraform la crea y le asigna los permisos, replicando lo que ya funciona en los
# países desplegados:
#   - En SU PROPIO proyecto: owner + bigquery.admin + bigquery.connectionUser
#   - En el proyecto de España (ip-billing-prod), cruzado: dataViewer + jobUser
#     (pasos 10 y 12: leer sku_third_party / Maps y lanzar jobs en España)
#
# Para países donde la SA YA existe (creada a mano antes de Terraform), poner
# create_service_account = false en el tfvars: Terraform no intentará crearla,
# pero sí (re)asegura los bindings IAM, que son idempotentes.

locals {
  # Email/member deterministas por convención de nombre, así los bindings IAM
  # funcionan tanto si Terraform crea la SA como si ya existía (create=false).
  talend_sa_email  = "${var.service_account_id}@${var.project_id}.iam.gserviceaccount.com"
  talend_sa_member = "serviceAccount:${local.talend_sa_email}"
}

resource "google_service_account" "bigquery_talend" {
  count = var.create_service_account ? 1 : 0

  project      = var.project_id
  account_id   = var.service_account_id
  display_name = "Talend BigQuery (${var.country})"
  description  = "SA de Talend y scheduled queries de billing. Gestionada por Terraform."
}

# ─── Roles en su propio proyecto ─────────────────────────────────────────────
# Solo BigQuery Admin + Storage Admin (lo que ya funcionaba en los países antiguos).

resource "google_project_iam_member" "talend_bq_admin" {
  project    = var.project_id
  role       = "roles/bigquery.admin"
  member     = local.talend_sa_member
  depends_on = [google_service_account.bigquery_talend]
}

resource "google_project_iam_member" "talend_storage_admin" {
  project    = var.project_id
  role       = "roles/storage.admin"
  member     = local.talend_sa_member
  depends_on = [google_service_account.bigquery_talend]
}

# ─── Roles cruzados en el proyecto de España ─────────────────────────────────
# Se pueden desactivar con manage_spain_iam = false si no se quiere que Terraform
# toque la IAM del proyecto de España (en ese caso se dan a mano, pasos 10/12).
# Requiere que quien hace apply tenga setIamPolicy sobre var.spain_project_id.

resource "google_project_iam_member" "talend_spain_data_viewer" {
  count = var.manage_spain_iam ? 1 : 0

  project    = var.spain_project_id
  role       = "roles/bigquery.dataViewer"
  member     = local.talend_sa_member
  depends_on = [google_service_account.bigquery_talend]
}

resource "google_project_iam_member" "talend_spain_job_user" {
  count = var.manage_spain_iam ? 1 : 0

  project    = var.spain_project_id
  role       = "roles/bigquery.jobUser"
  member     = local.talend_sa_member
  depends_on = [google_service_account.bigquery_talend]
}
