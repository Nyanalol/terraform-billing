-- Generic Opportunity Line Items Query
-- Parameters (loaded from .env.{country}):
--   {skus}: Comma-separated list of SKU codes (e.g., 1417,1409,1410,1731,...)
--   {billing_month}: Billing month (1-12)
--   {billing_year}: Billing year (e.g., 2026)

SELECT *
FROM OpportunityLineItem
WHERE SKU__c IN ({skus})
  AND (
    Fecha_Inicio_Contrato_Opp__c = NULL 
    OR Fecha_Inicio_Contrato_Opp__c < CURRENT_DATE()
  )
  AND (
    Fecha_Fin_Contrato_Opp__c = NULL 
    OR Fecha_Fin_Contrato_Opp__c >= CURRENT_DATE()
  )
