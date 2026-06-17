CREATE OR REPLACE TABLE `{project}.{transformed_dataset}.{table_name}_backup_{backup_timestamp}` AS
SELECT * FROM `{project}.{transformed_dataset}.{table_name}`;

CREATE OR REPLACE TABLE `{project}.{transformed_dataset}.{table_name}` AS
SELECT
  billing_account_id__c,
  Empresa_IP__c,
  MAX(CAST(Fecha_Inicio_Contrato__c AS STRING)) AS Fecha_Inicio_Contrato__c,
  MAX(CAST(Fecha_Fin_Contrato__c AS STRING)) AS Fecha_Fin_Contrato__c,
  MAX(CAST(Desglosar_Facturas__c AS STRING)) AS Desglosar_Facturas__c,
  MAX(CAST(Billing_Model__c AS STRING)) AS Billing_Model__c,
  MAX(CAST(billing_account_desc__c AS STRING)) AS billing_account_desc__c,
  MAX(CAST(StageName AS STRING)) AS StageName
FROM `{project}.{raw_dataset}.raw_all_opportunities`
WHERE billing_account_id__c IS NOT NULL
GROUP BY billing_account_id__c, Empresa_IP__c
