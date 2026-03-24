SELECT
  billing_account_id,
  invoice_month,
  IFNULL(SUM(cost_gmp),0) AS cost_gmp,
  IFNULL(SUM(credits_gmp),0) AS credits_gmp,
  IFNULL(SUM(cost_gcp),0) AS cost_gcp,
  IFNULL(SUM(credits_gcp),0) AS credits_gcp,
  IFNULL(SUM(reseller_margin_gmp),0) AS reseller_margin_gmp,
  IFNULL(SUM(reseller_margin_gcp),0) AS reseller_margin_gcp,
  currency,
  account
FROM (
  SELECT
    billing.billing_account_id AS billing_account_id,
    invoice.month AS invoice_month,
    IFNULL(SUM(cost), 0) AS cost_gmp,
    IFNULL( SUM( (SELECT SUM(amount) FROM UNNEST(credits) AS credits WHERE type IS NULL OR NOT(type LIKE 'RESELLER_MARGIN')) ), 0 ) AS credits_gmp,
    0 AS cost_gcp,
    0 AS credits_gcp,
    IFNULL( SUM( (SELECT SUM(amount) FROM UNNEST(credits) AS credits WHERE type='RESELLER_MARGIN') ), 0 ) AS reseller_margin_gmp,
    0 AS reseller_margin_gcp,
    currency,
    IFNULL(pba.account_name, 'Unknown') AS account,
    FROM `${project_id}.${billing_cp_dataset}.reseller_billing_detailed_export_v1` AS billing
    LEFT JOIN `${project_id}.${billing_cp_dataset}.maps_services` maps_services ON service.description = maps_services.SKU
    LEFT JOIN `${project_id}.${billing_cp_dataset}.payer_billing_accounts` AS pba ON billing.payer_billing_account_id = pba.payer_billing_account_id
  WHERE 
    1=1
    AND billing_account_id LIKE '%-%-%'
    AND TIMESTAMP_TRUNC(export_time, DAY) >= TIMESTAMP(DATE_SUB(DATE_TRUNC(CURRENT_DATE(), MONTH), INTERVAL 3 MONTH))
   AND (service.description IN ( 'Distance Matrix API',
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
      OR maps_services.SKU IS NOT NULL)
    AND NOT (service.description IN ( 'Anthos',
        'Invoice',
        'Maps Reseller Program',
        'Reseller Program',
        'Support',
        'SendGrid' ) )
  GROUP BY
    billing.billing_account_id,
    invoice_month, currency, account
   ) AS t
GROUP BY
  billing_account_id,
  invoice_month, currency, 
  account