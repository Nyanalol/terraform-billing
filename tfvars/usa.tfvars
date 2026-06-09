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

create_hmac_key = true
