# ─── Tables: third_party dataset ─────────────────────────────────────────────
# sku_third_party is managed by Talend / migration scheduled query.
# lifecycle.ignore_changes = [schema] prevents Terraform from overwriting
# the schema after the migration populates the table.

resource "google_bigquery_table" "sku_third_party_dataset" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.third_party.dataset_id
  table_id            = "sku_third_party"
  deletion_protection = false
  labels              = local.common_labels

  lifecycle {
    ignore_changes = [schema]
  }

  schema = jsonencode([
    { name = "service_name", type = "STRING", mode = "NULLABLE" },
    { name = "sku_name",     type = "STRING", mode = "NULLABLE" },
    { name = "sku_id",       type = "STRING", mode = "NULLABLE" },
    { name = "date_added",   type = "STRING", mode = "NULLABLE" }
  ])
}
