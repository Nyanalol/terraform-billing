project_id                     = "swoin-billing-prod"
country                        = "india"
billing_cloud_platform_dataset = "BILLING_IN_CLOUD_PLATFORM"
location                       = "EU"

payer_billing_accounts = {
  "01AD72-412BCE-A0F562" = "SWO INDIA_INR"
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

scheduled_query_service_account = "bigquery-talend@swoin-billing-prod.iam.gserviceaccount.com"

staging_bucket_name = "gcp-billing-process-staging-in"
create_hmac_key     = true

# Clausula Empresa_IP__c de Salesforce (config Talend). Ver generate-config-billing.ps1.
sf_empresa_ip = "Empresa_IP__c='001IV00001Wp2D5'"
