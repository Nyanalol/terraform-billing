# ─── Views: billing_views dataset ────────────────────────────────────────────
# Each view's SQL query is loaded from its dedicated file under:
#   sql/billing_views/<view_name>.sql
# Edit that file to change the query; Terraform will detect the change on the
# next plan/apply and update the view automatically.

# billing_accounts is managed by Talend. Stub created so dependent views can be deployed.
resource "google_bigquery_table" "billing_accounts" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.billing_views.dataset_id
  table_id            = "billing_accounts"
  deletion_protection = false
  labels              = local.common_labels

  lifecycle {
    ignore_changes = [schema]
  }

  schema = jsonencode([
    { name = "Fecha_Fin_Contrato__c",    type = "DATE",   mode = "NULLABLE" },
    { name = "Fecha_Inicio_Contrato__c", type = "DATE",   mode = "NULLABLE" },
    { name = "billing_account_id__c",    type = "STRING", mode = "NULLABLE" },
    { name = "billing_account_desc__c",  type = "STRING", mode = "NULLABLE" },
    { name = "Desglosar_Facturas__c",    type = "STRING", mode = "NULLABLE" },
    { name = "Billing_Model__c",         type = "STRING", mode = "NULLABLE" }
  ])
}

# importes_lecturas_* tables are managed by Talend. Stubs created so dependent views can be deployed.
resource "google_bigquery_table" "importes_lecturas_temp" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.billing_views.dataset_id
  table_id            = "importes_lecturas_temp"
  deletion_protection = false
  labels              = local.common_labels

  lifecycle {
    ignore_changes = [schema]
  }

  schema = jsonencode([
    { name = "billing_account_id",       type = "STRING", mode = "NULLABLE" },
    { name = "Dominio__c",               type = "STRING", mode = "NULLABLE" },
    { name = "OpportunityId__c",         type = "STRING", mode = "NULLABLE" },
    { name = "SKU__c",                   type = "FLOAT",  mode = "NULLABLE" },
    { name = "CurrencyIsoCode__c",       type = "STRING", mode = "NULLABLE" },
    { name = "TotalSupport",             type = "FLOAT",  mode = "NULLABLE" },
    { name = "Margen__c",               type = "FLOAT",  mode = "NULLABLE" },
    { name = "Total_gcp",               type = "FLOAT",  mode = "NULLABLE" },
    { name = "Magen_gcp",               type = "FLOAT",  mode = "NULLABLE" },
    { name = "Total_gmp",               type = "FLOAT",  mode = "NULLABLE" },
    { name = "Margen_gmp",              type = "FLOAT",  mode = "NULLABLE" },
    { name = "Margen_total",            type = "FLOAT",  mode = "NULLABLE" },
    { name = "Cargo_Google__c",         type = "FLOAT",  mode = "NULLABLE" },
    { name = "Importe__c",              type = "FLOAT",  mode = "NULLABLE" },
    { name = "invoice_month",           type = "STRING", mode = "NULLABLE" },
    { name = "invoce_date",             type = "STRING", mode = "NULLABLE" },
    { name = "cambio_aplicado",         type = "FLOAT",  mode = "NULLABLE" },
    { name = "project_id",              type = "STRING", mode = "NULLABLE" },
    { name = "descripcion",             type = "STRING", mode = "NULLABLE" },
    { name = "Margen_gcp_euros",        type = "FLOAT",  mode = "NULLABLE" },
    { name = "Margen_gmp_euros",        type = "FLOAT",  mode = "NULLABLE" },
    { name = "Margen_soporte_euros",    type = "FLOAT",  mode = "NULLABLE" },
    { name = "Margen_soporte_maps_euros", type = "FLOAT", mode = "NULLABLE" },
    { name = "Margen_SWO",              type = "FLOAT",  mode = "NULLABLE" },
    { name = "Total_thirdparty",        type = "FLOAT",  mode = "NULLABLE" }
  ])
}

