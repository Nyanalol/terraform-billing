SELECT Fecha_Fin_Contrato__c, Fecha_Inicio_Contrato__c, billing_account_id__c,
       billing_account_desc__c, Desglosar_Facturas__c, Billing_Model__c
FROM Opportunity 
WHERE {empresa_filter}
  AND billing_account_id__c != null
  AND StageName = '{stage_name}'
  AND (
    Estado_del_contrato__c = 'Activado' 
    OR Estado_del_contrato__c = '' 
    OR Estado_del_contrato__c = NULL
  )
