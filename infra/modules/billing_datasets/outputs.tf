output "dataset_ids" {
  description = "Dataset IDs created by this module instance."
  value = {
    billing_cloud_platform = google_bigquery_dataset.billing_cloud_platform.dataset_id
    billing_views          = google_bigquery_dataset.billing_views.dataset_id
    looker_views           = google_bigquery_dataset.looker_views.dataset_id
  }
}

output "billing_cloud_platform_dataset_id" {
  description = "Dataset ID of the billing_cloud_platform dataset."
  value       = google_bigquery_dataset.billing_cloud_platform.dataset_id
}

output "billing_views_dataset_id" {
  description = "Dataset ID of the billing_views dataset."
  value       = google_bigquery_dataset.billing_views.dataset_id
}

output "looker_views_dataset_id" {
  description = "Dataset ID of the looker_views dataset."
  value       = google_bigquery_dataset.looker_views.dataset_id
}

# ─── Staging bucket + HMAC ───────────────────────────────────────────────────
output "staging_bucket_name" {
  description = "Nombre del bucket de staging creado (null si no se creó)."
  value       = var.staging_bucket_name != "" ? google_storage_bucket.staging[0].name : null
}

output "hmac_access_id" {
  description = "Access ID (access key) de la clave HMAC de la SA (null si no se creó)."
  value       = var.create_hmac_key ? google_storage_hmac_key.talend[0].access_id : null
}

output "hmac_secret" {
  description = "Secret key de la clave HMAC de la SA. SENSIBLE."
  value       = var.create_hmac_key ? google_storage_hmac_key.talend[0].secret : null
  sensitive   = true
}

output "service_account_email" {
  description = "Email de la SA bigquery-talend (a pasar a Ops para descargar el JSON)."
  value       = local.talend_sa_email
}