resource "google_bigquery_table" "importes_lecturas_by_project" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.billing_views.dataset_id
  table_id            = "importes_lecturas_by_project"
  deletion_protection = false
  labels              = local.common_labels

  lifecycle {
    ignore_changes = [schema]
  }

  schema = jsonencode([
    { name = "billing_account_id",       type = "STRING", mode = "NULLABLE" },
    { name = "Dominio__c",               type = "STRING", mode = "NULLABLE" },
    { name = "OpportunityId__c",         type = "STRING", mode = "NULLABLE" },
    { name = "SKU__c",                   type = "FLOAT",  mode = "NULLABLE" },
    { name = "CurrencyIsoCode__c",       type = "STRING", mode = "NULLABLE" },
    { name = "TotalSupport",             type = "FLOAT",  mode = "NULLABLE" },
    { name = "Margen__c",               type = "FLOAT",  mode = "NULLABLE" },
    { name = "Total_gcp",               type = "FLOAT",  mode = "NULLABLE" },
    { name = "Magen_gcp",               type = "FLOAT",  mode = "NULLABLE" },
    { name = "Total_gmp",               type = "FLOAT",  mode = "NULLABLE" },
    { name = "Margen_gmp",              type = "FLOAT",  mode = "NULLABLE" },
    { name = "Margen_total",            type = "FLOAT",  mode = "NULLABLE" },
    { name = "Cargo_Google__c",         type = "FLOAT",  mode = "NULLABLE" },
    { name = "Importe__c",              type = "FLOAT",  mode = "NULLABLE" },
    { name = "invoice_month",           type = "STRING", mode = "NULLABLE" },
    { name = "invoice_date",            type = "STRING", mode = "NULLABLE" },
    { name = "cambio_aplicado",         type = "FLOAT",  mode = "NULLABLE" },
    { name = "project_id",              type = "STRING", mode = "NULLABLE" },
    { name = "descripcion",             type = "STRING", mode = "NULLABLE" },
    { name = "Margen_gcp_euros",        type = "FLOAT",  mode = "NULLABLE" },
    { name = "Margen_gmp_euros",        type = "FLOAT",  mode = "NULLABLE" },
    { name = "Margen_soporte_euros",    type = "FLOAT",  mode = "NULLABLE" },
    { name = "Margen_soporte_maps_euros", type = "FLOAT", mode = "NULLABLE" },
    { name = "Margen_SWO",              type = "FLOAT",  mode = "NULLABLE" },
    { name = "Total_thirdparty",        type = "STRING", mode = "REQUIRED" }
  ])
}

resource "google_bigquery_table" "billing_accounts_full" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.billing_views.dataset_id
  table_id            = "billing_accounts_full"
  deletion_protection = false
  labels              = local.common_labels

  lifecycle {
    ignore_changes = [schema]
  }

  schema = jsonencode([
    { name = "Fecha_Fin_Contrato__c",    type = "DATE",   mode = "NULLABLE" },
    { name = "Fecha_Inicio_Contrato__c", type = "DATE",   mode = "NULLABLE" },
    { name = "billing_account_id__c",    type = "STRING", mode = "NULLABLE" },
    { name = "billing_account_desc__c",  type = "STRING", mode = "NULLABLE" },
    { name = "Desglosar_Facturas__c",    type = "STRING", mode = "NULLABLE" },
    { name = "Billing_Model__c",         type = "STRING", mode = "NULLABLE" },
    { name = "StageName",                type = "STRING", mode = "REQUIRED" },
    { name = "Empresa_IP__c",            type = "STRING", mode = "NULLABLE" }
  ])
}

