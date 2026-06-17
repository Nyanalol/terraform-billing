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
    reseller_margin_gmp,
    reseller_margin_gcp,
    reseller_margin_thirdparty_marketplace,
    currency,
    cost_thirdparty,
    credits_thirdparty,
    IFNULL(cost_thirdparty + credits_thirdparty, 0) AS total_thirdparty,
    cost_thirdparty_marketplace,
    credits_thirdparty_marketplace,
    IFNULL(cost_thirdparty_marketplace + credits_thirdparty_marketplace, 0) AS total_thirdparty_marketplace,
    customer_cost_thirdparty_marketplace,
    IFNULL(customer_cost_thirdparty_marketplace + credits_thirdparty_marketplace, 0) AS total_customer_cost_thirdparty_marketplace
FROM (
    SELECT * FROM `{project}.{input_dataset}.sum_costs_credits_per_month`
    WHERE invoice_month = '{year}{month}'
) billing
