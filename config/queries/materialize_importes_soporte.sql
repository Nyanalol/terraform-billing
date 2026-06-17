-- mix_and_match -> lineas de "Soporte tecnico" del by_project (tMap_10 de Talend)
--
-- VALIDADO contra Talend (ESPANA 202605): 4/4 filas exactas. Las 3 filas "extra" que produce
-- corresponden a oportunidades facturadas el 4-jun (SF incremento Ultimo_periodo_facturado__c
-- a las 13:18, un dia DESPUES del snapshot BQ del 3-jun) -> el motor coincide con lo realmente
-- facturado en Salesforce; la tabla BQ es el snapshot desfasado.
--
-- Logica (rama project, cuentas Desglosar='SI', agregado por cuenta+opp+SKU):
--   - sup_gcp  = ApplySupport ? GREATEST((gcp+thirdparty)*Sop_Tec_Porcent/100 + fijo, minimo) : 0
--   - sup_maps = ApplySupport ? GREATEST(gmp*Sop_Tec_Maps_Porcent/100 + fijo_maps, min_maps) : 0
--   - Importe  = ROUND(sup_gcp*Margen_Soporte/100, 2) + ROUND(sup_maps*Margen_Soporte_Maps/100, 2)
--   - Split por SKU ANTES de calcular: SKU GMP 1420/1422 anula gcp/tp; SKU GCP 1419/1421 anula gmp.
--   - Filtro "raro" (intencional, decision 5 del spec): de los SKU GCP solo pasa el 1421 (descarta 1419).
--   - Columna TotalSupport = GREATEST(sup_gcp, COALESCE(minimo, min_maps, 0)) -- replica un alias
--     del tAggregateRow de Talend (empirico: cuadra los 4 casos, incluido el min Maps en cuentas Maps).
--   - descripcion = 'Soporte tecnico', project_id = ''. ROUND 2 (tMap_10, distinto del motor ROUND 6).
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
    SUM(total_gcp) AS total_gcp,
    SUM(total_gmp) AS total_gmp,
    SUM(total_thirdparty) AS total_tp
  FROM `{project}.{transformed_dataset}.bq_group_project`
  WHERE invoice_month = '{invoice_month}'
  GROUP BY 1
),
opp AS (
  SELECT Id, billing_account_id__c, CurrencyIsoCode,
    IFNULL(SAFE_CAST(Sop_Tec_Porcent__c AS FLOAT64), 0) / 100 AS pct,
    IFNULL(SAFE_CAST(Sop_Tec_imp_minimo__c AS FLOAT64), 0) AS minimo,
    IFNULL(SAFE_CAST(Sop_Tec_imp_fijo__c AS FLOAT64), 0) AS fijo,
    IFNULL(SAFE_CAST(Sop_Tec_Maps_Porcent__c AS FLOAT64), 0) / 100 AS pct_m,
    IFNULL(SAFE_CAST(Sop_Tec_Maps_imp_minimo__c AS FLOAT64), 0) AS min_m,
    IFNULL(SAFE_CAST(Sop_Tec_Maps_Importe_Fijo__c AS FLOAT64), 0) AS fijo_m,
    COALESCE(SAFE_CAST(Sop_Tec_imp_minimo__c AS FLOAT64), SAFE_CAST(Sop_Tec_Maps_imp_minimo__c AS FLOAT64), 0) AS min_eff,
    IFNULL(SAFE_CAST(Margen_de_partner_Margen_Soporte__c AS FLOAT64), 0) / 100 AS p_sop,
    IFNULL(SAFE_CAST(Margen_de_partner_Margen_Soporte_Maps__c AS FLOAT64), 0) / 100 AS p_sop_m
  FROM `{project}.{transformed_dataset}.stg_opportunities`
  WHERE Desglosar_Facturas__c = 'SI'
),
oli AS (
  SELECT DISTINCT OpportunityId, SAFE_CAST(SKU__c AS FLOAT64) AS sku,
    SAFE_CAST(Fecha_Inicio_Contrato_Opp__c AS DATE) AS f_ini
  FROM `{project}.{transformed_dataset}.stg_line_items`, params
  WHERE SAFE_CAST(SKU__c AS FLOAT64) IN (1417, 1409, 1410, 1731, 1730, 1902, 1910, 1729, 1252, 1251, 1911, 1207, 1418, 1419, 1420, 1421, 1422)
    AND (SAFE_CAST(Fecha_Inicio_Contrato_Opp__c AS DATE) IS NULL
         OR SAFE_CAST(Fecha_Inicio_Contrato_Opp__c AS DATE) < params.next_month_start)
    AND (SAFE_CAST(Fecha_Fin_Contrato_Opp__c AS DATE) IS NULL
         OR SAFE_CAST(Fecha_Fin_Contrato_Opp__c AS DATE) >= params.month_start)
),
calc AS (
  SELECT c.billing_account_id, o.Id AS opp_id, oli.sku, o.CurrencyIsoCode,
    IF(oli.sku IN (1420, 1422), 0, c.total_gcp) AS gcp,
    IF(oli.sku IN (1420, 1422), 0, c.total_tp) AS tp,
    IF(oli.sku IN (1419, 1421), 0, c.total_gmp) AS gmp,
    o.pct, o.minimo, o.fijo, o.pct_m, o.min_m, o.fijo_m, o.min_eff, o.p_sop, o.p_sop_m,
    (oli.f_ini IS NOT NULL AND oli.f_ini <= params.support_cutoff) AS apply_support
  FROM oli
  CROSS JOIN params
  JOIN opp o ON oli.OpportunityId = o.Id
  JOIN consumo_acc c ON c.billing_account_id = o.billing_account_id__c
  WHERE (oli.sku NOT IN (1419, 1421)) OR oli.sku = 1421
),
sup AS (
  SELECT *,
    IF(apply_support, GREATEST((gcp + tp) * pct + fijo, minimo), 0) AS sup_gcp,
    IF(apply_support, GREATEST(gmp * pct_m + fijo_m, min_m), 0) AS sup_maps
  FROM calc
)
SELECT billing_account_id, opp_id AS OpportunityId__c, sku AS SKU__c,
  CurrencyIsoCode AS CurrencyIsoCode__c,
  ROUND(GREATEST(sup_gcp, min_eff), 2) AS TotalSupport,
  ROUND(ROUND(sup_gcp * p_sop, 2) + ROUND(sup_maps * p_sop_m, 2), 2) AS Importe__c,
  'Soporte técnico' AS descripcion,
  '' AS project_id,
  '{invoice_month}' AS invoice_month,
  'soporte' AS source
FROM sup
WHERE ROUND(ROUND(sup_gcp * p_sop, 2) + ROUND(sup_maps * p_sop_m, 2), 2) > 0;