resource "google_bigquery_table" "importes_lecturas_workspace" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.billing_views.dataset_id
  table_id            = "importes_lecturas_workspace"
  deletion_protection = false
  labels              = local.common_labels

  lifecycle {
    ignore_changes = [schema]
  }

  schema = jsonencode([
    { name = "Cargo_Google__c",              type = "FLOAT",  mode = "NULLABLE" },
    { name = "Descripcion__c",               type = "STRING", mode = "NULLABLE" },
    { name = "Definicion_del_producto__c",   type = "STRING", mode = "NULLABLE" },
    { name = "Fecha_Inicio__c",              type = "DATE",   mode = "NULLABLE" },
    { name = "Fecha_Fin__c",                 type = "DATE",   mode = "NULLABLE" },
    { name = "Dominio__c",                   type = "STRING", mode = "NULLABLE" },
    { name = "Anyo__c",                      type = "STRING", mode = "NULLABLE" },
    { name = "Mes__c",                       type = "STRING", mode = "NULLABLE" },
    { name = "CurrencyIsoCode",              type = "STRING", mode = "NULLABLE" },
    { name = "SKU2__c",                      type = "STRING", mode = "NULLABLE" },
    { name = "Oportunidad__c",               type = "STRING", mode = "NULLABLE" },
    { name = "Order_Number__c",              type = "STRING", mode = "NULLABLE" },
    { name = "usage_type",                   type = "STRING", mode = "NULLABLE" },
    { name = "type",                         type = "STRING", mode = "NULLABLE" }
  ])
}

resource "google_bigquery_table" "importes_lecturas_anuales" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.billing_views.dataset_id
  table_id            = "importes_lecturas_anuales"
  deletion_protection = false
  labels              = local.common_labels

  lifecycle {
    ignore_changes = [schema]
  }

  schema = jsonencode([
    { name = "billing_account_id",       type = "STRING", mode = "NULLABLE" },
    { name = "Dominio__c",               type = "STRING", mode = "NULLABLE" },
    { name = "OpportunityId__c",         type = "STRING", mode = "NULLABLE" },
    { name = "SKU__c",                   type = "FLOAT",  mode = "NULLABLE" },
    { name = "CurrencyIsoCode__c",       type = "STRING", mode = "NULLABLE" },
    { name = "TotalSupport",             type = "FLOAT",  mode = "NULLABLE" },
    { name = "Margen__c",               type = "FLOAT",  mode = "NULLABLE" },
    { name = "Total_gcp",               type = "FLOAT",  mode = "NULLABLE" },
    { name = "Magen_gcp",               type = "FLOAT",  mode = "NULLABLE" },
    { name = "Total_gmp",               type = "FLOAT",  mode = "NULLABLE" },
    { name = "Margen_gmp",              type = "FLOAT",  mode = "NULLABLE" },
    { name = "Margen_total",            type = "FLOAT",  mode = "NULLABLE" },
    { name = "Cargo_Google__c",         type = "FLOAT",  mode = "NULLABLE" },
    { name = "Importe__c",              type = "FLOAT",  mode = "NULLABLE" },
    { name = "invoice_month",           type = "STRING", mode = "NULLABLE" },
    { name = "invoce_date",             type = "STRING", mode = "NULLABLE" },
    { name = "cambio_aplicado",         type = "FLOAT",  mode = "NULLABLE" },
    { name = "project_id",              type = "STRING", mode = "NULLABLE" },
    { name = "descripcion",             type = "STRING", mode = "NULLABLE" },
    { name = "Margen_gcp_euros",        type = "FLOAT",  mode = "NULLABLE" },
    { name = "Margen_gmp_euros",        type = "FLOAT",  mode = "NULLABLE" },
    { name = "Margen_soporte_euros",    type = "FLOAT",  mode = "NULLABLE" },
    { name = "Margen_soporte_maps_euros", type = "FLOAT", mode = "NULLABLE" },
    { name = "Total_thirdparty",        type = "FLOAT",  mode = "NULLABLE" }
  ])
}

resource "google_bigquery_table" "billing_gcp" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.billing_views.dataset_id
  table_id            = "billing_gcp"
  deletion_protection = false
  labels              = local.common_labels

  depends_on = [google_bigquery_table.sku_third_party]

  view {
    query = templatefile("${path.module}/sql/billing_views/billing_gcp.sql", {
      project_id            = var.project_id
      billing_cp_dataset    = google_bigquery_dataset.billing_cloud_platform.dataset_id
      billing_views_dataset = google_bigquery_dataset.billing_views.dataset_id
    })
    use_legacy_sql = false
  }
}

