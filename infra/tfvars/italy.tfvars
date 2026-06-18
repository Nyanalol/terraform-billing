# GENERADO por tools/gen_tfvars.py desde countries.yaml — NO editar a mano.

project_id                     = "swoit-billing-prod"
country                        = "italy"
billing_cloud_platform_dataset = "BILLINGIT_CLOUD_PLATFORM"
location                       = "EU"

payer_billing_accounts = {
  "011588-6DAA41-00B2F2" = "SWO ITALY_EUR"
  "012D46-9BB008-D9D029" = "SWO ITALY_USD"
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
}

scheduled_query_service_account = "bigquery-talend@swoit-billing-prod.iam.gserviceaccount.com"

create_hmac_key     = false

# Cláusula Empresa_IP__c de Salesforce (config Talend). Ver generate-config-billing.ps1.
sf_empresa_ip = "Empresa_IP__c='001IV00000WmUB4'"
