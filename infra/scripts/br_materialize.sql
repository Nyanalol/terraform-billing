-- Materializa las 7 vistas estandar + workspace de Brasil (billing_views, southamerica-east1)
-- a tablas en consolidado_src (ventana 3 meses) para la copia cross-region al consolidado EU.
-- Lo ejecuta una scheduled query diaria. NO toca billing_views (solo lee).

CREATE OR REPLACE TABLE `ipdb-billing-interno.consolidado_src.consumos_por_account` AS
SELECT *, total_gcp_gmp + reseller_margin_gmp + reseller_margin_gcp + reseller_margin_thirdparty_marketplace AS total_net_cost,
  (total_gcp+total_gmp)-importe_margen AS old_importe_factura_google
FROM ( SELECT *, (total_gcp*0.9+total_gmp*0.8) AS cargo_google,
    CAST(ROUND(total_gcp+total_gmp+total_thirdparty+total_thirdparty_marketplace,2) AS NUMERIC) AS total_gcp_gmp,
    (total_gmp*0.2)+(total_gcp*0.1) AS importe_margen
  FROM ( SELECT costes.billing_account_id, account.Billing_Model__c AS billing_model,
      CAST(cost_gcp AS NUMERIC) cost_gcp, CAST(cost_gmp AS NUMERIC) cost_gmp, CAST(credits_gcp AS NUMERIC) credits_gcp, CAST(credits_gmp AS NUMERIC) credits_gmp,
      account.billing_account_desc__c AS cuenta, account.billing_account_desc__c AS dominio,
      CAST(cost_gcp+credits_gcp AS NUMERIC) AS total_gcp, CAST(cost_gmp+credits_gmp AS NUMERIC) AS total_gmp,
      CAST(cost_thirdparty+credits_thirdparty AS NUMERIC) AS total_thirdparty,
      CAST(cost_base_thirdparty+credits_thirdparty AS NUMERIC) AS total_base_thirdparty,
      CAST(cost_thirdparty_marketplace+credits_thirdparty_marketplace AS NUMERIC) AS total_thirdparty_marketplace,
      costes.account, CAST(reseller_margin_gmp AS NUMERIC) reseller_margin_gmp, CAST(reseller_margin_gcp AS NUMERIC) reseller_margin_gcp,
      CAST(0 AS NUMERIC) AS reseller_margin_thirdparty_marketplace, costes.invoice_month
    FROM `ipdb-billing-interno.billing_views.sum_costs_credits_per_month` costes
    LEFT JOIN `ipdb-billing-interno.billing_views.billing_accounts` account ON costes.billing_account_id = account.billing_account_id__c
    WHERE costes.invoice_month >= FORMAT_DATE('%Y%m', DATE_SUB(DATE_TRUNC(CURRENT_DATE(),MONTH), INTERVAL 2 MONTH)) ));

CREATE OR REPLACE TABLE `ipdb-billing-interno.consolidado_src.consumos_por_proyecto_new` AS
SELECT * FROM `ipdb-billing-interno.billing_views.consumos_por_proyecto_new`
WHERE invoice_month >= FORMAT_DATE('%Y%m', DATE_SUB(DATE_TRUNC(CURRENT_DATE(),MONTH), INTERVAL 2 MONTH));

CREATE OR REPLACE TABLE `ipdb-billing-interno.consolidado_src.consumos_support_flex` AS
SELECT * FROM `ipdb-billing-interno.billing_views.consumos_support_plex`
WHERE invoice_month >= FORMAT_DATE('%Y%m', DATE_SUB(DATE_TRUNC(CURRENT_DATE(),MONTH), INTERVAL 2 MONTH));

CREATE OR REPLACE TABLE `ipdb-billing-interno.consolidado_src.gcp_billing_adjustment` AS
SELECT * FROM `ipdb-billing-interno.billing_views.gcp_billing_adjustments`
WHERE invoice_month >= FORMAT_DATE('%Y%m', DATE_SUB(DATE_TRUNC(CURRENT_DATE(),MONTH), INTERVAL 2 MONTH));

