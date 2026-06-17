output "service_account_email" {
  description = "Email de la SA que ejecuta las scheduled queries del union."
  value       = local.global_sa_email
}

output "dataset_id" {
  description = "Dataset destino de las tablas unificadas."
  value       = google_bigquery_dataset.global.dataset_id
}

output "global_tables" {
  description = "Tablas unificadas que se crean (looker_views + billing_views)."
  value       = [for t in keys(local.all_union_sql) : "${var.global_project_id}.${var.global_dataset}.${t}"]
}

output "union_sql" {
  description = "SQL generado por tabla (looker_views + billing_views) para depuración."
  value       = local.all_union_sql
}
