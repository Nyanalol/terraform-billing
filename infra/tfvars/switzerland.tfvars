# PAIS ANTIGUO — ESQUELETO para futuro import. NO desplegar tal cual.
# OJO: el dataset del export tiene TYPO -> "BIILING_CLOUD_PLATFORM" (doble I). Sin dataset third_party.
# Ver docs/MIGRACION_PAISES_ANTIGUOS.md.
project_id                     = "swo-billing-prod"
country                        = "switzerland"
billing_cloud_platform_dataset = "BIILING_CLOUD_PLATFORM"
location                       = "EU"

# TODO: rellenar payer_billing_account_id. Cuentas: SWO SWITZERLAND_USD/EUR/CHF (varias, OCRE y Google Cloud)
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

# Clausula Empresa_IP__c de Salesforce (config Talend). Ver generate-config-billing.ps1.
sf_empresa_ip = "Empresa_IP__c='001IV000012VppW'"
