WITH aux_table AS ( 
  SELECT 
    billing_account_id,
    payer_billing_account_id,
    invoice.month AS invoice_month,
    PARSE_DATE('%Y%m%d', CONCAT(invoice.month, '01')) AS invoice_date,
    usage.amount AS usage_amount,
    usage.unit   AS usage_unit,
    cost,
    currency,
    currency_conversion_rate,
    service.id          AS service_id,
    service.description AS service_description,
    sku.id              AS sku_id,
    sku.description     AS sku_description,
    DATE(usage_start_time) AS usage_start_time,
    DATE(usage_end_time)   AS usage_end_time,
    export_time,
    sf.sku_sf_flex,
    sf.sku_sf_month,

    CONCAT(
      '{',
      ARRAY_TO_STRING(
        ARRAY(
          SELECT FORMAT('"%s": "%s"',
                        IF(CONTAINS_SUBSTR(kv.key, '/'),
                           REGEXP_EXTRACT(kv.key, r'/([^/]+)$'),
                           kv.key),
                        kv.value)
          FROM UNNEST(IFNULL(system_labels, [])) AS kv
        ), ', '
      ),
      '}'
    ) AS attributes_json
  FROM `${project_id}.${billing_cp_dataset}.reseller_billing_detailed_export_v1` AS export
  LEFT JOIN `${project_id}.${billing_cp_dataset}.workspace_sku_sf` AS sf
    ON export.sku.id = sf.sku_id
  WHERE TIMESTAMP_TRUNC(export_time, DAY) >= TIMESTAMP(
          DATE_SUB(DATE_TRUNC(CURRENT_DATE(), MONTH), INTERVAL 3 MONTH)
        )
  
),

no_agg_flex AS (
  SELECT * FROM (
    SELECT 
      *,

      JSON_EXTRACT_SCALAR(attributes_json, '$.domain_name')        AS domain_name,
      JSON_EXTRACT_SCALAR(attributes_json, '$.order_id')           AS order_id,
      JSON_EXTRACT_SCALAR(attributes_json, '$.purchase_order_id')  AS purchase_order_id,
      JSON_EXTRACT_SCALAR(attributes_json, '$.subscription_id')    AS subscription_id,
      JSON_EXTRACT_SCALAR(attributes_json, '$.usage_type')         AS usage_type,

      sku_sf_flex AS sku_sf,
      sku_sf_flex IS NULL AS match_sf
    FROM aux_table
  )
  WHERE usage_type = 'FLEXIBLE_SEATS_ITEM'
    AND cost != 0
),

agg_flex AS (
  SELECT
    billing_account_id,
    payer_billing_account_id,
    invoice_month,
    invoice_date,
    currency,
    currency_conversion_rate,
    service_id,
    service_description,
    sku_id,
    sku_description,
    domain_name,
    order_id,
    sku_sf,
    SUM(cost)                                   AS google_charge,
    ROUND(AVG(ABS(usage_amount)))               AS usage_amount,
    ANY_VALUE(usage_unit)                       AS usage_unit,
    MIN(usage_start_time)                       AS usage_start_time,
    MAX(usage_end_time)                         AS usage_end_time,
    MAX(export_time)                            AS export_time,
    ANY_VALUE(match_sf)                         AS match_sf,
    ANY_VALUE(attributes_json)                  AS attributes_json,
    ANY_VALUE(purchase_order_id)                AS purchase_order_id,
    ANY_VALUE(subscription_id)                  AS subscription_id,
    'FLEXIBLE_SEATS_ITEM'                       AS usage_type
  FROM no_agg_flex
  GROUP BY
    billing_account_id, payer_billing_account_id, invoice_month, invoice_date,
    currency, currency_conversion_rate, service_id, service_description,
    sku_id, sku_description, domain_name, order_id, sku_sf
),

no_agg_month_raw AS (
  SELECT * FROM (
    SELECT 
      *,
      JSON_EXTRACT_SCALAR(attributes_json, '$.domain_name')        AS domain_name,
      JSON_EXTRACT_SCALAR(attributes_json, '$.order_id')           AS order_id,
      JSON_EXTRACT_SCALAR(attributes_json, '$.purchase_order_id')  AS purchase_order_id,
      JSON_EXTRACT_SCALAR(attributes_json, '$.subscription_id')    AS subscription_id,
      JSON_EXTRACT_SCALAR(attributes_json, '$.usage_type')         AS usage_type,

      sku_sf_month AS sku_sf,
      sku_sf_month IS NULL AS match_sf
    FROM aux_table
  )
  WHERE usage_type IN ('COMMITMENT_MONTHLY_ITEM','COMMITMENT_SEATS_CHANGE_ITEM', 'COMMITMENT_TERM_START_ITEM')
    AND cost != 0
),

no_agg_monthly AS (
  SELECT t.*
  FROM no_agg_month_raw t
  WHERE t.usage_type IN ('COMMITMENT_MONTHLY_ITEM', 'COMMITMENT_TERM_START_ITEM')
     OR (
       t.usage_type IN ('COMMITMENT_SEATS_CHANGE','COMMITMENT_SEATS_CHANGE_ITEM')
       AND EXISTS (
         SELECT 1
         FROM no_agg_month_raw m
         WHERE m.invoice_month = t.invoice_month
           AND m.domain_name   = t.domain_name
           AND m.sku_id        = t.sku_id
           AND m.usage_type IN ('COMMITMENT_MONTHLY_ITEM', 'COMMITMENT_TERM_START_ITEM')       )
     )
),

no_agg_table AS (
  SELECT
    billing_account_id, payer_billing_account_id, invoice_month, invoice_date,
    usage_amount, usage_unit, google_charge, currency, currency_conversion_rate,
    service_id, service_description, sku_id, sku_description,
    usage_start_time, usage_end_time, export_time,
    sku_sf, match_sf, attributes_json,
    domain_name, order_id, purchase_order_id, subscription_id,
    usage_type
  FROM agg_flex

  UNION ALL

  SELECT
    billing_account_id, payer_billing_account_id, invoice_month, invoice_date,
    usage_amount, usage_unit, cost AS google_charge, currency, currency_conversion_rate,
    service_id, service_description, sku_id, sku_description,
    usage_start_time, usage_end_time, export_time,
    sku_sf, match_sf, attributes_json,
    domain_name, order_id, purchase_order_id, subscription_id,
    usage_type
  FROM no_agg_monthly
)
SELECT *
FROM no_agg_table
WHERE google_charge != 0