CREATE OR REPLACE TABLE `ipdb-billing-interno.consolidado_src.consumos_google_reseller_factura` AS
SELECT invoice_month, account,
  CAST(consumo AS NUMERIC) consumo, CAST(cost AS NUMERIC) cost, CAST(all_creditos AS NUMERIC) all_creditos,
  CAST(creditos AS NUMERIC) creditos, CAST(creditos_reseller AS NUMERIC) creditos_reseller,
  CAST(descuento_reseller_old AS NUMERIC) descuento_reseller_old, CAST(descuento_reseller_new AS NUMERIC) descuento_reseller_new,
  CAST(descuento_reseller AS NUMERIC) descuento_reseller
FROM `ipdb-billing-interno.billing_views.consumos_google_reseller_factura`
WHERE invoice_month >= FORMAT_DATE('%Y%m', DATE_SUB(DATE_TRUNC(CURRENT_DATE(),MONTH), INTERVAL 2 MONTH));

CREATE OR REPLACE TABLE `ipdb-billing-interno.consolidado_src.importes_lecturas` AS
SELECT billing_account_id,Dominio,OpportunityId,SKU,Currency,TotalSupport_original,GCP_original,GMP_original,
  CAST(0 AS NUMERIC) AS ThirdParty_original,
  Importe_sin_soporte_original,Margen_GCP,Margen_GMP,Margen_total,TotalSupport_EUR,GCP_EUR,GMP_EUR,Importe_sin_soporte_EUR,
  Cargo_Google_original,Cargo_Google_EUR,Importe_original,Importe_EUR,invoice_month,invoice_date,cambio_aplicado,
  TotalSupport_str,GCP_original_str,GMP_original_str,Cargo_Google_str,Importe_str,billing_model,project_id,LecturasSoloSoporte
FROM `ipdb-billing-interno.billing_views.importes_lecturas`
WHERE invoice_month >= FORMAT_DATE('%Y%m', DATE_SUB(DATE_TRUNC(CURRENT_DATE(),MONTH), INTERVAL 2 MONTH));

CREATE OR REPLACE TABLE `ipdb-billing-interno.consolidado_src.vista_importes_lecturas` AS
SELECT billing_account_id,Dominio__c,OpportunityId__c,SKU__c,CurrencyIsoCode__c,TotalSupport,
  CAST(0 AS NUMERIC) AS Margen_soporte_euros, CAST(0 AS NUMERIC) AS Margen_soporte_maps_euros,
  Total_gcp,Margen_gcp,Total_gmp,Margen_gmp,Total_thirdparty,Margen_total,gcp_euros,gmp_euros,thirdparty_euros,
  Importe_GCP_Eur,Cargo_Google__c,Cargo_Google_Eur,Importe__c,Importe_Eur,invoice_month,invoice_date,cambio_aplicado,
  TotalSupport_str,Total_gcp_str,Total_gmp_str,Total_thirdparty_str,Cargo_Google_str,Importe_str,billing_model,project_id,LecturasSoloSoporte
FROM `ipdb-billing-interno.billing_views.vista_importes_lecturas`
WHERE invoice_month >= FORMAT_DATE('%Y%m', DATE_SUB(DATE_TRUNC(CURRENT_DATE(),MONTH), INTERVAL 2 MONTH));

CREATE OR REPLACE TABLE `ipdb-billing-interno.consolidado_src.importes_lecturas_workspace` AS
SELECT * FROM `ipdb-billing-interno.billing_views.importes_lecturas_workspace`
WHERE CONCAT(Anyo__c,Mes__c) >= FORMAT_DATE('%Y%m', DATE_SUB(DATE_TRUNC(CURRENT_DATE(),MONTH), INTERVAL 2 MONTH));
