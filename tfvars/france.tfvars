# PAIS ANTIGUO — ESQUELETO para futuro import. NO desplegar tal cual (estructura compatible,
# pero requiere import de lo existente + reconciliar vistas). Ver docs/MIGRACION_PAISES_ANTIGUOS.md.
project_id                     = "swofr-billing-prod"
country                        = "france"
billing_cloud_platform_dataset = "BILLINGFR_CLOUD_PLATFORM"
location                       = "EU"

# TODO: rellenar payer_billing_account_id. Cuentas: SWO FRANCE_EUR, SWO FRANCE_USD
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
