CREATE OR REPLACE TABLE `{project}.{transformed_dataset}.{table_name}_backup_{backup_timestamp}` AS
SELECT * FROM `{project}.{transformed_dataset}.{table_name}`;

CREATE OR REPLACE TABLE `{project}.{transformed_dataset}.{table_name}` AS
SELECT
  billing_account_id__c,
  billing_account_desc__c,
  MAX(IF(Fecha_Fin_Contrato__c IS NULL, '9999-12-31', CAST(Fecha_Fin_Contrato__c AS STRING))) AS Fecha_Fin_Contrato__c,
  MAX(CAST(Fecha_Inicio_Contrato__c AS STRING)) AS Fecha_Inicio_Contrato__c,
  MAX(CAST(Desglosar_Facturas__c AS STRING)) AS Desglosar_Facturas__c,
  MAX(CAST(Billing_Model__c AS STRING)) AS Billing_Model__c
FROM (
  SELECT billing_account_id__c, billing_account_desc__c,
         CAST(Fecha_Fin_Contrato__c AS STRING) AS Fecha_Fin_Contrato__c,
         CAST(Fecha_Inicio_Contrato__c AS STRING) AS Fecha_Inicio_Contrato__c,
         CAST(Desglosar_Facturas__c AS STRING) AS Desglosar_Facturas__c,
         CAST(Billing_Model__c AS STRING) AS Billing_Model__c
  FROM `{project}.{raw_dataset}.raw_opportunities`
  WHERE billing_account_id__c IS NOT NULL
  UNION ALL
  SELECT billing_account_id__c, billing_account_desc__c,
         '9999-12-31' AS Fecha_Fin_Contrato__c,
         '9999-12-31' AS Fecha_Inicio_Contrato__c,
         '' AS Desglosar_Facturas__c,
         'N/A' AS Billing_Model__c
  FROM `{project}.{raw_dataset}.raw_n_a_opportunities`
  WHERE billing_account_id__c IS NOT NULL
)
GROUP BY billing_account_id__c, billing_account_desc__c
