CREATE VIEW `swouk-billing-prod.consolidado_src.consumos_por_account`
AS SELECT *, total_gcp_gmp + reseller_margin_gmp + reseller_margin_gcp + reseller_margin_thirdparty_marketplace AS total_net_cost,
  (total_gcp + total_gmp) - importe_margen AS old_importe_factura_google
FROM ( SELECT *, (total_gcp*0.9 + total_gmp*0.8) AS cargo_google,
    ROUND(total_gcp + total_gmp + total_thirdparty + total_thirdparty_marketplace, 2) AS total_gcp_gmp,
    (total_gmp*0.2) + (total_gcp*0.1) AS importe_margen
  FROM ( SELECT costes.billing_account_id, account.Billing_Model__c AS billing_model,
      cost_gcp, cost_gmp, credits_gcp, credits_gmp,
      account.billing_account_desc__c AS cuenta, account.billing_account_desc__c AS dominio,
      (cost_gcp+credits_gcp) AS total_gcp, (cost_gmp+credits_gmp) AS total_gmp,
      (cost_thirdparty+credits_thirdparty) AS total_thirdparty,
      (cost_base_thirdparty+credits_thirdparty) AS total_base_thirdparty,
      (cost_thirdparty_marketplace+credits_thirdparty_marketplace) AS total_thirdparty_marketplace,
      costes.account, reseller_margin_gmp, reseller_margin_gcp, reseller_margin_thirdparty_marketplace, costes.invoice_month
    FROM `swouk-billing-prod.billing_views.sum_costs_credits_per_month` costes
    LEFT JOIN `swouk-billing-prod.billing_views.billing_accounts` account ON costes.billing_account_id = account.billing_account_id__c ));
