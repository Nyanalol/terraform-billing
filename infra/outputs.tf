output "dataset_ids" {
  description = "BigQuery dataset IDs created by this deployment."
  value       = module.billing_datasets.dataset_ids
}

output "service_account_email" {
  description = "Email de la SA bigquery-talend (pasar a Ops para descargar el JSON)."
  value       = module.billing_datasets.service_account_email
}

output "staging_bucket_name" {
  description = "Nombre del bucket de staging creado (null si no se creó)."
  value       = module.billing_datasets.staging_bucket_name
}

output "hmac_access_id" {
  description = "Access ID (access key) de la clave HMAC de la SA."
  value       = module.billing_datasets.hmac_access_id
}

output "hmac_secret" {
  description = "Secret key de la clave HMAC. Verlo con: terraform output -raw hmac_secret"
  value       = module.billing_datasets.hmac_secret
  sensitive   = true
}
