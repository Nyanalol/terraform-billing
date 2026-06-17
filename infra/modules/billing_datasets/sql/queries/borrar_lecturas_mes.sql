-- Cuerpo del stored procedure billing_views.borrar_lecturas_mes(anyo, mes, dry_run).
-- Gestionado por Terraform (routines.tf). project_id y el dataset los inyecta
-- Terraform con templatefile.
--
-- Argumentos (BigQuery no permite defaults en la firma; se usa NULL como "no especificado"):
--   anyo, mes : el mes a borrar ('YYYY','MM'). Si NULL -> mes anterior (año anterior si enero).
--   dry_run   : TRUE/NULL -> solo MUESTRA cuántas filas borraría, NO borra (seguro por defecto).
--               FALSE       -> borra de verdad.
--
-- Ejemplos:
--   CALL `<proj>.billing_views.borrar_lecturas_mes`(NULL, NULL, NULL)   -- preview del mes anterior
--   CALL `<proj>.billing_views.borrar_lecturas_mes`(NULL, NULL, FALSE)  -- borra el mes anterior
--   CALL `<proj>.billing_views.borrar_lecturas_mes`('2025','03', TRUE)  -- preview de marzo 2025
BEGIN
  -- Primer día del mes anterior (gestiona el salto enero -> diciembre del año previo).
  DECLARE prev_month DATE DEFAULT DATE_SUB(DATE_TRUNC(CURRENT_DATE(), MONTH), INTERVAL 1 MONTH);

  -- Valores efectivos: lo que se pasa, o el mes anterior si viene NULL.
  DECLARE _anyo STRING DEFAULT IFNULL(anyo, FORMAT_DATE('%Y', prev_month));
  DECLARE _mes  STRING DEFAULT IFNULL(mes, FORMAT_DATE('%m', prev_month));
  DECLARE invoice_month_param STRING DEFAULT CONCAT(_anyo, _mes);

  -- Solo borra si dry_run = FALSE explícito. NULL o TRUE => preview (no borra).
  DECLARE _borrar BOOL DEFAULT IFNULL(dry_run, TRUE) = FALSE;

  -- Doble check: muestra los PARÁMETROS RESUELTOS antes de ejecutar, para confirmar
  -- que coge bien lo que toca (sobre todo el default de mes anterior cuando van NULL).
  SELECT
    anyo                AS anyo_recibido,   -- lo que pasaste (NULL si no especificaste)
    mes                 AS mes_recibido,
    _anyo               AS anyo_efectivo,    -- lo que realmente usará
    _mes                AS mes_efectivo,
    invoice_month_param AS invoice_month,    -- filtro YYYYMM resultante
    IF(_borrar, 'BORRARÁ datos', 'PREVIEW (no borra)') AS modo;

  IF _borrar THEN
    DELETE FROM `${project_id}.${billing_views_dataset}.importes_lecturas_temp`
    WHERE invoice_month = invoice_month_param;

    DELETE FROM `${project_id}.${billing_views_dataset}.importes_lecturas_by_project`
    WHERE invoice_month = invoice_month_param;

    DELETE FROM `${project_id}.${billing_views_dataset}.importes_lecturas_anuales`
    WHERE invoice_month = invoice_month_param;

    DELETE FROM `${project_id}.${billing_views_dataset}.importes_lecturas_workspace`
    WHERE Mes__c = _mes AND Anyo__c = _anyo;
  END IF;
END
