# ─── Stored procedures ───────────────────────────────────────────────────────
# borrar_lecturas_mes: borra las lecturas de un mes concreto de las tablas
# importes_lecturas_* (gestionadas por Talend). Sustituye al script manual que
# antes vivía suelto en sql/queries/. Ahora es un procedimiento versionado y
# ejecutable desde BigQuery:
#   CALL `<project>.billing_views.borrar_lecturas_mes`('2025', '01');

resource "google_bigquery_routine" "borrar_lecturas_mes" {
  project      = var.project_id
  dataset_id   = google_bigquery_dataset.billing_views.dataset_id
  routine_id   = "borrar_lecturas_mes"
  routine_type = "PROCEDURE"
  language     = "SQL"

  arguments {
    name      = "anyo"
    data_type = jsonencode({ typeKind = "STRING" })
  }

  arguments {
    name      = "mes"
    data_type = jsonencode({ typeKind = "STRING" })
  }

  arguments {
    name      = "dry_run"
    data_type = jsonencode({ typeKind = "BOOL" })
  }

  definition_body = templatefile("${path.module}/sql/queries/borrar_lecturas_mes.sql", {
    project_id            = var.project_id
    billing_views_dataset = google_bigquery_dataset.billing_views.dataset_id
  })

  description = "Borra las lecturas de un mes de las tablas importes_lecturas_*. Args: anyo, mes (NULL=mes anterior), dry_run (NULL/TRUE=solo preview, FALSE=borra). Ej: CALL billing_views.borrar_lecturas_mes(NULL,NULL,TRUE)."

  depends_on = [
    google_bigquery_table.importes_lecturas_temp,
    google_bigquery_table.importes_lecturas_by_project,
    google_bigquery_table.importes_lecturas_anuales,
    google_bigquery_table.importes_lecturas_workspace,
  ]
}
