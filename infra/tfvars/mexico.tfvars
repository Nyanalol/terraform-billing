# GENERADO por tools/gen_tfvars.py desde countries.yaml — NO editar a mano.

project_id                     = "swo-billing-prod-484513"
country                        = "mexico"
billing_cloud_platform_dataset = "BILLINGMX_CLOUD_PLATFORM"
location                       = "EU"

payer_billing_accounts = {
  "010CE7-4E8471-6CA88E" = "SWO MEXICO_MXN"
  "01AEA2-F3EE1F-C36BDE" = "SWO MEXICO_USD"
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

scheduled_query_service_account = "bigquery-talend@swo-billing-prod-484513.iam.gserviceaccount.com"

staging_bucket_name = "gcp-billing-process-staging-mx"
create_hmac_key     = true

# Cláusula Empresa_IP__c de Salesforce (config Talend). Ver generate-config-billing.ps1.
sf_empresa_ip = "Empresa_IP__c='001IV00001RclHJ'"
