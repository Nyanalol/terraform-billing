project_id                     = "swobe-billing-prod"
country                        = "belgium"
billing_cloud_platform_dataset = "BILLINGBE_CLOUD_PLATFORM"
location                       = "EU"

payer_billing_accounts = {
  "01F127-DED7D3-5138B6" = "SWO BELGIUM_EUR"
  "018972-66E343-DEF21E" = "SWO BELGIUM_USD"
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

scheduled_query_service_account = "bigquery-talend@swobe-billing-prod.iam.gserviceaccount.com"

staging_bucket_name = "gcp-billing-process-staging-be"
create_hmac_key     = true
