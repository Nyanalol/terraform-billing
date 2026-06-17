SELECT
  billing_account_id,
  invoice_month,
  project_id,
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
  SUM(credits_thirdparty) AS credits_thirdparty
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
    project_id
  FROM
    `${project_id}.${billing_views_dataset}.billing_gmp_by_project`
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
    project_id
  FROM
    `${project_id}.${billing_views_dataset}.billing_gcp_by_project` ) AS t
GROUP BY
  billing_account_id,
  invoice_month,
  project_id,
  currency,
  account