#standardSQL
SELECT
    billing.invoice_month,
    cost_gcp,
    credits_gcp,
    IFNULL(GREATEST(cost_gcp + credits_gcp, 0), 0) AS total_gcp,
    cost_gmp,
    credits_gmp,
    IFNULL(GREATEST(cost_gmp + credits_gmp, 0), 0) AS total_gmp,
    billing.billing_account_id AS billing_account_id,
    project_id,
    reseller_margin_gmp,
    reseller_margin_gcp,
    currency,
    cost_thirdparty,
    credits_thirdparty,
    IFNULL(cost_thirdparty + credits_thirdparty, 0) AS total_thirdparty
FROM (
    SELECT * FROM `{project}.{input_dataset}.sum_costs_credits_per_month_by_project`
    WHERE invoice_month = '{year}{month}'
) billing
