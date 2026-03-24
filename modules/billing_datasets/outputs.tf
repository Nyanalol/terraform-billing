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
