CREATE VIEW `ip-billing-prod.consolidado_src.consumos_por_account`
AS SELECT *, total_gcp_gmp + reseller_margin_gmp + reseller_margin_gcp + reseller_margin_thirdparty_marketplace AS total_net_cost,
  (total_gcp+total_gmp)-importe_margen AS old_importe_factura_google
FROM ( SELECT
    billing_account_id, billing_model, cost_gcp, cost_gmp, credits_gcp, credits_gmp, cuenta, dominio,
    total_gcp, total_gmp, total_thirdparty, total_base_thirdparty, total_thirdparty_marketplace,
    account, reseller_margin_gmp, reseller_margin_gcp, reseller_margin_thirdparty_marketplace, invoice_month, cargo_google,
    CAST(ROUND(total_gcp+total_gmp+total_thirdparty+total_thirdparty_marketplace,2) AS NUMERIC) AS total_gcp_gmp,
    (total_gmp*0.2)+(total_gcp*0.1) AS importe_margen
  FROM `ip-billing-prod.billing_views.consumos_por_account` );
