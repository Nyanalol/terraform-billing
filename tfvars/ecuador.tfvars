project_id                     = "swoec-billing-prod"
country                        = "ecuador"
billing_cloud_platform_dataset = "BILLINGEC_CLOUD_PLATFORM"
location                       = "EU"

payer_billing_accounts = {
  "010EC5-F9AD4D-3F556B" = "SWO ECUADOR_USD"
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

scheduled_query_service_account = "bigquery-talend@swoec-billing-prod.iam.gserviceaccount.com"

staging_bucket_name = "gcp-billing-process-staging-ec"
create_hmac_key     = true
