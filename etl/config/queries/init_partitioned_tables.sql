-- Initialize partitioned billing accounts tables
-- Run this once per country to create the table structure with partitions
-- 
-- Usage:
--   gcloud bigquery query --location=EU --use_legacy_sql=false < init_partitioned_tables.sql

-- Create billing_accounts table if not exists
-- Partitioned by billing_date (MONTH)
CREATE TABLE IF NOT EXISTS `{project}.{transformed_dataset}.billing_accounts`
PARTITION BY DATE_TRUNC(billing_date, MONTH)
CLUSTER BY billing_account_id__c
AS
SELECT
  CAST(NULL AS STRING) AS Fecha_Fin_Contrato__c,
  CAST(NULL AS STRING) AS Fecha_Inicio_Contrato__c,
  CAST(NULL AS STRING) AS billing_account_id__c,
  CAST(NULL AS STRING) AS billing_account_desc__c,
  CAST(NULL AS STRING) AS Desglosar_Facturas__c,
  CAST(NULL AS STRING) AS Billing_Model__c,
  CAST(NULL AS DATE) AS billing_date
WHERE FALSE;

-- Create billing_accounts_full table if not exists
-- Partitioned by billing_date (MONTH)
CREATE TABLE IF NOT EXISTS `{project}.{transformed_dataset}.billing_accounts_full`
PARTITION BY DATE_TRUNC(billing_date, MONTH)
CLUSTER BY billing_account_id__c
AS
SELECT
  CAST(NULL AS STRING) AS Fecha_Fin_Contrato__c,
  CAST(NULL AS STRING) AS Fecha_Inicio_Contrato__c,
  CAST(NULL AS STRING) AS billing_account_id__c,
  CAST(NULL AS STRING) AS billing_account_desc__c,
  CAST(NULL AS STRING) AS Desglosar_Facturas__c,
  CAST(NULL AS STRING) AS Billing_Model__c,
  CAST(NULL AS STRING) AS StageName,
  CAST(NULL AS STRING) AS Empresa_IP__c,
  CAST(NULL AS DATE) AS billing_date
WHERE FALSE;
