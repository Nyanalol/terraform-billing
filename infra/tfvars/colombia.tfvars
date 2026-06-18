# GENERADO por tools/gen_tfvars.py desde countries.yaml — NO editar a mano.

project_id                     = "swoco-billing-prod"
country                        = "colombia"
billing_cloud_platform_dataset = "BILLINGCO_CLOUD_PLATFORM"
location                       = "EU"

payer_billing_accounts = {
  "012514-E29E2A-7004C7" = "SWO COLOMBIA_USD"
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

scheduled_query_service_account = "bigquery-talend@swoco-billing-prod.iam.gserviceaccount.com"

staging_bucket_name = "gcp-billing-process-staging-co"
create_hmac_key     = true

# Cláusula Empresa_IP__c de Salesforce (config Talend). Ver generate-config-billing.ps1.
sf_empresa_ip = "Empresa_IP__c='001IV00001PehnLYAR'"
