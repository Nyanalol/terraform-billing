# GENERADO por tools/gen_tfvars.py desde countries.yaml — NO editar a mano.
# PAÍS ANTIGUO / ESQUELETO — NO desplegar tal cual. Ver docs/MIGRACION_PAISES_ANTIGUOS.md.

project_id                     = "swonl-billing-prod"
country                        = "netherlands"
billing_cloud_platform_dataset = "billing_export"
location                       = "EU"

payer_billing_accounts = {
  "01341E-7E79EA-92E816" = "SWO NETHERLANDS_EUR"
  "011FFE-F0683A-226427" = "SWO NL_EUR - OCRE"
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

scheduled_query_service_account = "bigquery-talend@swonl-billing-prod.iam.gserviceaccount.com"

create_service_account = false   # la SA ya existe (creada a mano antes de Terraform)
create_hmac_key     = false

# Cláusula Empresa_IP__c de Salesforce (config Talend). Ver generate-config-billing.ps1.
sf_empresa_ip = "Empresa_IP__c='001IV00000rOsnC'"
