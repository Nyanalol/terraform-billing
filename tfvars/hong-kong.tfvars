project_id                     = "swo-billing-prod-hk"
country                        = "honk-kong"
billing_cloud_platform_dataset = "BILLING_HK_CLOUD_PLATFORM"
location                       = "EU"

# ─── Cuentas pagadoras ─────────────────────────────────────────────────────
payer_billing_accounts = {
  "012026-D15FE4-ACC5D6" = "SWOHK-BILLING-PROD"
}

# ─── Símbolos de divisa ────────────────────────────────────────────────────
currency_symbols = {
  "EUR" = "€"
  "USD" = "$"
  "GBP" = "£"
  "HKD" = "HK$"
  "INR" = "₹"
  "VND" = "₫"
  "MXN" = "MX$"
  "COP" = "COL$"
  "SGD" = "S$"
  "CHF" = "Fr"
}

scheduled_query_service_account = "bigquery-talend@swo-billing-prod-hk.iam.gserviceaccount.com"

# La SA de HK ya existía (creada a mano antes de Terraform) → no la recreamos.
create_service_account = false

# HMAC: org policy ya levantada por OPS → creada.
staging_bucket_name = "gcp-billing-process-staging-hk"
create_hmac_key     = true

sku_third_party_migration_service_account = ""
