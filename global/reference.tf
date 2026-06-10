# ─── Datos de referencia compartidos (proyecto global) ───────────────────────
# Tablas de referencia que alimentan el SQL de facturación de TODOS los países.
# Viven en el proyecto central para no duplicar (una sola carga al mes).

resource "google_bigquery_dataset" "reference" {
  project                    = var.global_project_id
  dataset_id                 = var.reference_dataset
  friendly_name              = "Billing Reference"
  description                = "Datos de referencia compartidos por todos los países (p.ej. tipos de cambio). Cargado por el ETL de Python."
  location                   = var.location
  delete_contents_on_destroy = false

  labels = {
    managed_by = "terraform"
    scope      = "global"
  }
}

# Tipos de cambio mensuales (sustituye al job de Talend currencies_exchange_rates).
# Lo carga etl/currencies/fetch_exchange_rates.py (idempotente por partición rate_date).
resource "google_bigquery_table" "currency_exchange_rates" {
  project             = var.global_project_id
  dataset_id          = google_bigquery_dataset.reference.dataset_id
  table_id            = "currency_exchange_rates"
  deletion_protection = false

  description = "Tipos de cambio por par de divisas y mes. rate(base->target): 1 unidad de base = exchange_rate unidades de target. Fuente: Hexarate."

  time_partitioning {
    type  = "DAY"
    field = "rate_date"
  }
  clustering = ["base_currency", "target_currency"]

  schema = jsonencode([
    { name = "base_currency", type = "STRING", mode = "REQUIRED", description = "Divisa origen (ISO 4217)." },
    { name = "target_currency", type = "STRING", mode = "REQUIRED", description = "Divisa destino (ISO 4217)." },
    { name = "exchange_rate", type = "FLOAT", mode = "REQUIRED", description = "1 base = exchange_rate target." },
    { name = "rate_date", type = "DATE", mode = "REQUIRED", description = "Fecha a la que corresponde el cambio (primer día del mes siguiente al facturado)." },
    { name = "billing_month", type = "STRING", mode = "REQUIRED", description = "Mes facturado YYYYMM al que aplica este cambio (para JOIN con invoice_month)." },
    { name = "fetched_at", type = "TIMESTAMP", mode = "NULLABLE", description = "Cuándo se obtuvo de la API." },
  ])

  labels = {
    managed_by = "terraform"
    loaded_by  = "etl-python"
  }
}
