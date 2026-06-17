# ─── Scheduled Queries ───────────────────────────────────────────────────────
# SQL files for scheduled queries are placed under:
#   sql/scheduled_queries/<name>.sql
# Files that use template variables (project_id, dataset_id, etc.) must be
# loaded with templatefile() instead of file().

# ─── maps_services ─────────────────────────────────────────────────────────────
# Copies ext_maps_services → maps_services on days 1 & 2 of each month 00:00 UTC.
# Required IAM on the service account:
#   roles/bigquery.dataEditor  on BILLING_CLOUD_PLATFORM dataset
#   roles/bigquery.jobUser     on the project

resource "google_bigquery_data_transfer_config" "maps_services" {
  project        = var.project_id
  display_name   = "maps_services"
  location       = var.location
  data_source_id = "scheduled_query"
  schedule       = "1,2 of month 00:00"

  destination_dataset_id = google_bigquery_dataset.billing_cloud_platform.dataset_id

  service_account_name = var.scheduled_query_service_account != "" ? var.scheduled_query_service_account : null

  params = {
    destination_table_name_template = "maps_services"
    write_disposition               = "WRITE_TRUNCATE"
    query = templatefile("${path.module}/sql/scheduled_queries/maps_services.sql", {
      project_id = var.project_id
      dataset_id = google_bigquery_dataset.billing_cloud_platform.dataset_id
    })
  }
}

# ─── sku_third_party_migration_from_spain ────────────────────────────────────
# Migrates sku_third_party from the Spain source project every Monday 07:30 UTC.
# Required IAM on the service account:
#   roles/bigquery.dataEditor  on third_party dataset (destination project)
#   roles/bigquery.dataViewer  on BILLING_CLOUD_PLATFORM dataset (source project)
#   roles/bigquery.jobUser     on both projects
#
# Uses sku_third_party_migration_service_account if set; otherwise falls back
# to scheduled_query_service_account.

locals {
  sku_third_party_migration_sa = (
    var.sku_third_party_migration_service_account != ""
    ? var.sku_third_party_migration_service_account
    : var.scheduled_query_service_account
  )
}

resource "google_bigquery_data_transfer_config" "sku_third_party_migration_from_spain" {
  count = local.sku_third_party_migration_sa != "" ? 1 : 0

  project        = var.project_id
  display_name   = "sku_third_party_migration_from_spain"
  location       = var.location
  data_source_id = "scheduled_query"
  schedule       = "every mon 07:30"

  destination_dataset_id = google_bigquery_dataset.third_party.dataset_id

  service_account_name = local.sku_third_party_migration_sa

  params = {
    destination_table_name_template = "sku_third_party"
    write_disposition               = "WRITE_TRUNCATE"
    query                           = file("${path.module}/sql/scheduled_queries/sku_third_party_migration_from_spain.sql")
  }
}

# ─── workspace_sku_sf ────────────────────────────────────────────────────────
# Copies ext_workspace_sku_sf → workspace_sku_sf every Sunday at 00:00 UTC.
# Required IAM on the service account:
#   roles/bigquery.dataEditor  on BILLING_CLOUD_PLATFORM dataset
#   roles/bigquery.jobUser     on the project
resource "google_bigquery_data_transfer_config" "workspace_sku_sf" {
  project        = var.project_id
  display_name   = "workspace_sku_sf"
  location       = var.location
  data_source_id = "scheduled_query"
  schedule       = "every sun 00:00"

  destination_dataset_id = google_bigquery_dataset.billing_cloud_platform.dataset_id

  service_account_name = var.scheduled_query_service_account != "" ? var.scheduled_query_service_account : null

  params = {
    destination_table_name_template = "workspace_sku_sf"
    write_disposition               = "WRITE_TRUNCATE"
    query = templatefile("${path.module}/sql/scheduled_queries/workspace_sku_sf.sql", {
      project_id = var.project_id
      dataset_id = google_bigquery_dataset.billing_cloud_platform.dataset_id
    })
  }
}
