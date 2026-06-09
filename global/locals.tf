locals {
  # El dataset de vistas es siempre "looker_views" en cada país (lo fija el módulo por país).
  looker_dataset = "looker_views"

  global_sa_email  = "${var.global_service_account_id}@${var.global_project_id}.iam.gserviceaccount.com"
  global_sa_member = "serviceAccount:${local.global_sa_email}"

  # Filtro de ventana móvil sobre invoice_month (STRING 'YYYYMM'). Se evalúa en SQL en cada
  # ejecución, así que rueda solo. months_back=3 -> mes actual + 2 anteriores (INTERVAL 2 MONTH).
  cutoff_sql_expr = format(
    "FORMAT_DATE('%%Y%%m', DATE_SUB(DATE_TRUNC(CURRENT_DATE(), MONTH), INTERVAL %d MONTH))",
    var.months_back - 1,
  )

  # SQL del union por vista: CREATE OR REPLACE TABLE ... CLUSTER BY ... AS <UNION ALL por país>.
  # El DDL crea/reemplaza la tabla y fija el clustering; el filtro de 3 meses la mantiene pequeña.
  union_sql = {
    for v in var.views : v =>
    "CREATE OR REPLACE TABLE `${var.global_project_id}.${var.global_dataset}.${v}` CLUSTER BY country, invoice_month AS\n${
      join("\nUNION ALL\n", [
        for cname, pid in var.countries :
        "SELECT *, '${cname}' AS country FROM `${pid}.${local.looker_dataset}.${v}` WHERE invoice_month >= ${local.cutoff_sql_expr}"
      ])
    }"
  }
}
