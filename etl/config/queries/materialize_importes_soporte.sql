-- mix_and_match -> lineas de "Soporte tecnico" del by_project (tMap_10/tMap_11 de Talend)
--
-- Logica (rama project, cuentas Desglosar='SI', agregado por cuenta+opp+SKU):
--   1. tMap_13 hace SPLIT POR SKU: anula consumos Y parametros de soporte segun SKU type.
--      - GCP (1419/1421): pct, fijo, p_sop, margen_ip_soporte activos; minimo=0(!);
--                          pct_m=0, min_m=0, p_sop_m=0, margen_ip_soporte_maps=0.
--                          fijo_m NO se anula (pass-through en tMap_13).
--      - GMP (1420/1422): pct=0, fijo=0, p_sop=0, margen_ip_soporte=0;
--                          minimo=maps_minimo (soporte_tecnico_minimo remapeado!);
--                          pct_m, fijo_m, min_m, p_sop_m, margen_ip_soporte_maps activos.
--   2. tFilterRow_3: Importe_factura > 0 AND OpportunityId != null.
--   3. tAggregateRow: GROUP BY (billing_account, opp, SKU), SUM consumos.
--   4. tMap_10 calcula soporte sobre datos AGREGADOS:
--      - sup_gcp  = ApplySupport ? GREATEST((gcp+tp)*pct + fijo, minimo) : 0
--      - sup_maps = ApplySupport ? GREATEST(gmp*pct_m + fijo_m, min_m) : 0
--      - Importe  = ROUND(sup_gcp*p_sop, 2) + ROUND(sup_maps*p_sop_m, 2)
--      - TotalSupport = sup_gcp (output directo, SIN extra GREATEST)
--      - MargenTotal  = ROUND(Importe>0 ? sup_gcp*p_sop*100/Importe : 0, 2)
--      - Margen_soporte_euros = ROUND(sup_gcp * p_sop, 2) * rate_eur
--      - Margen_soporte_maps_euros = ROUND(sup_maps * p_sop_m, 2) * rate_eur
--   5. Filtro "raro" (spec decision 5): de SKU GCP solo pasa 1421 (descarta 1419).
--   6. SKU output: si no es 1419/1420/1421/1422 → default 1410.
--   7. descripcion = 'Soporte tecnico', project_id = ''.
--   8. Columnas zero: Total_gcp, Magen_gcp, Total_gmp, Margen_gmp, Cargo_Google__c,
--      Margen_gmp_euros, Margen_gcp_euros, Margen_SWO, Total_thirdparty.
--
-- Schema de salida (26 cols, misma que by_project): billing_account_id, Dominio__c,
--   OpportunityId__c, SKU__c, CurrencyIsoCode__c, TotalSupport, Margen__c, Total_gcp,
--   Magen_gcp, Total_gmp, Margen_gmp, Margen_total, Cargo_Google__c, Importe__c,
--   invoice_month, invoce_date, cambio_aplicado, project_id, descripcion, Margen_gmp_euros,
--   Margen_gcp_euros, Margen_soporte_euros, Margen_soporte_maps_euros, Margen_SWO,
--   Total_thirdparty, source
--
-- Parametros: {project}, {transformed_dataset}, {invoice_month}
CREATE OR REPLACE TABLE `{project}.{transformed_dataset}.soporte_new` AS
WITH params AS (
  SELECT PARSE_DATE('%Y%m', '{invoice_month}') AS month_start,
         DATE_ADD(PARSE_DATE('%Y%m', '{invoice_month}'), INTERVAL 1 MONTH) AS next_month_start,
         DATE_ADD(PARSE_DATE('%Y%m', '{invoice_month}'), INTERVAL 22 DAY) AS support_cutoff
),
consumo_acc AS (
  SELECT billing_account_id,
    ANY_VALUE(currency) AS currency,
    SUM(total_gcp) AS total_gcp,
    SUM(total_gmp) AS total_gmp,
    SUM(total_thirdparty) AS total_tp
  FROM `{project}.{transformed_dataset}.bq_group_project`
  WHERE invoice_month = '{invoice_month}'
  GROUP BY 1
),
rates AS (
  SELECT base_currency, target_currency, exchange_rate
  FROM `{project}.{transformed_dataset}.currencies_exchange_rates`
),
opp AS (
  SELECT Id, billing_account_id__c, billing_account_desc__c, CurrencyIsoCode,
    IFNULL(SAFE_CAST(Sop_Tec_Porcent__c AS FLOAT64), 0) / 100 AS pct,
    IFNULL(SAFE_CAST(Sop_Tec_imp_minimo__c AS FLOAT64), 0) AS minimo,
    IFNULL(SAFE_CAST(Sop_Tec_imp_fijo__c AS FLOAT64), 0) AS fijo,
    IFNULL(SAFE_CAST(Sop_Tec_Maps_Porcent__c AS FLOAT64), 0) / 100 AS pct_m,
    IFNULL(SAFE_CAST(Sop_Tec_Maps_imp_minimo__c AS FLOAT64), 0) AS min_m,
    IFNULL(SAFE_CAST(Sop_Tec_Maps_Importe_Fijo__c AS FLOAT64), 0) AS fijo_m,
    IFNULL(SAFE_CAST(Margen_de_partner_Margen_Soporte__c AS FLOAT64), 0) / 100 AS p_sop,
    IFNULL(SAFE_CAST(Margen_de_partner_Margen_Soporte_Maps__c AS FLOAT64), 0) / 100 AS p_sop_m
  FROM `{project}.{transformed_dataset}.stg_opportunities`
  WHERE Desglosar_Facturas__c = 'SI'
),
oli AS (
  SELECT DISTINCT OpportunityId, SAFE_CAST(SKU__c AS FLOAT64) AS sku,
    SAFE_CAST(Fecha_Inicio_Contrato_Opp__c AS DATE) AS f_ini
  FROM `{project}.{transformed_dataset}.stg_line_items`, params
  WHERE (SAFE_CAST(Fecha_Inicio_Contrato_Opp__c AS DATE) IS NULL
         OR SAFE_CAST(Fecha_Inicio_Contrato_Opp__c AS DATE) < params.next_month_start)
    AND (SAFE_CAST(Fecha_Fin_Contrato_Opp__c AS DATE) IS NULL
         OR SAFE_CAST(Fecha_Fin_Contrato_Opp__c AS DATE) >= params.month_start)
),
-- Replicate tMap_13 SKU split: zero/remap parameters by SKU type
calc AS (
  SELECT c.billing_account_id, o.Id AS opp_id, o.billing_account_desc__c AS Dominio__c,
    oli.sku, o.CurrencyIsoCode,
    -- Consumption split (same as before)
    IF(oli.sku IN (1420, 1422), 0, c.total_gcp) AS gcp,
    IF(oli.sku IN (1420, 1422), 0, c.total_tp) AS tp,
    IF(oli.sku IN (1419, 1421), 0, c.total_gmp) AS gmp,
    -- GCP support params (zeroed for GMP SKUs)
    IF(oli.sku IN (1420, 1422), 0, o.pct) AS pct,
    IF(oli.sku IN (1420, 1422), 0, o.fijo) AS fijo,
    -- soporte_tecnico_minimo: GCP→0, GMP→maps_minimo (tMap_13 remap!)
    CASE WHEN oli.sku IN (1419, 1421) THEN 0
         WHEN oli.sku IN (1420, 1422) THEN o.min_m
         ELSE o.minimo END AS minimo,
    -- Maps support params (zeroed for GCP SKUs, EXCEPT fijo_m = pass-through!)
    IF(oli.sku IN (1419, 1421), 0, o.pct_m) AS pct_m,
    o.fijo_m,  -- NOT zeroed in tMap_13 (pass-through for all SKUs)
    IF(oli.sku IN (1419, 1421), 0, o.min_m) AS min_m,
    -- Margin percentages (zeroed cross-SKU)
    IF(oli.sku IN (1420, 1422), 0, o.p_sop) AS p_sop,
    IF(oli.sku IN (1419, 1421), 0, o.p_sop_m) AS p_sop_m,
    -- ApplySupport
    (oli.f_ini IS NOT NULL AND oli.f_ini <= params.support_cutoff) AS apply_support,
    -- Rates
    IFNULL(r.exchange_rate, 1.0) AS rate,
    IF(UPPER(c.currency) = 'EUR', 1.0, IFNULL(re.exchange_rate, 1.0)) AS rate_eur
  FROM oli
  CROSS JOIN params
  JOIN opp o ON oli.OpportunityId = o.Id
  JOIN consumo_acc c ON c.billing_account_id = o.billing_account_id__c
  LEFT JOIN rates r ON r.base_currency = UPPER(c.currency) AND r.target_currency = UPPER(o.CurrencyIsoCode)
  LEFT JOIN rates re ON re.base_currency = UPPER(c.currency) AND re.target_currency = 'EUR'
  WHERE (oli.sku NOT IN (1419, 1421)) OR oli.sku = 1421
),
sup AS (
  SELECT *,
    IF(apply_support, GREATEST((gcp + tp) * pct + fijo, minimo), 0) AS sup_gcp,
    IF(apply_support, GREATEST(gmp * pct_m + fijo_m, min_m), 0) AS sup_maps
  FROM calc
),
final AS (
  SELECT *,
    ROUND(sup_gcp, 2) AS total_sup,
    ROUND(ROUND(sup_gcp * p_sop, 2) + ROUND(sup_maps * p_sop_m, 2), 2) AS importe
  FROM sup
)
SELECT billing_account_id,
  Dominio__c,
  opp_id AS OpportunityId__c,
  CAST(IF(sku IN (1419, 1420, 1421, 1422), sku, 1410) AS STRING) AS SKU__c,
  CurrencyIsoCode AS CurrencyIsoCode__c,
  CAST(total_sup AS STRING) AS TotalSupport,
  CAST(ROUND(IF(importe > 0, sup_gcp * p_sop * 100 / importe, 0), 2) AS STRING) AS Margen__c,
  CAST(0 AS STRING) AS Total_gcp,
  CAST(0 AS STRING) AS Magen_gcp,
  CAST(0 AS STRING) AS Total_gmp,
  CAST(0 AS STRING) AS Margen_gmp,
  CAST(ROUND(IF(importe > 0, sup_gcp * p_sop * 100 / importe, 0), 2) AS STRING) AS Margen_total,
  CAST(0 AS STRING) AS Cargo_Google__c,
  CAST(importe AS STRING) AS Importe__c,
  '{invoice_month}' AS invoice_month,
  FORMAT_DATE('%d-%m-%Y', (SELECT month_start FROM params)) AS invoce_date,
  CAST(ROUND(rate, 6) AS STRING) AS cambio_aplicado,
  '' AS project_id,
  'Soporte técnico' AS descripcion,
  CAST(0 AS STRING) AS Margen_gmp_euros,
  CAST(0 AS STRING) AS Margen_gcp_euros,
  CAST(ROUND(total_sup * p_sop, 2) * rate_eur AS STRING) AS Margen_soporte_euros,
  CAST(ROUND(sup_maps * p_sop_m, 2) * rate_eur AS STRING) AS Margen_soporte_maps_euros,
  CAST(0 AS STRING) AS Margen_SWO,
  CAST(0 AS STRING) AS Total_thirdparty,
  'soporte' AS source
FROM final
WHERE importe > 0;
