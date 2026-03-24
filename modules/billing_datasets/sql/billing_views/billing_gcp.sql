WITH
  all_gcp_costs AS (
  SELECT
    billing.billing_account_id AS billing_account_id,
    invoice.month AS invoice_month,
    service.description AS service,
    billing.sku.description AS sku,
    (project.id IS NULL) AS project_is_null,
    project.id AS project_id,
    0 AS cost_gmp,
    0 AS credits_gmp,
    IFNULL(SUM(cost), 0) AS cost_gcp,
    IFNULL(SUM(customer_cost), 0) AS customer_cost,
    IFNULL( SUM((SELECT SUM(amount) FROM UNNEST(credits) AS credits WHERE type IS NULL OR NOT(type LIKE 'RESELLER_MARGIN'))), 0 ) AS credits_gcp,
    0 AS reseller_margin_gmp,
    IFNULL( SUM((SELECT SUM(amount) FROM UNNEST(credits) AS credits WHERE type = 'RESELLER_MARGIN')), 0 ) AS reseller_margin_gcp,
    currency,
    IFNULL(pba.account_name, 'Unknown') AS account,
    ((sku_id IS NOT NULL)  OR (billing.transaction_type IN ('THIRD_PARTY_RESELLER', 'THIRD_PARTY_AGENCY') AND billing.seller_name IS NULL)) AS is_third_party,
    (billing.transaction_type IN ('THIRD_PARTY_RESELLER', 'THIRD_PARTY_AGENCY') AND billing.seller_name IS NOT NULL AND billing.service.description != 'Compute Engine') AS is_third_party_marketplace,
  FROM `${project_id}.${billing_cp_dataset}.reseller_billing_detailed_export_v1` AS billing
  LEFT JOIN `${project_id}.${billing_cp_dataset}.sku_third_party` ON billing.sku.id = sku_id
  LEFT JOIN `${project_id}.${billing_cp_dataset}.maps_services` maps_services ON service.description = maps_services.SKU
  LEFT JOIN `${project_id}.${billing_cp_dataset}.payer_billing_accounts` AS pba ON billing.payer_billing_account_id = pba.payer_billing_account_id
  WHERE 1 = 1
    AND billing_account_id LIKE '%-%-%'
    AND TIMESTAMP_TRUNC(export_time, DAY) >= TIMESTAMP(DATE_SUB(DATE_TRUNC(CURRENT_DATE(), MONTH), INTERVAL 3 MONTH))
    AND NOT (service.description IN ( 
      'Distance Matrix API', 
      'Street View API', 
      'Zagat content in the Places API', 
      'Maps Static API', 
      'Places API for iOS', 
      'Maps Elevation API', 
      'Maps API', 
      'Places API for Android', 
      'Street View Static API', 
      'Geocoding API', 
      'Maps Reseller Program', 
      'Google Maps Android API', 
      'Maps and Street View API', 
      'Directions API', 
      'Maps JavaScript API', 
      'Google Maps SDK for iOS', 
      'Places API', 
      'Time Zone API', 
      'Maps Embed API', 
      'Roads API', 
      'Geolocation API', 
      'Navigation API', 
      'Google Maps Platform Rides and Deliveries Service')
      OR service.description LIKE '%maps%'
      OR service.description LIKE '%Maps%'
      OR service.description LIKE '%Place%'
      OR maps_services.SKU IS NOT NULL )
    AND NOT (service.description IN ( 'Invoice', 'Maps Reseller Program', 'Reseller Program', 'SendGrid' ) )
    AND billing.sku.description != 'GCP Partner-led Enhanced Support Variable Fee'
  GROUP BY
    billing.billing_account_id,
    invoice_month,
    currency,
    account,
    service,
    sku,
    project_is_null,
    project_id,
    is_third_party,
    is_third_party_marketplace
    )
SELECT
  billing_account_id,
  invoice_month,
  IFNULL(SUM(cost_gmp), 0) AS cost_gmp,
  IFNULL(SUM(credits_gmp), 0) AS credits_gmp,
  IFNULL(SUM( IF(NOT (is_third_party OR is_third_party_marketplace OR (project_is_null = TRUE AND reseller_margin_gcp = 0)), cost_gcp, 0)), 0) AS cost_gcp,
  IFNULL(SUM( IF(NOT (is_third_party OR is_third_party_marketplace OR (project_is_null = TRUE AND reseller_margin_gcp = 0)), credits_gcp, 0)), 0) AS credits_gcp,
  IFNULL(SUM(reseller_margin_gmp), 0) AS reseller_margin_gmp,
  IFNULL(SUM(reseller_margin_gcp), 0) AS reseller_margin_gcp,
  currency,
  account,

  SUM(IF( is_third_party OR (project_is_null = TRUE AND reseller_margin_gcp = 0 AND NOT is_third_party_marketplace), IFNULL(customer_cost, 0), 0)) AS cost_thirdparty,
  SUM(IF( is_third_party OR (project_is_null = TRUE AND reseller_margin_gcp = 0 AND NOT is_third_party_marketplace), IFNULL(cost_gcp, 0), 0)) AS cost_base_thirdparty,
  SUM(IF( is_third_party OR (project_is_null = TRUE AND reseller_margin_gcp = 0 AND NOT is_third_party_marketplace), IFNULL(credits_gcp, 0), 0)) AS credits_thirdparty,

  SUM(IF( is_third_party_marketplace, IFNULL(cost_gcp, 0), 0)) AS cost_thirdparty_marketplace,
  SUM(IF( is_third_party_marketplace, IFNULL(customer_cost, 0), 0)) AS customer_cost_thirdparty_marketplace,
  SUM(IF( is_third_party_marketplace, IFNULL(credits_gcp, 0), 0)) AS credits_thirdparty_marketplace

FROM all_gcp_costs
GROUP BY
  billing_account_id,
  invoice_month,
  currency,
  account
    
