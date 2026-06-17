# Plantilla por país. Copia este fichero como tfvars/<país>.tfvars y rellénalo.
# Los datos de cada país están en docs/PAISES.md.
# Despliegue:  terraform init -reconfigure -backend-config="prefix=billing/<país>"
#              terraform apply -var-file="tfvars/<país>.tfvars"

project_id                     = "swoit-billing-prod"
country                        = "italy"
billing_cloud_platform_dataset = "BILLINGIT_CLOUD_PLATFORM"
location                       = "EU"

# ─── Cuentas pagadoras (payer_billing_account_id → nombre visible) ──────────
payer_billing_accounts = {
  "011588-6DAA41-00B2F2" = "SWO ITALY_EUR"
  "012D46-9BB008-D9D029" = "SWO ITALY_USD"
}

# ─── Símbolos de divisa (CurrencyIsoCode → símbolo) ─────────────────────────
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

# ─── Service Account (Terraform la crea y le da bigquery.admin + storage.admin,
#     y dataViewer + jobUser cruzados en España) ──────────────────────────────
# create_service_account = false   # si la SA ya existe (creada a mano)
# manage_spain_iam       = true    # false para no tocar la IAM de España

# ─── Bucket de staging + HMAC (pasos 15-16) ─────────────────────────────────
staging_bucket_name = "gcp-billing-process-staging-it" # vacío = no crear bucket
create_hmac_key     = true                             # output: hmac_access_id / hmac_secret

# Migración de sku_third_party desde España. Vacío = no aplica.
sku_third_party_migration_service_account = ""
