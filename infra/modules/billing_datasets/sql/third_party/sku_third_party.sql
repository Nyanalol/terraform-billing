/*
  TABLA: third_party.sku_third_party
  Gestionada por Talend / scheduled query de migración desde el proyecto Spain.

  Esquema de referencia (el schema real lo gestiona Talend):
    service_name  STRING   -- Nombre del servicio de terceros
    sku_name      STRING   -- Nombre del SKU
    sku_id        STRING   -- Identificador del SKU
    date_added    STRING   -- Fecha de alta (formato libre)

  DDL para recrear manualmente si fuera necesario:
*/

CREATE OR REPLACE TABLE `<project_id>.third_party.sku_third_party` (
  service_name STRING,
  sku_name     STRING,
  sku_id       STRING,
  date_added   STRING
);
