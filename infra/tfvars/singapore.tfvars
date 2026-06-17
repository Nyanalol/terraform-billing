project_id                     = "swosg-billing-prod" # OJO: swosg- (no swo-sg-, que era lo que decia el email de Ops)
country                        = "singapore"
billing_cloud_platform_dataset = "BILLINGSG_CLOUD_PLATFORM"
location                       = "EU"

payer_billing_accounts = {
  "016521-E5DD08-72768E" = "SWO SINGAPORE_SGD"
  "01C5C9-AD6259-5D2D50" = "SWO SINGAPORE_USD"
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

scheduled_query_service_account = "bigquery-talend@swosg-billing-prod.iam.gserviceaccount.com"

staging_bucket_name = "gcp-billing-process-staging-sg"
create_hmac_key     = true

# Clausula Empresa_IP__c de Salesforce (config Talend). Ver generate-config-billing.ps1.
sf_empresa_ip = "Empresa_IP__c='001IV00001fGos1'"
