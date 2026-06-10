"""Helpers de BigQuery para el ETL (cliente + carga)."""
from __future__ import annotations

import os


def client(project: str):
    """Cliente BQ. En local usa GOOGLE_OAUTH_ACCESS_TOKEN (cuenta SWO) si esta presente;
    en Cloud Run cae a ADC (la service account del servicio)."""
    from google.cloud import bigquery

    token = os.environ.get("GOOGLE_OAUTH_ACCESS_TOKEN")
    if token:
        from google.oauth2.credentials import Credentials
        return bigquery.Client(project=project, credentials=Credentials(token=token))
    return bigquery.Client(project=project)


def load_rows(rows: list[dict], table_fqn: str, columns: list[str], project: str,
              write_disposition: str = "WRITE_TRUNCATE") -> int:
    """Carga filas (todas las columnas STRING) en una tabla. Devuelve nº de filas."""
    from google.cloud import bigquery

    schema = [bigquery.SchemaField(c, "STRING") for c in columns]
    job_config = bigquery.LoadJobConfig(
        write_disposition=write_disposition,
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
        schema=schema,
    )
    job = client(project).load_table_from_json(rows, table_fqn, job_config=job_config)
    job.result()
    return len(rows)