resource "google_bigquery_table" "billing_gcp_by_project" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.billing_views.dataset_id
  table_id            = "billing_gcp_by_project"
  deletion_protection = false
  labels              = local.common_labels

  depends_on = [google_bigquery_table.sku_third_party]

  view {
    query = templatefile("${path.module}/sql/billing_views/billing_gcp_by_project.sql", {
      project_id            = var.project_id
      billing_cp_dataset    = google_bigquery_dataset.billing_cloud_platform.dataset_id
      billing_views_dataset = google_bigquery_dataset.billing_views.dataset_id
    })
    use_legacy_sql = false
  }
}

resource "google_bigquery_table" "billing_gmp" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.billing_views.dataset_id
  table_id            = "billing_gmp"
  deletion_protection = false
  labels              = local.common_labels

  view {
    query = templatefile("${path.module}/sql/billing_views/billing_gmp.sql", {
      project_id            = var.project_id
      billing_cp_dataset    = google_bigquery_dataset.billing_cloud_platform.dataset_id
      billing_views_dataset = google_bigquery_dataset.billing_views.dataset_id
    })
    use_legacy_sql = false
  }
}

resource "google_bigquery_table" "billing_gmp_by_project" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.billing_views.dataset_id
  table_id            = "billing_gmp_by_project"
  deletion_protection = false
  labels              = local.common_labels

  depends_on = [google_bigquery_table.sku_third_party]

  view {
    query = templatefile("${path.module}/sql/billing_views/billing_gmp_by_project.sql", {
      project_id            = var.project_id
      billing_cp_dataset    = google_bigquery_dataset.billing_cloud_platform.dataset_id
      billing_views_dataset = google_bigquery_dataset.billing_views.dataset_id
    })
    use_legacy_sql = false
  }
}

# importes_lecturas_* views are managed by Talend, not Terraform.

resource "google_bigquery_table" "reseller_view" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.billing_views.dataset_id
  table_id            = "reseller_view"
  deletion_protection = false
  labels              = local.common_labels

  view {
    query = templatefile("${path.module}/sql/billing_views/reseller_view.sql", {
      project_id            = var.project_id
      billing_cp_dataset    = google_bigquery_dataset.billing_cloud_platform.dataset_id
      billing_views_dataset = google_bigquery_dataset.billing_views.dataset_id
    })
    use_legacy_sql = false
  }
}

resource "google_bigquery_table" "sum_costs_credits_per_month" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.billing_views.dataset_id
  table_id            = "sum_costs_credits_per_month"
  deletion_protection = false
  labels              = local.common_labels

  depends_on = [google_bigquery_table.billing_gcp, google_bigquery_table.billing_gmp]

  view {
    query = templatefile("${path.module}/sql/billing_views/sum_costs_credits_per_month.sql", {
      project_id            = var.project_id
      billing_cp_dataset    = google_bigquery_dataset.billing_cloud_platform.dataset_id
      billing_views_dataset = google_bigquery_dataset.billing_views.dataset_id
    })
    use_legacy_sql = false
  }
}

resource "google_bigquery_table" "sum_costs_credits_per_month_by_project" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.billing_views.dataset_id
  table_id            = "sum_costs_credits_per_month_by_project"
  deletion_protection = false
  labels              = local.common_labels

  depends_on = [google_bigquery_table.billing_gcp_by_project, google_bigquery_table.billing_gmp_by_project]

  view {
    query = templatefile("${path.module}/sql/billing_views/sum_costs_credits_per_month_by_project.sql", {
      project_id            = var.project_id
      billing_cp_dataset    = google_bigquery_dataset.billing_cloud_platform.dataset_id
      billing_views_dataset = google_bigquery_dataset.billing_views.dataset_id
    })
    use_legacy_sql = false
  }
}
