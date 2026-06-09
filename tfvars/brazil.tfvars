# PAIS ANTIGUO — ESQUELETO para futuro import. NO desplegar tal cual.
# Sin dataset looker_views (reporting en billing_views). ThirdParty Reseller = FALSE.
# Ver docs/MIGRACION_PAISES_ANTIGUOS.md.
project_id                     = "ipdb-billing-interno"
country                        = "brazil"
billing_cloud_platform_dataset = "BILLING_CLOUD_PLATFORMBRL"
location                       = "EU"

# TODO: rellenar payer_billing_account_id. Cuentas: SWO BRAZIL_BRL_GCP, SWO BRAZIL_BRL_MAPS
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

# ThirdParty Reseller Active = FALSE -> sin migracion de sku_third_party.
sku_third_party_migration_service_account = ""
