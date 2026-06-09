output "service_account_email" {
  description = "Email de la SA que ejecuta las scheduled queries del union."
  value       = local.global_sa_email
}

output "dataset_id" {
  description = "Dataset destino de las tablas unificadas."
  value       = google_bigquery_dataset.global.dataset_id
}

output "global_tables" {
  description = "Tablas unificadas que se crean (una por vista)."
  value       = [for v in var.views : "${var.global_project_id}.${var.global_dataset}.${v}"]
}

output "union_sql" {
  description = "SQL generado por vista (para depuración)."
  value       = local.union_sql
}
