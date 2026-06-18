# GENERADO por tools/gen_tfvars.py desde countries.yaml — NO editar a mano.
# PAÍS ANTIGUO / ESQUELETO — NO desplegar tal cual. Ver docs/MIGRACION_PAISES_ANTIGUOS.md.

project_id                     = "ip-billing-prod"
country                        = "spain"
billing_cloud_platform_dataset = "BILLING_CLOUD_PLATFORM"
location                       = "EU"

payer_billing_accounts = {
  "001244-593F93-3FC8DF" = "SWO SPAIN_EUR"
  "01161C-DDDB50-45D065" = "SWO SPAIN_EUR - OCRE"
  "0194A7-052425-63DF63" = "SWO SPAIN_USD"
  "01C497-D03C3E-04B5C6" = "SWO SPAIN_GBP"
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

scheduled_query_service_account = "bigquery-talend@ip-billing-prod.iam.gserviceaccount.com"

create_service_account = false   # la SA ya existe (creada a mano antes de Terraform)
create_hmac_key     = false

sku_third_party_migration_service_account = ""
manage_spain_iam = false

# Cláusula Empresa_IP__c de Salesforce (config Talend). Ver generate-config-billing.ps1.
sf_empresa_ip = "(Empresa_IP__c='0015700001lTrioAAC' OR Empresa_IP__c='001IV00001TJUpHYAX')"
