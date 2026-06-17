CREATE VIEW `ip-billing-prod.consolidado_src.importes_lecturas`
AS SELECT * REPLACE(SAFE_CAST(SKU AS FLOAT64) AS SKU) FROM `ip-billing-prod.billing_views.importes_lecturas`;
