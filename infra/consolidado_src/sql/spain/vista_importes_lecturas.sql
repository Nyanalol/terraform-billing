CREATE VIEW `ip-billing-prod.consolidado_src.vista_importes_lecturas`
AS SELECT * REPLACE(SAFE_CAST(SKU__c AS FLOAT64) AS SKU__c) FROM `ip-billing-prod.BILLING_CLOUD_PLATFORM.vista_importes_lecturas`;
