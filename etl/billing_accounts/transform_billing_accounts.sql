-- Construye billing_accounts desde las tablas staging de Salesforce.
-- Sustituye la TRANSFORMACION del job de Talend `diary_get_billing_accounts`
-- (tMap_1/2 + tUnite + tAggregateRow_1).
--
-- Validado en Colombia: salida IDENTICA (diff 0/0) a la billing_accounts de Talend.
--
-- SEGURIDAD: mientras se valida en paralelo, escribe en `${target_table}` = billing_accounts_new.
-- En el cutover (tras cerrar facturacion y con OK del usuario) se cambia a billing_accounts.
--
-- Parametros: ${project}, ${dataset}, ${target_table}
CREATE OR REPLACE TABLE `${project}.${dataset}.${target_table}` AS
WITH facturables AS (
  -- Oportunidades facturables del pais (StageName cerrada + contrato activo).
  SELECT
    COALESCE(SAFE.PARSE_DATE('%Y-%m-%d', Fecha_Fin_Contrato__c), DATE '9999-12-31')    AS Fecha_Fin_Contrato__c,
    COALESCE(SAFE.PARSE_DATE('%Y-%m-%d', Fecha_Inicio_Contrato__c), DATE '9999-12-31') AS Fecha_Inicio_Contrato__c,
    billing_account_id__c, billing_account_desc__c, Desglosar_Facturas__c, Billing_Model__c
  FROM `${project}.${dataset}.stg_opportunity`
  WHERE StageName = 'Cerrada ganada'
    AND (Estado_del_contrato__c = 'Activado' OR Estado_del_contrato__c = '' OR Estado_del_contrato__c IS NULL)
),
n_a AS (
  -- Relleno: todas las Billing_Account__c con fechas/valores constantes (igual que Talend).
  SELECT DATE '9999-12-31', DATE '9999-12-31', billing_account_id__c, billing_account_desc__c, '', 'N/A'
  FROM `${project}.${dataset}.stg_billing_account`
),
u AS (SELECT * FROM facturables UNION ALL SELECT * FROM n_a)
SELECT
  MAX(Fecha_Fin_Contrato__c)    AS Fecha_Fin_Contrato__c,
  MAX(Fecha_Inicio_Contrato__c) AS Fecha_Inicio_Contrato__c,
  billing_account_id__c,
  billing_account_desc__c,
  MAX(Desglosar_Facturas__c)    AS Desglosar_Facturas__c,
  MAX(Billing_Model__c)         AS Billing_Model__c
FROM u
GROUP BY billing_account_id__c, billing_account_desc__c;
