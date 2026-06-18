# GENERADO por tools/gen_tfvars.py desde countries.yaml — NO editar a mano.

project_id                     = "swo-billing-prod-hk"
country                        = "honk-kong"
billing_cloud_platform_dataset = "BILLING_HK_CLOUD_PLATFORM"
location                       = "EU"

payer_billing_accounts = {
  "012026-D15FE4-ACC5D6" = "SWOHK-BILLING-PROD"
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

scheduled_query_service_account = "bigquery-talend@swo-billing-prod-hk.iam.gserviceaccount.com"

create_service_account = false   # la SA ya existe (creada a mano antes de Terraform)
staging_bucket_name = "gcp-billing-process-staging-hk"
create_hmac_key     = true

sku_third_party_migration_service_account = ""

# Cláusula Empresa_IP__c de Salesforce (config Talend). Ver generate-config-billing.ps1.
sf_empresa_ip = "Empresa_IP__c='001IV00001JLmUT'"
