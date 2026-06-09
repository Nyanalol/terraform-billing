locals {
  # Datasets de cada país: las looker_views (filtran por invoice_month) y las tablas de
  # billing_views que se quieran consolidar (tablas Talend; filtran por Anyo__c/Mes__c).
  looker_dataset  = "looker_views"
  billing_dataset = "billing_views"

  global_sa_email  = "${var.global_service_account_id}@${var.global_project_id}.iam.gserviceaccount.com"
  global_sa_member = "serviceAccount:${local.global_sa_email}"

  # Filtro de ventana móvil (YYYYMM). months_back=3 -> mes actual + 2 anteriores.
  cutoff_sql_expr = format(
    "FORMAT_DATE('%%Y%%m', DATE_SUB(DATE_TRUNC(CURRENT_DATE(), MONTH), INTERVAL %d MONTH))",
    var.months_back - 1,
  )

  # ─── looker_views: filtro por invoice_month, clustering por country + invoice_month ──────
  union_sql = {
    for v in var.views : v =>
    "CREATE OR REPLACE TABLE `${var.global_project_id}.${var.global_dataset}.${v}` CLUSTER BY country, invoice_month AS\n${
      join("\nUNION ALL\n", [
        for cname, pid in var.countries :
        "SELECT *, '${cname}' AS country FROM `${pid}.${local.looker_dataset}.${v}` WHERE invoice_month >= ${local.cutoff_sql_expr}"
      ])
    }"
  }

  # ─── billing_views (tablas Talend): no tienen invoice_month, filtran por Anyo__c/Mes__c ──
  # (CONCAT(Anyo__c, Mes__c) forma 'YYYYMM', ordena cronológicamente). Clustering por country.
  billing_union_sql = {
    for t in var.billing_views_tables : t =>
    "CREATE OR REPLACE TABLE `${var.global_project_id}.${var.global_dataset}.${t}` CLUSTER BY country AS\n${
      join("\nUNION ALL\n", [
        for cname, pid in var.countries :
        "SELECT *, '${cname}' AS country FROM `${pid}.${local.billing_dataset}.${t}` WHERE CONCAT(Anyo__c, Mes__c) >= ${local.cutoff_sql_expr}"
      ])
    }"
  }

  # Mapa combinado tabla -> DDL, que consume la scheduled query (una por entrada).
  all_union_sql = merge(local.union_sql, local.billing_union_sql)
}
