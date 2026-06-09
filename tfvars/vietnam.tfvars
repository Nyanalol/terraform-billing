project_id                     = "swovn-billing-prod"
country                        = "vietnam"
billing_cloud_platform_dataset = "BILLING_VN_CLOUD_PLATFORM" # OJO: con guion bajo (verificado), no BILLINGVN_...
location                       = "EU"

payer_billing_accounts = {
  "01979E-D5CB5A-E064DB" = "SWO VIETNAM_USD"
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

scheduled_query_service_account = "bigquery-talend@swovn-billing-prod.iam.gserviceaccount.com"

create_hmac_key = true
