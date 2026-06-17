SELECT
  billing_account_id,
  Dominio,
  OpportunityId,
  SKU,
  Currency,
  TotalSupport_original,
  GCP_original,
  GMP_original,
  ThirdParty_original,
  GCP_original + GMP_original + ThirdParty_original AS Importe_sin_soporte_original,
  Margen_GCP,
  Margen_GMP,
  Margen_total,
  TotalSupport_original / cambio_aplicado AS TotalSupport_EUR,
  GCP_original / cambio_aplicado AS GCP_EUR,
  GMP_original / cambio_aplicado AS GMP_EUR,
  (GCP_original + GMP_original + ThirdParty_original) / cambio_aplicado AS Importe_sin_soporte_EUR,
  Cargo_Google_original,
  Cargo_Google_original / cambio_aplicado AS Cargo_Google_EUR,
  Importe_original,
  Importe_original / cambio_aplicado AS Importe_EUR,
  invoice_month,
  invoice_date,
  cambio_aplicado,
  CONCAT(moneda, CAST(TotalSupport_original AS STRING)) AS TotalSupport_str,
  CONCAT(moneda, CAST(GCP_original AS STRING)) AS GCP_original_str,
  CONCAT(moneda, CAST(GMP_original AS STRING)) AS GMP_original_str,
  CONCAT(moneda, CAST(Cargo_Google_original AS STRING)) AS Cargo_Google_str,
  CONCAT(moneda, CAST(Importe_original AS STRING)) AS Importe_str,
  billing_model,
  project_id,
  IF((GCP_original + GMP_original) <= 0.01, 1, 0) AS LecturasSoloSoporte
FROM (
  SELECT
    billing_account_id,
    Dominio__c AS Dominio,
    OpportunityId__c AS OpportunityId,
    SKU__c AS SKU,
    CurrencyIsoCode__c AS Currency,
    CAST(TotalSupport AS NUMERIC) AS TotalSupport_original,
    CAST(Total_gcp AS NUMERIC) AS GCP_original,
    CAST(Magen_gcp AS NUMERIC) AS Margen_GCP,
    CAST(Total_gmp AS NUMERIC) AS GMP_original,
    CAST(Margen_gmp AS NUMERIC) AS Margen_GMP,
    CAST(Total_thirdparty AS NUMERIC) AS ThirdParty_original,
    CAST(Margen_total AS NUMERIC) AS Margen_total,
    CAST(Cargo_Google__c AS NUMERIC) AS Cargo_Google_original,
    CAST(Importe__c AS NUMERIC) AS Importe_original,
    invoice_month,
    PARSE_DATE('%d-%m-%Y', invoice_date) AS invoice_date,
    CAST(cambio_aplicado AS NUMERIC) AS cambio_aplicado,
    IFNULL(cs.symbol, '€') AS moneda,
    billing_model,
    project_id
  FROM (
    SELECT
      billing_account_id, Dominio__c, OpportunityId__c, SKU__c, CurrencyIsoCode__c,
      TotalSupport, Margen__c, Total_gcp, Magen_gcp, Total_gmp, Margen_gmp,
      Margen_total, Cargo_Google__c, Importe__c, invoice_month, invoce_date AS invoice_date,
      cambio_aplicado, project_id, descripcion, Margen_gcp_euros, Margen_gmp_euros,
      Margen_soporte_euros, 'Flexible' AS billing_model, Total_thirdparty
    FROM `${project_id}.${billing_views_dataset}.importes_lecturas_temp`

    UNION ALL

    SELECT
      billing_account_id, Dominio__c, OpportunityId__c, SKU__c, CurrencyIsoCode__c,
      TotalSupport, Margen__c, Total_gcp, Magen_gcp, Total_gmp, Margen_gmp,
      Margen_total, Cargo_Google__c, Importe__c, invoice_month, invoice_date,
      cambio_aplicado, project_id, descripcion, Margen_gcp_euros, Margen_gmp_euros,
      Margen_soporte_euros, 'Flexibles desglosadas' AS billing_model, CAST(Total_thirdparty AS NUMERIC) AS Total_thirdparty
    FROM `${project_id}.${billing_views_dataset}.importes_lecturas_by_project`

    UNION ALL

    SELECT
      billing_account_id, Dominio__c, OpportunityId__c, SKU__c, CurrencyIsoCode__c,
      TotalSupport, Margen__c, Total_gcp, Magen_gcp, Total_gmp, Margen_gmp,
      Margen_total, Cargo_Google__c, Importe__c, invoice_month, invoce_date AS invoice_date,
      cambio_aplicado, project_id, descripcion, Margen_gcp_euros, Margen_gmp_euros,
      Margen_soporte_euros, 'Anuales' AS billing_model, Total_thirdparty
    FROM `${project_id}.${billing_views_dataset}.importes_lecturas_anuales`
  ) AS source_data
  LEFT JOIN `${project_id}.${billing_cp_dataset}.currency_symbols` AS cs
    ON source_data.CurrencyIsoCode__c = cs.currency_iso_code
) AS t