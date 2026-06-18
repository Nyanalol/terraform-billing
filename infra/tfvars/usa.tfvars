# GENERADO por tools/gen_tfvars.py desde countries.yaml — NO editar a mano.

project_id                     = "swous-billing-prod"
country                        = "usa"
billing_cloud_platform_dataset = "BILLINGUS_CLOUD_PLATFORM"
location                       = "EU"

payer_billing_accounts = {
  "014A14-300F5E-58E68F" = "SWO USA_USD"
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

scheduled_query_service_account = "bigquery-talend@swous-billing-prod.iam.gserviceaccount.com"

staging_bucket_name = "gcp-billing-process-staging-us"
create_hmac_key     = true

# Cláusula Empresa_IP__c de Salesforce (config Talend). Ver generate-config-billing.ps1.
sf_empresa_ip = "Empresa_IP__c='001IV00000fytRt'"
