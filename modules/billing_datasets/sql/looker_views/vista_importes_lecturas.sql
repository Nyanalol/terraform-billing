SELECT
  billing_account_id,
  Dominio__c,
  OpportunityId__c,
  SKU__c,
  CurrencyIsoCode__c,
  TotalSupport,
  Margen_soporte_euros,
  Margen_soporte_maps_euros,
  Total_gcp,
  Margen_gcp,
  Total_gmp,
  Margen_gmp,
  Total_thirdparty,
  Margen_total,
  Total_gcp / cambio_aplicado AS gcp_euros,
  Total_gmp / cambio_aplicado AS gmp_euros,
  Total_thirdparty / cambio_aplicado AS thirdparty_euros,
  (Total_gcp + Total_gmp) / cambio_aplicado AS Importe_GCP_Eur,
  Cargo_Google__c,
  Cargo_Google__c / cambio_aplicado AS Cargo_Google_Eur,
  Importe__c,
  Importe__c / cambio_aplicado AS Importe_Eur,
  invoice_month,
  invoice_date,
  cambio_aplicado,
  CONCAT(moneda, CAST(TotalSupport AS STRING)) AS TotalSupport_str,
  CONCAT(moneda, CAST(Total_gcp AS STRING)) AS Total_gcp_str,
  CONCAT(moneda, CAST(Total_gmp AS STRING)) AS Total_gmp_str,
  CONCAT(moneda, CAST(Total_thirdparty AS STRING)) AS Total_thirdparty_str,
  CONCAT(moneda, CAST(Cargo_Google__c AS STRING)) AS Cargo_Google_str,
  CONCAT(moneda, CAST(Importe__c AS STRING)) AS Importe_str,
  billing_model,
  project_id,
  IF(TotalSupport = Importe__c, 1, 0) AS LecturasSoloSoporte
FROM (
  SELECT
    billing_account_id,
    Dominio__c,
    OpportunityId__c,
    SKU__c,
    CurrencyIsoCode__c,
    CAST(TotalSupport AS NUMERIC) AS TotalSupport,
    CAST(Margen_soporte_euros AS NUMERIC) AS Margen_soporte_euros,
    CAST(Margen_soporte_maps_euros AS NUMERIC) AS Margen_soporte_maps_euros,
    CAST(Total_gcp AS NUMERIC) AS Total_gcp,
    CAST(Magen_gcp AS NUMERIC) AS Margen_gcp,
    CAST(Total_gmp AS NUMERIC) AS Total_gmp,
    CAST(Margen_gmp AS NUMERIC) AS Margen_gmp,
    CAST(Margen_total AS NUMERIC) AS Margen_total,
    CAST(Cargo_Google__c AS NUMERIC) AS Cargo_Google__c,
    CAST(Importe__c AS NUMERIC) AS Importe__c,
    invoice_month,
    PARSE_DATE('%d-%m-%Y', invoice_date) AS invoice_date,
    CAST(cambio_aplicado AS NUMERIC) AS cambio_aplicado,
    IFNULL(cs.symbol, '€') AS moneda,
    billing_model,
    project_id,
    CAST(Total_thirdparty AS NUMERIC) AS Total_thirdparty
  FROM (
    SELECT
      billing_account_id, Dominio__c, OpportunityId__c, SKU__c, CurrencyIsoCode__c,
      TotalSupport, Margen__c, Total_gcp, Magen_gcp, Total_gmp, Margen_gmp,
      Margen_total, Cargo_Google__c, Importe__c, invoice_month, invoce_date AS invoice_date,
      cambio_aplicado, project_id, descripcion, Margen_gcp_euros, Margen_gmp_euros,
      Margen_soporte_euros, Margen_soporte_maps_euros, Total_thirdparty,
      'Flexible' AS billing_model
    FROM `${project_id}.${billing_views_dataset}.importes_lecturas_temp`

    UNION ALL

    SELECT
      billing_account_id, Dominio__c, OpportunityId__c, SKU__c, CurrencyIsoCode__c,
      TotalSupport, Margen__c, Total_gcp, Magen_gcp, Total_gmp, Margen_gmp,
      Margen_total, Cargo_Google__c, Importe__c, invoice_month, invoice_date,
      cambio_aplicado, project_id, descripcion, Margen_gcp_euros, Margen_gmp_euros,
      Margen_soporte_euros, Margen_soporte_maps_euros, CAST(Total_thirdparty AS NUMERIC),
      'Flexibles desglosadas' AS billing_model
    FROM `${project_id}.${billing_views_dataset}.importes_lecturas_by_project`

    UNION ALL

    SELECT
      billing_account_id, Dominio__c, OpportunityId__c, SKU__c, CurrencyIsoCode__c,
      TotalSupport, Margen__c, Total_gcp, Magen_gcp, Total_gmp, Margen_gmp,
      Margen_total, Cargo_Google__c, Importe__c, invoice_month, invoce_date AS invoice_date,
      cambio_aplicado, project_id, descripcion, Margen_gcp_euros, Margen_gmp_euros,
      Margen_soporte_euros, Margen_soporte_maps_euros, Total_thirdparty,
      'Anuales' AS billing_model
    FROM `${project_id}.${billing_views_dataset}.importes_lecturas_anuales`
  ) AS source_data
  LEFT JOIN `${project_id}.${billing_cp_dataset}.currency_symbols` AS cs
    ON source_data.CurrencyIsoCode__c = cs.currency_iso_code
) AS t