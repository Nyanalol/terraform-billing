WITH
  all_gcp_costs AS (
  SELECT
    billing.billing_account_id AS billing_account_id,
    account.billing_account_desc__c as dominio,
    invoice.month AS invoice_month,
    billing.sku.description AS sku,
    IFNULL(SUM(cost),0) AS cost_gcp,
    IFNULL( SUM( (
        SELECT
          SUM(amount)
        FROM
          UNNEST(credits) AS credits
        WHERE
          type IS NULL
          OR NOT(type LIKE 'RESELLER_MARGIN')) ), 0 ) AS credits_gcp,
    0 AS reseller_margin_gmp,
    IFNULL( SUM( (
        SELECT
          SUM(amount)
        FROM
          UNNEST(credits) AS credits
        WHERE
          type='RESELLER_MARGIN') ), 0 ) AS reseller_margin_gcp,
    currency,
    IFNULL(pba.account_name, 'Unknown') AS account
  FROM `${project_id}.${billing_cp_dataset}.reseller_billing_detailed_export_v1` AS billing
  LEFT JOIN `${project_id}.${billing_views_dataset}.billing_accounts` account ON billing.billing_account_id = account.billing_account_id__c
  LEFT JOIN `${project_id}.${billing_cp_dataset}.payer_billing_accounts` AS pba ON billing.payer_billing_account_id = pba.payer_billing_account_id
    WHERE
      1=1
      AND billing_account_id LIKE '%-%-%'
      AND TIMESTAMP_TRUNC(export_time, DAY) >= TIMESTAMP(DATE_SUB(DATE_TRUNC(CURRENT_DATE(), MONTH), INTERVAL 3 MONTH))
      AND sku.description = 'GCP Partner-led Enhanced Support Variable Fee'
    GROUP BY
      billing.billing_account_id,
      dominio,
      invoice_month,
      currency,
      account,
      service,
      sku
    )
SELECT
  billing_account_id,
  dominio,
  invoice_month,
  sku,
  SUM(cost_gcp) as cost,
  IFNULL(SUM(reseller_margin_gmp),0) AS reseller_margin_gmp,
  IFNULL(SUM(reseller_margin_gcp),0) AS reseller_margin_gcp,
  currency,
  account
FROM
  all_gcp_costs

GROUP BY
  billing_account_id,
  dominio,
  invoice_month,
  sku,
  currency,
  account
ORDER BY
  invoice_month