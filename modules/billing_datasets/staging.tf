# ─── Bucket de staging + clave HMAC (pasos 15-16 del checklist) ───────────────
# Talend usa un bucket de staging y accede vía claves HMAC (interoperability,
# compatible S3). El checklist define un bucket por país en EU multiregion:
#   gcp-billing-process-staging-<código_país>
#
# El bucket se crea solo si staging_bucket_name != "" (déjalo vacío para no crearlo,
# p.ej. en despliegues de prueba). La SA bigquery-talend ya tiene acceso al bucket
# de su propio proyecto vía su rol owner.

resource "google_storage_bucket" "staging" {
  count = var.staging_bucket_name != "" ? 1 : 0

  project                     = var.project_id
  name                        = var.staging_bucket_name
  location                    = "EU"
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false
  labels                      = local.common_labels

  depends_on = [google_project_service.required]
}

# ─── Clave HMAC para la SA (paso 16: access key / secret key) ─────────────────
# El secret se expone como output sensible y queda en el estado de Terraform
# (protegido en el bucket de state). Desactivable con create_hmac_key = false.

resource "google_storage_hmac_key" "talend" {
  count = var.create_hmac_key ? 1 : 0

  project               = var.project_id
  service_account_email = local.talend_sa_email

  depends_on = [
    google_service_account.bigquery_talend,
    google_project_service.required,
  ]
}
