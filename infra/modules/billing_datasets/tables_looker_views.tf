# ─── Views: looker_views dataset ─────────────────────────────────────────────
# Each view's SQL query is loaded from its dedicated file under:
#   sql/looker_views/<view_name>.sql
# Edit that file to change the query; Terraform will detect the change on the
# next plan/apply and update the view automatically.
# NOTE: "consumos_por_account" was normalised from "consumos_por account"
#       (space replaced by underscore).

resource "google_bigquery_table" "consumos_google_reseller_factura" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.looker_views.dataset_id
  table_id            = "consumos_google_reseller_factura"
  deletion_protection = false
  labels              = local.common_labels

  view {
    query = templatefile("${path.module}/sql/looker_views/consumos_google_reseller_factura.sql", {
      project_id            = var.project_id
      billing_cp_dataset    = google_bigquery_dataset.billing_cloud_platform.dataset_id
      billing_views_dataset = google_bigquery_dataset.billing_views.dataset_id
    })
    use_legacy_sql = false
  }
}

# consumos_por_account and consumos_por_proyecto_new depend on billing_views.billing_accounts (Talend) — managed by Talend, not Terraform.

resource "google_bigquery_table" "consumos_por_account" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.looker_views.dataset_id
  table_id            = "consumos_por_account"
  deletion_protection = false
  labels              = local.common_labels

  depends_on = [google_bigquery_table.billing_accounts, google_bigquery_table.sum_costs_credits_per_month]

  view {
    query = templatefile("${path.module}/sql/looker_views/consumos_por_account.sql", {
      project_id            = var.project_id
      billing_cp_dataset    = google_bigquery_dataset.billing_cloud_platform.dataset_id
      billing_views_dataset = google_bigquery_dataset.billing_views.dataset_id
    })
    use_legacy_sql = false
  }
}

resource "google_bigquery_table" "consumos_por_proyecto_new" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.looker_views.dataset_id
  table_id            = "consumos_por_proyecto_new"
  deletion_protection = false
  labels              = local.common_labels

  depends_on = [google_bigquery_table.billing_accounts, google_bigquery_table.sum_costs_credits_per_month_by_project]

  view {
    query = templatefile("${path.module}/sql/looker_views/consumos_por_proyecto_new.sql", {
      project_id            = var.project_id
      billing_cp_dataset    = google_bigquery_dataset.billing_cloud_platform.dataset_id
      billing_views_dataset = google_bigquery_dataset.billing_views.dataset_id
    })
    use_legacy_sql = false
  }
}

# consumos_support_flex depends on billing_accounts (Talend) — managed by Talend, not Terraform.

resource "google_bigquery_table" "consumos_support_flex" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.looker_views.dataset_id
  table_id            = "consumos_support_flex"
  deletion_protection = false
  labels              = local.common_labels

  depends_on = [google_bigquery_table.billing_accounts]

  view {
    query = templatefile("${path.module}/sql/looker_views/consumos_support_flex.sql", {
      project_id            = var.project_id
      billing_cp_dataset    = google_bigquery_dataset.billing_cloud_platform.dataset_id
      billing_views_dataset = google_bigquery_dataset.billing_views.dataset_id
    })
    use_legacy_sql = false
  }
}

resource "google_bigquery_table" "gcp_billing_adjustment" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.looker_views.dataset_id
  table_id            = "gcp_billing_adjustment"
  deletion_protection = false
  labels              = local.common_labels

  view {
    query = templatefile("${path.module}/sql/looker_views/gcp_billing_adjustment.sql", {
      project_id            = var.project_id
      billing_cp_dataset    = google_bigquery_dataset.billing_cloud_platform.dataset_id
      billing_views_dataset = google_bigquery_dataset.billing_views.dataset_id
    })
    use_legacy_sql = false
  }
}

# importes_lecturas and vista_importes_lecturas depend on importes_lecturas_* (Talend) — managed by Talend, not Terraform.

resource "google_bigquery_table" "importes_lecturas" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.looker_views.dataset_id
  table_id            = "importes_lecturas"
  deletion_protection = false
  labels              = local.common_labels

  depends_on = [
    google_bigquery_table.currency_symbols,
    google_bigquery_table.importes_lecturas_temp,
    google_bigquery_table.importes_lecturas_by_project,
    google_bigquery_table.importes_lecturas_anuales,
  ]

  view {
    query = templatefile("${path.module}/sql/looker_views/importes_lecturas.sql", {
      project_id            = var.project_id
      billing_cp_dataset    = google_bigquery_dataset.billing_cloud_platform.dataset_id
      billing_views_dataset = google_bigquery_dataset.billing_views.dataset_id
    })
    use_legacy_sql = false
  }
}

resource "google_bigquery_table" "vista_importes_lecturas" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.looker_views.dataset_id
  table_id            = "vista_importes_lecturas"
  deletion_protection = false
  labels              = local.common_labels

  depends_on = [
    google_bigquery_table.currency_symbols,
    google_bigquery_table.importes_lecturas_temp,
    google_bigquery_table.importes_lecturas_by_project,
    google_bigquery_table.importes_lecturas_anuales,
  ]

  view {
    query = templatefile("${path.module}/sql/looker_views/vista_importes_lecturas.sql", {
      project_id            = var.project_id
      billing_cp_dataset    = google_bigquery_dataset.billing_cloud_platform.dataset_id
      billing_views_dataset = google_bigquery_dataset.billing_views.dataset_id
    })
    use_legacy_sql = false
  }
}
