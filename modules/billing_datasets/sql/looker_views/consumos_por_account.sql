SELECT
  *,
  (total_gcp * 0.9 + total_gmp * 0.8) AS cargo_google
FROM (
  SELECT
    costes.billing_account_id,
    account.Billing_Model__c AS billing_model,
    cost_gcp,
    cost_gmp,
    credits_gcp,
    credits_gmp,
    account.billing_account_desc__c AS cuenta,
    account.billing_account_desc__c AS dominio,
    (cost_gcp + credits_gcp) AS total_gcp,
    (cost_gmp + credits_gmp) AS total_gmp,
    (cost_thirdparty + credits_thirdparty) AS total_thirdparty,
    (cost_base_thirdparty + credits_thirdparty) AS total_base_thirdparty,
    (cost_thirdparty_marketplace + credits_thirdparty_marketplace) AS total_thirdparty_marketplace,
    costes.account,
    reseller_margin_gmp,
    reseller_margin_gcp,
    costes.invoice_month
  FROM `${project_id}.${billing_views_dataset}.sum_costs_credits_per_month` costes
  LEFT JOIN `${project_id}.${billing_views_dataset}.billing_accounts` account ON costes.billing_account_id = account.billing_account_id__c
)