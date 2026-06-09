# ─── Scheduled queries: una por vista ────────────────────────────────────────
# Cada una ejecuta el DDL CREATE OR REPLACE TABLE ... AS <union> (ver locals.tf).
# Al ser DDL, no se usan destination_table_name_template ni write_disposition: la propia
# query crea/reemplaza la tabla destino y fija el clustering.

resource "google_bigquery_data_transfer_config" "global_union" {
  for_each = toset(var.views)

  project        = var.global_project_id
  display_name   = "global_union_${each.value}"
  location       = var.location
  data_source_id = "scheduled_query"
  schedule       = var.schedule

  service_account_name = local.global_sa_email

  params = {
    query = local.union_sql[each.value]
  }

  depends_on = [
    google_bigquery_dataset.global,
    google_project_iam_member.global_job_user,
    google_bigquery_dataset_iam_member.global_data_editor,
    google_project_iam_member.country_viewer,
  ]
}
