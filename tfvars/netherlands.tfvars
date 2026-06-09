# PAIS ANTIGUO — ESQUELETO para futuro import. NO desplegar tal cual.
# OJO: el dataset del export se llama "billing_export" (no BILLING*_CLOUD_PLATFORM).
# Ver docs/MIGRACION_PAISES_ANTIGUOS.md.
project_id                     = "swonl-billing-prod"
country                        = "netherlands"
billing_cloud_platform_dataset = "billing_export"
location                       = "EU"

# TODO: rellenar payer_billing_account_id. Cuentas: SWO NETHERLANDS_EUR, SWO NL_EUR - OCRE
payer_billing_accounts = {}

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
  "BRL" = "R$"
}

create_service_account = false # la SA ya existe
create_hmac_key        = false
