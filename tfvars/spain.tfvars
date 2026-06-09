# PAIS ANTIGUO (proyecto central ip-billing-prod) — ESQUELETO para futuro import.
# NO desplegar tal cual: es el mas complejo y arriesgado (sin looker_views/third_party,
# reporting en tableau_views, multiples datasets extra). Ver docs/MIGRACION_PAISES_ANTIGUOS.md.
project_id                     = "ip-billing-prod"
country                        = "spain"
billing_cloud_platform_dataset = "BILLING_CLOUD_PLATFORM"
location                       = "EU"

# TODO: rellenar con los payer_billing_account_id (sacar de reseller_billing_detailed_export_v1).
# Cuentas: SWO SPAIN_EUR - OCRE, SWO SPAIN_EUR, SWO SPAIN_GBP, SWO SPAIN_USD
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
manage_spain_iam       = false # ES Espana: no aplicar IAM cruzado a si mismo
create_hmac_key        = false

# Espana es el ORIGEN de la migracion de sku_third_party (no la recibe).
sku_third_party_migration_service_account = ""
