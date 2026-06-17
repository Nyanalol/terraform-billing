#standardSQL
SELECT
    invoice_month,
    usage_amount,
    usage_unit,
    google_charge,
    currency,
    currency_conversion_rate,
    service_description,
    sku_description,
    usage_start_time,
    usage_end_time,
    domain_name,
    order_id,
    sku_id,
    sku_sf,
    usage_type
FROM `{project}.{workspace_dataset}.reseller_view`
WHERE invoice_month = '{year}{month}'
