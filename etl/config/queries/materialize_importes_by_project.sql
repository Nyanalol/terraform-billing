-- mix_and_match -> salida BY_PROJECT / DESGLOSADAS (importes_lecturas_by_project, lecturas por proyecto)
--
-- Rama by_project del job (tMap_5/tMap_13): cuentas con Desglosar_Facturas='SI', grano
-- (billing_account, project). Sin marketplace (la vista by_project no lo trae) y SIN soporte
-- (el soporte de las desglosadas es una linea aparte "Soporte tecnico", tMap_10 -> otro SQL).
-- Soporte=0, Margen_soporte_euros=0, Margen_soporte_maps_euros=0.
-- descripcion = Descripci_n_del_producto__c del OLI. project_id vacio -> 'No project name',
-- project_id vacio post-tMap_7 -> 'Google Adjustments'.
-- Filtro de salida: Importe > 0 (tFilterRow_3).
-- Dominio__c viene de billing_account_desc__c (Opportunity), igual que en flexibles.
--
-- Schema de salida Talend (tFileOutputDelimited_2 / tMap_7): 25 columnas:
--   billing_account_id, Dominio__c, OpportunityId__c, SKU__c, CurrencyIsoCode__c,
--   TotalSupport, Margen__c, Total_gcp, Magen_gcp, Total_gmp, Margen_gmp,
--   Margen_total, Cargo_Google__c, Importe__c, invoice_month, invoce_date,
--   cambio_aplicado, project_id, descripcion, Margen_gmp_euros, Margen_gcp_euros,
--   Margen_soporte_euros, Margen_soporte_maps_euros, Margen_SWO, Total_thirdparty
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
  FROM `{currencies_project}.{currencies_dataset}.{currencies_table}`
  WHERE billing_month = '{invoice_month}'
),
opp AS (
  SELECT Id, billing_account_id__c, billing_account_desc__c, CurrencyIsoCode,
    IFNULL(SAFE_CAST(Margen_SWO__c AS FLOAT64), 0) / 100 AS swo,
    IFNULL(SAFE_CAST(Margen_de_partner_Descuento_GCP__c AS FLOAT64), 0) / 100 AS desc_gcp,
    IFNULL(SAFE_CAST(Margen_de_partner_Descuento_GMP__c AS FLOAT64), 0) / 100 AS desc_gmp
  FROM `{project}.{transformed_dataset}.stg_opportunities`
  WHERE Desglosar_Facturas__c = 'SI'
    AND Margen_de_partner_Margen_GCP__c IS NOT NULL
    AND Margen_de_partner_Margen_GMP__c IS NOT NULL
),
oli AS (
  -- DISTINCT: stg_line_items puede traer OLIs duplicados (misma opp+SKU); sin esto, el JOIN
  -- multiplica las filas de salida -> Carga_de_lectura__c DUPLICADAS en SF (doble facturacion).
  SELECT DISTINCT OpportunityId, SAFE_CAST(SKU__c AS FLOAT64) AS sku,
    Descripci_n_del_producto__c AS descripcion
  FROM `{project}.{transformed_dataset}.stg_line_items`, params
  WHERE (SAFE_CAST(Fecha_Inicio_Contrato_Opp__c AS DATE) IS NULL
         OR SAFE_CAST(Fecha_Inicio_Contrato_Opp__c AS DATE) < params.next_month_start)
    AND (SAFE_CAST(Fecha_Fin_Contrato_Opp__c AS DATE) IS NULL
         OR SAFE_CAST(Fecha_Fin_Contrato_Opp__c AS DATE) >= params.month_start)
),
base AS (
  SELECT c.billing_account_id,
    IF(c.project_id IS NULL OR TRIM(c.project_id) = '', 'No project name', c.project_id) AS project_id,
    o.Id AS opp_id, oli.sku, o.billing_account_desc__c AS Dominio__c, oli.descripcion, o.CurrencyIsoCode,
    oli.sku IN (1419, 1421) AS is_gcp, oli.sku IN (1420, 1422) AS is_gmp,
    IFNULL(r.exchange_rate, 1.0) AS rate,
    IF(UPPER(c.currency) = 'EUR', 1.0, IFNULL(re.exchange_rate, 1.0)) AS rate_eur,
    c.total_gcp AS b_gcp, c.total_gmp AS b_gmp, c.total_thirdparty AS b_tp,
    c.rmargin_gcp AS b_rmg_gcp, c.rmargin_gmp AS b_rmg_gmp,
    o.swo, o.desc_gcp, o.desc_gmp
  FROM oli
  JOIN opp o ON oli.OpportunityId = o.Id
  JOIN consumo c ON c.billing_account_id = o.billing_account_id__c
  LEFT JOIN rates r ON r.base_currency = UPPER(c.currency) AND r.target_currency = UPPER(o.CurrencyIsoCode)
  LEFT JOIN rates re ON re.base_currency = UPPER(c.currency) AND re.target_currency = 'EUR'
),
calc AS (
  SELECT *,
    ROUND(b_gcp * rate, 6) AS gcp_ok, ROUND(b_gmp * rate, 6) AS gmp_ok, ROUND(b_tp * rate, 6) AS tp_ok,
    ((-b_rmg_gcp) - b_gcp * desc_gcp) * (1 - swo) AS mg_gcp_e,
    ((-b_rmg_gmp) - b_gmp * desc_gmp) * (1 - swo) AS mg_gmp_e,
    ((-b_rmg_gcp) - b_gcp * desc_gcp) * swo AS mg_gcp_swo,
    ((-b_rmg_gmp) - b_gmp * desc_gmp) * swo AS mg_gmp_swo
  FROM base
),
calc2 AS (
  SELECT *,
    ROUND(gmp_ok * (1 - desc_gmp) + gcp_ok * (1 - desc_gcp) + tp_ok - mg_gmp_swo - mg_gcp_swo, 6) AS importe_full
  FROM calc
)
SELECT * FROM (
  SELECT billing_account_id, Dominio__c, opp_id AS OpportunityId__c, CAST(sku AS STRING) AS SKU__c,
    CurrencyIsoCode AS CurrencyIsoCode__c,
    CAST(0 AS STRING) AS TotalSupport,
    CAST(ROUND(CASE WHEN importe_full > 0
      THEN (mg_gcp_e + mg_gmp_e) * 100 / (importe_full / rate)
      ELSE 0 END, 6) AS STRING) AS Margen__c,
    CAST(IF(is_gmp, 0, gcp_ok) AS STRING) AS Total_gcp,
    CAST(IF(is_gmp, 0, ROUND(ROUND(mg_gcp_e, 6) * rate, 6)) AS STRING) AS Magen_gcp,
    CAST(IF(is_gcp, 0, gmp_ok) AS STRING) AS Total_gmp,
    CAST(IF(is_gcp, 0, ROUND(ROUND(mg_gmp_e, 6) * rate, 6)) AS STRING) AS Margen_gmp,
    CAST(ROUND(CASE WHEN importe_full > 0
      THEN (mg_gcp_e + mg_gmp_e) * 100 / (importe_full / rate)
      ELSE 0 END, 6) AS STRING) AS Margen_total,
    CAST(CASE
      WHEN is_gcp THEN
        CASE WHEN ROUND(b_gcp + b_rmg_gcp + tp_ok, 6) < 0 AND ROUND(b_gcp + b_rmg_gcp + tp_ok, 6) > -0.001
          THEN 0 ELSE ROUND(b_gcp + b_rmg_gcp + tp_ok, 6) END
      WHEN is_gmp THEN
        CASE WHEN ROUND(b_gmp + b_rmg_gmp, 6) < 0 AND ROUND(b_gmp + b_rmg_gmp, 6) > -0.001
          THEN 0 ELSE ROUND(b_gmp + b_rmg_gmp, 6) END
      ELSE ROUND(b_gmp + b_gcp + b_tp + b_rmg_gmp + b_rmg_gcp, 6)
    END AS STRING) AS Cargo_Google__c,
    CAST(CASE WHEN is_gcp THEN ROUND(gcp_ok * (1 - desc_gcp) + tp_ok - mg_gcp_swo, 6)
         WHEN is_gmp THEN ROUND(gmp_ok * (1 - desc_gmp) - mg_gmp_swo, 6)
         ELSE importe_full END AS STRING) AS Importe__c,
    '{invoice_month}' AS invoice_month,
    FORMAT_DATE('%d-%m-%Y', (SELECT month_start FROM params)) AS invoce_date,
    CAST(ROUND(rate, 6) AS STRING) AS cambio_aplicado,
    IF(TRIM(project_id) = '', 'Google Adjustments', project_id) AS project_id,
    descripcion,
    CAST(IF(is_gcp, 0, ROUND(mg_gmp_e, 6) * rate_eur) AS STRING) AS Margen_gmp_euros,
    CAST(IF(is_gmp, 0, ROUND(mg_gcp_e, 6) * rate_eur) AS STRING) AS Margen_gcp_euros,
    CAST(0 AS STRING) AS Margen_soporte_euros,
    CAST(0 AS STRING) AS Margen_soporte_maps_euros,
    CAST(ROUND(mg_gcp_swo + mg_gmp_swo, 6) AS STRING) AS Margen_SWO,
    CAST(IF(is_gmp, 0, tp_ok) AS STRING) AS Total_thirdparty,
    'by_project' AS source
  FROM calc2
  WHERE ROUND(CASE WHEN is_gcp THEN gcp_ok * (1 - desc_gcp) + tp_ok - mg_gcp_swo
       WHEN is_gmp THEN gmp_ok * (1 - desc_gmp) - mg_gmp_swo
       ELSE importe_full END, 6) > 0
);
