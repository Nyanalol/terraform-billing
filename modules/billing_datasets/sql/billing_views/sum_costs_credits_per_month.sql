SELECT
  billing_account_id,
  invoice_month,
  SUM(cost_gmp) AS cost_gmp,
  SUM(credits_gmp) AS credits_gmp,
  SUM(cost_gcp) AS cost_gcp,
  SUM(credits_gcp) AS credits_gcp,
  SUM(reseller_margin_gmp) AS reseller_margin_gmp,
  SUM(reseller_margin_gcp) AS reseller_margin_gcp,
  currency,
  account,
  SUM(cost_thirdparty) AS cost_thirdparty,
  SUM(cost_base_thirdparty) AS cost_base_thirdparty,
  SUM(credits_thirdparty) AS credits_thirdparty,
  SUM(cost_thirdparty_marketplace) AS cost_thirdparty_marketplace,
  SUM(customer_cost_thirdparty_marketplace) AS customer_cost_thirdparty_marketplace,
  SUM(credits_thirdparty_marketplace) AS credits_thirdparty_marketplace
FROM (
  SELECT
    billing_account_id,
    invoice_month,
    cost_gmp,
    credits_gmp,
    cost_gcp,
    credits_gcp,
    reseller_margin_gmp,
    reseller_margin_gcp,
    currency,
    account,
    0 AS cost_thirdparty,
    0 AS cost_base_thirdparty,
    0 AS credits_thirdparty,
    0 AS cost_thirdparty_marketplace,
    0 AS customer_cost_thirdparty_marketplace,
    0 AS credits_thirdparty_marketplace
  FROM
    `${project_id}.${billing_views_dataset}.billing_gmp`
  UNION ALL
  SELECT
    billing_account_id,
    invoice_month,
    cost_gmp,
    credits_gmp,
    cost_gcp,
    credits_gcp,
    reseller_margin_gmp,
    reseller_margin_gcp,
    currency,
    account,
    cost_thirdparty,
    cost_base_thirdparty,
    credits_thirdparty,
    cost_thirdparty_marketplace,
    customer_cost_thirdparty_marketplace,
    credits_thirdparty_marketplace
  FROM
    `${project_id}.${billing_views_dataset}.billing_gcp` ) AS t
GROUP BY
  billing_account_id,
  invoice_month,
  currency,
  account