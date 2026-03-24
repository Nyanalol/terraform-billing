# ─── Seed data: payer_billing_accounts ───────────────────────────────────────
# Populates the payer_billing_accounts lookup table from var.payer_billing_accounts.
#
# HOW IT WORKS:
#   The job_id includes a hash of the map contents. When the map changes in
#   tfvars, the hash changes → Terraform creates a new BigQuery job that runs
#   CREATE OR REPLACE TABLE, reloading all rows atomically (WRITE_TRUNCATE).
#   The old job is simply removed from state (BigQuery jobs cannot be deleted).
#
# USAGE (in terraform.tfvars):
#   payer_billing_accounts = {
#     "AAAAAA-BBBBBB-CCCCCC" = "Cuenta Principal EUR"
#     "DDDDDD-EEEEEE-FFFFFF" = "Cuenta Secundaria USD"
#   }

locals {
  # Build the STRUCT list for the UNNEST literal, one entry per account.
  payer_billing_accounts_structs = join(",\n        ", [
    for id, name in var.payer_billing_accounts :
    "STRUCT('${id}' AS payer_billing_account_id, '${name}' AS account_name)"
  ])
}

# ─── Seed data: currency_symbols ─────────────────────────────────────────────
locals {
  currency_symbols_structs = join(",\n        ", [
    for code, symbol in var.currency_symbols :
    "STRUCT('${code}' AS currency_iso_code, '${symbol}' AS symbol)"
  ])
}

resource "google_bigquery_job" "seed_currency_symbols" {
  count = length(var.currency_symbols) > 0 ? 1 : 0

  job_id   = "seed-currency-symbols-${replace(var.country, "_", "-")}-${substr(sha256(jsonencode(var.currency_symbols)), 0, 8)}"
  project  = var.project_id
  location = var.location

  query {
    use_legacy_sql = false
    query          = <<-SQL
      CREATE OR REPLACE TABLE `${var.project_id}.${google_bigquery_dataset.billing_cloud_platform.dataset_id}.currency_symbols` AS
      SELECT currency_iso_code, symbol
      FROM UNNEST([
        ${local.currency_symbols_structs}
      ])
    SQL
  }

  depends_on = [google_bigquery_table.currency_symbols]
}

resource "google_bigquery_job" "seed_payer_billing_accounts" {
  # Only create the job if there is at least one entry in the map.
  count = length(var.payer_billing_accounts) > 0 ? 1 : 0

  # Hash-based suffix: changes when map content changes → triggers a new run.
  job_id   = "seed-payer-billing-accounts-${replace(var.country, "_", "-")}-${substr(sha256(jsonencode(var.payer_billing_accounts)), 0, 8)}"
  project  = var.project_id
  location = var.location

  query {
    use_legacy_sql = false
    query          = <<-SQL
      CREATE OR REPLACE TABLE `${var.project_id}.${google_bigquery_dataset.billing_cloud_platform.dataset_id}.payer_billing_accounts` AS
      SELECT payer_billing_account_id, account_name
      FROM UNNEST([
        ${local.payer_billing_accounts_structs}
      ])
    SQL
  }

  # Ensure the target table exists before loading data into it.
  depends_on = [google_bigquery_table.payer_billing_accounts]
}
