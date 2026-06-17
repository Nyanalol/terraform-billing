-- mix_and_match -> salida BY_PROJECT / DESGLOSADAS (importes_lecturas_by_project, lecturas por proyecto)
--
-- VALIDADO contra Talend (ESPANA 202605): 399/399 filas exactas, diff 0/0.
--   26 cuentas, 374 proyectos, descuentos reales (2.66/3/3.5/7 %), multi-divisa.
--   Esta validacion ademas PROBO que el descuento se aplica con UN solo /100
--   (el "doble /100" del spec era una mala lectura del XML de Talend).
--
-- Rama by_project del job (tMap_5/tMap_13): cuentas con Desglosar_Facturas='SI', grano
-- (billing_account, project). Sin marketplace (la vista by_project no lo trae) y SIN soporte
-- (el soporte de las desglosadas es una linea aparte "Soporte tecnico", tMap_10 -> otro SQL).
-- descripcion = Descripci_n_del_producto__c del OLI. project_id vacio -> 'No project name'.
-- Filtro de salida: Importe > 0 (tFilterRow_3).
--
-- NOTA Espana: el dataset de consumo es el viejo (BILLING_CLOUD_PLATFORM); en paises nuevos
-- es billing_views. Ahora se lee de bq_group_project (materializado por get_data).
--
-- Parametros: {project}, {transformed_dataset}, {invoice_month} (YYYYMM)
CREATE OR REPLACE TABLE `{project}.{transformed_dataset}.project_new` AS
WITH params AS (
  SELECT PARSE_DATE('%Y%m', '{invoice_month}') AS month_start,
         DATE_ADD(PARSE_DATE('%Y%m', '{invoice_month}'), INTERVAL 1 MONTH) AS next_month_start
),
consumo AS (
  SELECT billing_account_id, project_id, currency,
    total_gcp,
    total_gmp,
    total_thirdparty,
    reseller_margin_gcp AS rmargin_gcp,
    reseller_margin_gmp AS rmargin_gmp
  FROM `{project}.{transformed_dataset}.bq_group_project`
  WHERE invoice_month = '{invoice_month}'
),
rates AS (
  SELECT base_currency, target_currency, exchange_rate
  FROM `{project}.{transformed_dataset}.currencies_exchange_rates`
),
opp AS (
  SELECT Id, billing_account_id__c, CurrencyIsoCode,
    IFNULL(SAFE_CAST(Margen_SWO__c AS FLOAT64), 0) / 100 AS swo,
    IFNULL(SAFE_CAST(Margen_de_partner_Descuento_GCP__c AS FLOAT64), 0) / 100 AS desc_gcp,
    IFNULL(SAFE_CAST(Margen_de_partner_Descuento_GMP__c AS FLOAT64), 0) / 100 AS desc_gmp
  FROM `{project}.{transformed_dataset}.stg_opportunities`
  WHERE Desglosar_Facturas__c = 'SI'
),
oli AS (
  SELECT OpportunityId, SAFE_CAST(SKU__c AS FLOAT64) AS sku, Descripci_n_del_producto__c AS descripcion
  FROM `{project}.{transformed_dataset}.stg_line_items`, params
  WHERE SAFE_CAST(SKU__c AS FLOAT64) IN (1417, 1409, 1410, 1731, 1730, 1902, 1910, 1729, 1252, 1251, 1911, 1207, 1418, 1419, 1420, 1421, 1422)
    AND (SAFE_CAST(Fecha_Inicio_Contrato_Opp__c AS DATE) IS NULL
         OR SAFE_CAST(Fecha_Inicio_Contrato_Opp__c AS DATE) < params.next_month_start)
    AND (SAFE_CAST(Fecha_Fin_Contrato_Opp__c AS DATE) IS NULL
         OR SAFE_CAST(Fecha_Fin_Contrato_Opp__c AS DATE) >= params.month_start)
),
base AS (
  SELECT c.billing_account_id,
    IF(c.project_id IS NULL OR TRIM(c.project_id) = '', 'No project name', c.project_id) AS project_id,
    o.Id AS opp_id, oli.sku, oli.descripcion, o.CurrencyIsoCode,
    IFNULL(r.exchange_rate, 1.0) AS rate,
    c.total_gcp AS b_gcp, c.total_gmp AS b_gmp, c.total_thirdparty AS b_tp,
    c.rmargin_gcp AS b_rmg_gcp, c.rmargin_gmp AS b_rmg_gmp,
    o.swo, o.desc_gcp, o.desc_gmp
  FROM oli
  JOIN opp o ON oli.OpportunityId = o.Id
  JOIN consumo c ON c.billing_account_id = o.billing_account_id__c
  LEFT JOIN rates r ON r.base_currency = UPPER(c.currency) AND r.target_currency = UPPER(o.CurrencyIsoCode)
),
calc AS (
  SELECT *,
    ROUND(b_gcp * rate, 6) AS gcp_ok, ROUND(b_gmp * rate, 6) AS gmp_ok, ROUND(b_tp * rate, 6) AS tp_ok,
    ((-b_rmg_gcp) - b_gcp * desc_gcp) * swo AS mg_gcp_swo,
    ((-b_rmg_gmp) - b_gmp * desc_gmp) * swo AS mg_gmp_swo
  FROM base
)
SELECT * FROM (
  SELECT billing_account_id, project_id, opp_id AS OpportunityId__c, sku AS SKU__c, descripcion,
    CurrencyIsoCode AS CurrencyIsoCode__c, ROUND(rate, 6) AS cambio_aplicado,
    IF(sku IN (1420, 1422), 0, ROUND(b_gcp, 6)) AS Total_gcp,
    IF(sku IN (1419, 1421), 0, ROUND(b_gmp, 6)) AS Total_gmp,
    CASE WHEN sku IN (1419, 1421) THEN ROUND(gcp_ok * (1 - desc_gcp) + tp_ok - mg_gcp_swo, 6)
         WHEN sku IN (1420, 1422) THEN ROUND(gmp_ok * (1 - desc_gmp) - mg_gmp_swo, 6)
         ELSE ROUND(gmp_ok * (1 - desc_gmp) + gcp_ok * (1 - desc_gcp) + tp_ok - mg_gmp_swo - mg_gcp_swo, 6) END AS Importe__c,
    '{invoice_month}' AS invoice_month,
    'by_project' AS source
  FROM calc
)
WHERE ROUND(Importe__c, 6) > 0;
