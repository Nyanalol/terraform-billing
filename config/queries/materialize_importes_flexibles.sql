-- mix_and_match -> salida FLEXIBLES (importes_lecturas_temp), 25 columnas COMPLETAS
--
-- VALIDADO contra Talend a FILA COMPLETA (25 columnas):
--   * FRANCIA (EUR) 202605: 8/8 byte a byte.  * HOLANDA (EUR): idem en columnas economicas.
--   * SUIZA (USD/CHF): 24/25 columnas exactas. Unica diferencia: las columnas *_euros de
--     reporting difieren ~0.4% (sub-centimo) en cuentas NO-EUR, porque la tabla de rates DERIVA
--     los cruces desde base EUR (CHF->EUR = 1/(EUR->CHF)) en vez de fetchear cada par directo
--     como Talend. DECISION (con Angel): se ACEPTA -> el Importe facturado es exacto; solo las
--     columnas informativas en euros llevan sub-centimo. Mantener la derivacion eficiente.
--   * ALEMANIA 16/18, UK 7/8: resto = deriva de datos de SF posterior al run (probado).
--
-- Logica (ver MIX_AND_MATCH_SPEC.md): consumo con GREATEST(cost+credits,0); marketplace via
-- googleInvoiceTypeOpp__c (minuscula); soporte (dia 23, % + minimo, sin fijo); descuentos /100
-- simple; split por SKU (GCP 1419/1421, GMP 1420/1422); Importe por SKU; Margen_total pre-split.
-- Columnas *_euros = valor en divisa de cuenta * rate(divisa->EUR). invoce_date = primer dia del mes
-- (DD-MM-YYYY). project_id/descripcion vacios en flexibles.
--
-- Parametros: {project}, {transformed_dataset}, {invoice_month} (YYYYMM)
CREATE OR REPLACE TABLE `{project}.{transformed_dataset}.flex_new` AS
WITH params AS (
  SELECT PARSE_DATE('%Y%m', '{invoice_month}') AS month_start,
         DATE_ADD(PARSE_DATE('%Y%m', '{invoice_month}'), INTERVAL 1 MONTH) AS next_month_start,
         DATE_ADD(PARSE_DATE('%Y%m', '{invoice_month}'), INTERVAL 22 DAY) AS support_cutoff
),
consumo AS (
  SELECT billing_account_id, currency,
    total_gcp,
    total_gmp,
    total_thirdparty,
    total_customer_cost_thirdparty_marketplace AS total_mkt,
    reseller_margin_gcp AS rmargin_gcp, reseller_margin_gmp AS rmargin_gmp,
    IFNULL(reseller_margin_thirdparty_marketplace,0) AS rmargin_mkt
  FROM `{project}.{transformed_dataset}.bq_group_billing` WHERE invoice_month='{invoice_month}'
),
rates AS (
  SELECT base_currency, target_currency, exchange_rate
  FROM `{project}.{transformed_dataset}.currencies_exchange_rates`
),
opp AS (
  SELECT Id, billing_account_id__c, CurrencyIsoCode, Billing_Model__c,
    IFNULL(googleInvoiceTypeOpp__c,'')='MARKETPLACE' AS is_mkt,
    IFNULL(SAFE_CAST(Margen_SWO__c AS FLOAT64),0)/100 AS swo,
    IFNULL(SAFE_CAST(Margen_de_partner_Descuento_GCP__c AS FLOAT64),0)/100 AS desc_gcp,
    IFNULL(SAFE_CAST(Margen_de_partner_Descuento_GMP__c AS FLOAT64),0)/100 AS desc_gmp,
    IFNULL(SAFE_CAST(Margen_de_partner_Descuento_Soporte__c AS FLOAT64),0)/100 AS desc_sop,
    IFNULL(SAFE_CAST(Margen_de_partner_Descuento_Soporte_Maps__c AS FLOAT64),0)/100 AS desc_sop_maps,
    IFNULL(SAFE_CAST(Margen_de_partner_Margen_Soporte__c AS FLOAT64),0)/100 AS m_sop,
    IFNULL(SAFE_CAST(Margen_de_partner_Margen_Soporte_Maps__c AS FLOAT64),0)/100 AS m_sop_maps,
    IFNULL(SAFE_CAST(Sop_Tec_Porcent__c AS FLOAT64),0)/100 AS sop_pct,
    IFNULL(SAFE_CAST(Sop_Tec_Maps_Porcent__c AS FLOAT64),0)/100 AS sop_maps_pct,
    IFNULL(SAFE_CAST(Sop_Tec_imp_minimo__c AS FLOAT64),0) AS sop_min,
    IFNULL(SAFE_CAST(Sop_Tec_Maps_imp_minimo__c AS FLOAT64),0) AS sop_maps_min
  FROM `{project}.{transformed_dataset}.stg_opportunities`
),
oli AS (
  SELECT OpportunityId, SAFE_CAST(SKU__c AS FLOAT64) AS sku, Dominio__c,
    SAFE_CAST(Fecha_Inicio_Contrato_Opp__c AS DATE) AS f_ini
  FROM `{project}.{transformed_dataset}.stg_line_items`, params
  WHERE SAFE_CAST(SKU__c AS FLOAT64) IN (1417,1409,1410,1731,1730,1902,1910,1729,1252,1251,1911,1207,1418,1419,1420,1421,1422)
    AND (SAFE_CAST(Fecha_Inicio_Contrato_Opp__c AS DATE) IS NULL OR SAFE_CAST(Fecha_Inicio_Contrato_Opp__c AS DATE) < params.next_month_start)
    AND (SAFE_CAST(Fecha_Fin_Contrato_Opp__c AS DATE) IS NULL OR SAFE_CAST(Fecha_Fin_Contrato_Opp__c AS DATE) >= params.month_start)
),
base AS (
  -- billing_account_id desde la OPP (no del consumo): asi sobreviven las cuentas con minimo de
  -- soporte y CERO consumo (no estan en sum_costs). LEFT JOIN + coalesce de los totales a 0.
  SELECT o.billing_account_id__c AS billing_account_id, o.Id AS opp_id, oli.sku, oli.Dominio__c, o.CurrencyIsoCode,
    oli.sku IN (1419,1421) AS is_gcp, oli.sku IN (1420,1422) AS is_gmp,
    IFNULL(r.exchange_rate,1.0) AS rate, IFNULL(re.exchange_rate,1.0) AS rate_eur, IFNULL(rea.exchange_rate,1.0) AS rate_eur_acc,
    IF(o.is_mkt, IFNULL(c.total_mkt,0), IFNULL(c.total_gcp,0)) AS b_gcp, IF(o.is_mkt, 0, IFNULL(c.total_gmp,0)) AS b_gmp,
    IF(o.is_mkt, 0, IFNULL(c.total_thirdparty,0)) AS b_tp,
    IF(o.is_mkt, IFNULL(c.rmargin_mkt,0), IFNULL(c.rmargin_gcp,0)) AS b_rmg_gcp, IF(o.is_mkt, 0, IFNULL(c.rmargin_gmp,0)) AS b_rmg_gmp,
    o.swo, o.desc_gcp, o.desc_gmp, o.desc_sop, o.desc_sop_maps, o.m_sop, o.m_sop_maps,
    o.sop_pct, o.sop_maps_pct, o.sop_min, o.sop_maps_min,
    (oli.f_ini IS NOT NULL AND oli.f_ini <= params.support_cutoff) AS apply_support
  FROM oli CROSS JOIN params
  JOIN opp o ON oli.OpportunityId=o.Id LEFT JOIN consumo c ON c.billing_account_id=o.billing_account_id__c
  LEFT JOIN rates r ON r.base_currency=UPPER(c.currency) AND r.target_currency=UPPER(o.CurrencyIsoCode)
  LEFT JOIN rates re ON re.base_currency=UPPER(c.currency) AND re.target_currency='EUR'
  LEFT JOIN rates rea ON rea.base_currency=UPPER(o.CurrencyIsoCode) AND rea.target_currency='EUR'
  WHERE o.Billing_Model__c='Flexible'
),
calc AS (
  SELECT *,
    ROUND(b_gcp*rate,6) AS gcp_ok, ROUND(b_gmp*rate,6) AS gmp_ok, ROUND(b_tp*rate,6) AS tp_ok,
    IF(apply_support, GREATEST(ROUND(b_gcp*rate,6)*sop_pct, sop_min), 0) AS sup,
    IF(apply_support, GREATEST(ROUND(b_gmp*rate,6)*sop_maps_pct, sop_maps_min), 0) AS sup_maps,
    ((-b_rmg_gcp) - b_gcp*desc_gcp)*(1-swo) AS mg_gcp_e, ((-b_rmg_gmp) - b_gmp*desc_gmp)*(1-swo) AS mg_gmp_e,
    ((-b_rmg_gcp) - b_gcp*desc_gcp)*swo AS mg_gcp_swo, ((-b_rmg_gmp) - b_gmp*desc_gmp)*swo AS mg_gmp_swo
  FROM base
),
calc2 AS (
  SELECT *, ROUND(sup*(1-desc_sop) + sup_maps*(1-desc_sop_maps) + gmp_ok*(1-desc_gmp) + gcp_ok*(1-desc_gcp) + tp_ok - mg_gmp_swo - mg_gcp_swo, 6) AS importe_full FROM calc
)
SELECT * FROM (
  SELECT billing_account_id, Dominio__c, opp_id AS OpportunityId__c, CAST(sku AS STRING) AS SKU__c, CurrencyIsoCode AS CurrencyIsoCode__c,
    CAST(IF(is_gmp, 0, ROUND(sup,6)) AS STRING) AS TotalSupport,
    CAST(ROUND(CASE WHEN importe_full>0 THEN (sup*(1-desc_sop)/rate + mg_gcp_e + mg_gmp_e)*100/(importe_full/rate) ELSE 0 END,6) AS STRING) AS Margen__c,
    CAST(IF(is_gmp, 0, ROUND(b_gcp,6)) AS STRING) AS Total_gcp,
    CAST(IF(is_gmp, 0, ROUND(mg_gcp_e,6)) AS STRING) AS Magen_gcp,
    CAST(IF(is_gcp, 0, ROUND(b_gmp,6)) AS STRING) AS Total_gmp,
    CAST(IF(is_gcp, 0, ROUND(mg_gmp_e,6)) AS STRING) AS Margen_gmp,
    CAST(ROUND(CASE WHEN importe_full>0 THEN (sup*(1-desc_sop)/rate + mg_gcp_e + mg_gmp_e)*100/(importe_full/rate) ELSE 0 END,6) AS STRING) AS Margen_total,
    CAST(ROUND(IF(is_gmp,0,b_gcp) + IF(is_gcp,0,b_gmp) + IF(is_gmp,0,b_tp) + IF(is_gcp,0,b_rmg_gmp) + IF(is_gmp,0,b_rmg_gcp),6) AS STRING) AS Cargo_Google__c,
    CAST(CASE WHEN is_gcp THEN ROUND(sup*(1-desc_sop) + gcp_ok*(1-desc_gcp) + tp_ok - mg_gcp_swo, 6)
         WHEN is_gmp THEN ROUND(sup_maps*(1-desc_sop_maps) + gmp_ok*(1-desc_gmp) - mg_gmp_swo, 6)
         ELSE importe_full END AS STRING) AS Importe__c,
    '{invoice_month}' AS invoice_month,
    FORMAT_DATE('%d-%m-%Y', (SELECT month_start FROM params)) AS invoce_date,
    CAST(ROUND(rate,6) AS STRING) AS cambio_aplicado, '' AS project_id, '' AS descripcion,
    CAST(IF(is_gmp, 0, mg_gcp_e*rate_eur) AS STRING) AS Margen_gcp_euros,
    CAST(IF(is_gcp, 0, mg_gmp_e*rate_eur) AS STRING) AS Margen_gmp_euros,
    CAST(IF(is_gmp, 0, sup*m_sop*rate_eur_acc) AS STRING) AS Margen_soporte_euros,
    CAST(IF(is_gcp, 0, sup_maps*m_sop_maps*rate_eur_acc) AS STRING) AS Margen_soporte_maps_euros,
    CAST(ROUND(mg_gcp_swo + mg_gmp_swo,6) AS STRING) AS Margen_SWO,
    CAST(IF(is_gmp, 0, ROUND(b_tp,6)) AS STRING) AS Total_thirdparty
  FROM calc2
  WHERE ROUND(CASE WHEN is_gcp THEN sup*(1-desc_sop) + gcp_ok*(1-desc_gcp) + tp_ok - mg_gcp_swo
       WHEN is_gmp THEN sup_maps*(1-desc_sop_maps) + gmp_ok*(1-desc_gmp) - mg_gmp_swo
       ELSE importe_full END, 6) <> 0
);
