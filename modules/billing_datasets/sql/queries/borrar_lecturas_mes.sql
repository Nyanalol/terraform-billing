/*
  INSTRUCCIONES:
  Rellena las dos variables de abajo antes de ejecutar:
    - anyo : el año  del mes a borrar, en formato 'YYYY'  (p.ej. '2025')
    - mes  : el mes  del mes a borrar, en formato 'MM'    (p.ej. '03' para marzo)

  El script borrará todas las filas cuyo invoice_month = 'YYYYMM'
  de las tablas importes_lecturas_temp, _by_project e _anuales,
  y las filas con Anyo__c = anyo AND Mes__c = mes de importes_lecturas_workspace.

  IMPORTANTE: este script es de uso manual — NO está gestionado por Terraform.
*/

DECLARE anyo STRING DEFAULT '2025';  -- ← cambia el año aquí
DECLARE mes  STRING DEFAULT '01';    -- ← cambia el mes aquí (dos dígitos)
DECLARE invoice_month_param STRING DEFAULT CONCAT(anyo, mes);

DELETE FROM `${project_id}.billing_views.importes_lecturas_temp`
WHERE invoice_month = invoice_month_param;

DELETE FROM `${project_id}.billing_views.importes_lecturas_by_project`
WHERE invoice_month = invoice_month_param;

DELETE FROM `${project_id}.billing_views.importes_lecturas_anuales`
WHERE invoice_month = invoice_month_param;

DELETE FROM `${project_id}.billing_views.importes_lecturas_workspace`
WHERE Mes__c = mes AND Anyo__c = anyo;