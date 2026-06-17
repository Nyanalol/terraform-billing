CREATE VIEW `swouk-billing-prod.consolidado_src.consumos_google_reseller_factura`
AS SELECT invoice_month, account, consumo, cost, all_creditos, creditos, creditos_reseller, descuento_reseller_old, descuento_reseller_new, descuento_reseller
FROM `swouk-billing-prod.looker_views.consumos_google_reseller_factura`;
