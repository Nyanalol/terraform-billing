# ─── Tables: BILLING_CLOUD_PLATFORM dataset ───────────────────────────────────
# Schema for each table is a placeholder (empty array).
# Replace the schema attribute with the actual field definitions when ready.
# The lifecycle block prevents Terraform from overwriting schemas managed outside
# of Terraform (e.g. schemas loaded by a data pipeline).

resource "google_bigquery_table" "ext_workspace_sku_sf" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.billing_cloud_platform.dataset_id
  table_id            = "ext_workspace_sku_sf"
  deletion_protection = false
  labels              = local.common_labels

  schema = jsonencode([
    { name = "sku_id",              type = "STRING", mode = "NULLABLE" },
    { name = "sku_sf_flex",         type = "STRING", mode = "NULLABLE" },
    { name = "sku_sf_month",        type = "STRING", mode = "NULLABLE" },
    { name = "service_id",          type = "STRING", mode = "NULLABLE" },
    { name = "service_description", type = "STRING", mode = "NULLABLE" },
    { name = "sku_description",     type = "STRING", mode = "NULLABLE" },
  ])

  external_data_configuration {
    autodetect    = false
    source_format = "GOOGLE_SHEETS"
    source_uris   = [var.ext_workspace_sku_sf_sheet_url]

    google_sheets_options {
      skip_leading_rows = 1
      range             = "A:F"
    }
  }
}

resource "google_bigquery_table" "ext_maps_services" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.billing_cloud_platform.dataset_id
  table_id            = "ext_maps_services"
  deletion_protection = false
  labels              = local.common_labels

  schema = jsonencode([
    { name = "SKU", type = "STRING", mode = "NULLABLE" },
  ])

  external_data_configuration {
    autodetect    = false
    source_format = "GOOGLE_SHEETS"
    source_uris   = [var.ext_maps_services_sheet_url]

    google_sheets_options {
      skip_leading_rows = 1
    }
  }
}

resource "google_bigquery_table" "maps_services" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.billing_cloud_platform.dataset_id
  table_id            = "maps_services"
  deletion_protection = false
  labels              = local.common_labels

  schema = jsonencode([
    { name = "sku", type = "STRING", mode = "NULLABLE" }
  ])

  lifecycle {
    ignore_changes = [schema]
  }
}

resource "google_bigquery_table" "gcp_billing_maps_sku" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.billing_cloud_platform.dataset_id
  table_id            = "gcp_billing_maps_sku"
  deletion_protection = false
  labels              = local.common_labels

  schema = jsonencode([
    { name = "sku", type = "STRING", mode = "NULLABLE" }
  ])

  lifecycle {
    ignore_changes = [schema]
  }
}

resource "google_bigquery_table" "gcp_billing_accounts_name_id" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.billing_cloud_platform.dataset_id
  table_id            = "gcp_billing_accounts_name_id"
  deletion_protection = false
  labels              = local.common_labels

  schema = jsonencode([
    { name = "displayName", type = "STRING", mode = "NULLABLE" },
    { name = "ID",          type = "STRING", mode = "NULLABLE" }
  ])

  lifecycle {
    ignore_changes = [schema]
  }
}

resource "google_bigquery_table" "reseller_billing_detailed_export_v1" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.billing_cloud_platform.dataset_id
  table_id            = "reseller_billing_detailed_export_v1"
  deletion_protection = false
  labels              = local.common_labels

  # Schema and partitioning are managed by the Google Billing export — ignore both.
  schema = jsonencode([])

  lifecycle {
    ignore_changes = [schema, time_partitioning]
  }
}

resource "google_bigquery_table" "sku_third_party" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.billing_cloud_platform.dataset_id
  table_id            = "sku_third_party"
  deletion_protection = false
  labels              = local.common_labels

  # Minimal schema: only sku_id is needed for the LEFT JOIN in billing_gcp/billing_gmp views.
  # When the migration from Spain is enabled, this table will be overwritten by WRITE_TRUNCATE.
  schema = jsonencode([
    { name = "sku_id", type = "STRING", mode = "NULLABLE" }
  ])
}

resource "google_bigquery_table" "workspace_sku_sf" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.billing_cloud_platform.dataset_id
  table_id            = "workspace_sku_sf"
  deletion_protection = false
  labels              = local.common_labels

  schema = jsonencode([
    { name = "sku_id",              type = "STRING", mode = "NULLABLE" },
    { name = "sku_sf_flex",         type = "STRING", mode = "NULLABLE" },
    { name = "sku_sf_month",        type = "STRING", mode = "NULLABLE" },
    { name = "service_id",          type = "STRING", mode = "NULLABLE" },
    { name = "service_description", type = "STRING", mode = "NULLABLE" },
    { name = "sku_description",     type = "STRING", mode = "NULLABLE" }
  ])

  lifecycle {
    ignore_changes = [schema]
  }
}

# ─── Lookup: currency_symbols ───────────────────────────────────────────────
# Mapeo de CurrencyIsoCode → símbolo de divisa.
# Las vistas importes_lecturas y vista_importes_lecturas hacen LEFT JOIN aquí
# en lugar del CASE WHEN hardcodeado. Fallback en SQL: '€'.

resource "google_bigquery_table" "currency_symbols" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.billing_cloud_platform.dataset_id
  table_id            = "currency_symbols"
  deletion_protection = false
  labels              = local.common_labels
  description         = "Lookup: mapeo de CurrencyIsoCode a símbolo de divisa. Editar esta tabla para añadir/cambiar divisas sin modificar las vistas."

  schema = jsonencode([
    {
      name        = "currency_iso_code"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Código ISO de la divisa (e.g. EUR, USD, GBP)"
    },
    {
      name        = "symbol"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Símbolo a mostrar (e.g. €, $, £)"
    }
  ])
}

# ─── Lookup: payer_billing_accounts ──────────────────────────────────────────
# Mapeo de payer_billing_account_id → nombre de cuenta.
# Todas las vistas hacen LEFT JOIN aquí en lugar de CASE WHEN hardcodeado.
# Para añadir o cambiar una cuenta basta con insertar/actualizar una fila.

resource "google_bigquery_table" "payer_billing_accounts" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.billing_cloud_platform.dataset_id
  table_id            = "payer_billing_accounts"
  deletion_protection = false
  labels              = local.common_labels
  description         = "Lookup: mapeo de payer_billing_account_id a nombre de cuenta. Editar esta tabla para añadir/cambiar cuentas sin modificar las vistas."

  schema = jsonencode([
    {
      name        = "payer_billing_account_id"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "ID de la cuenta pagadora en el export de billing del revendedor"
    },
    {
      name        = "account_name"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Nombre o etiqueta de negocio de la cuenta"
    }
  ])
}
