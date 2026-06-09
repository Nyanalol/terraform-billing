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

create_hmac_key = true
