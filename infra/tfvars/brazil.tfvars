# GENERADO por tools/gen_tfvars.py desde countries.yaml — NO editar a mano.
# PAÍS ANTIGUO / ESQUELETO — NO desplegar tal cual. Ver docs/MIGRACION_PAISES_ANTIGUOS.md.

project_id                     = "ipdb-billing-interno"
country                        = "brazil"
billing_cloud_platform_dataset = "BILLING_CLOUD_PLATFORMBRL"
location                       = "EU"

payer_billing_accounts = {
  "0120C2-4D1D47-5C12C7" = "SWO BRAZIL_BRL_GCP"
  "01DC38-521399-1EAC42" = "SWO BRAZIL_BRL_MAPS"
}

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

create_service_account = false   # la SA ya existe (creada a mano antes de Terraform)
create_hmac_key     = false

sku_third_party_migration_service_account = ""

# Cláusula Empresa_IP__c de Salesforce (config Talend). Ver generate-config-billing.ps1.
sf_empresa_ip = "Empresa_IP__c='0015700001lTrkuAAC'"
