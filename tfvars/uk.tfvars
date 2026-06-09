# PAIS ANTIGUO — ESQUELETO para futuro import. NO desplegar tal cual.
# Ver docs/MIGRACION_PAISES_ANTIGUOS.md.
project_id                     = "swouk-billing-prod"
country                        = "uk"
billing_cloud_platform_dataset = "BILLINGUK_CLOUD_PLATFORM"
location                       = "EU"

# TODO: rellenar payer_billing_account_id. Cuentas: SWO UK_GBP, SWO UK_GBP - OCRE
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
