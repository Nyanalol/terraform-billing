#!/usr/bin/env python3
"""Extrae los tipos de cambio del mes y los carga en BigQuery.

Sustituye al job de Talend `currencies_exchange_rates`. En vez de pedir las N*(N-1)
parejas a la API, pide solo EUR->cada_divisa y deriva la matriz completa:
    rate(A->B) = rate(EUR->B) / rate(EUR->A)
(la propia API deriva todo de una base, asi que el cross-rate coincide).

Idempotente: escribe SOLO la particion rate_date de la tabla (WRITE_TRUNCATE sobre
`tabla$YYYYMMDD`), asi que re-ejecutar un mes no duplica.

Diseñado para Cloud Run (config por variables de entorno) pero ejecutable en local.
Solo depende de google-cloud-bigquery, y solo para la carga real: con --dry-run no
hace falta ninguna libreria externa (HTTP via urllib de stdlib).

Ejemplos:
    python fetch_exchange_rates.py --month 202605 --dry-run
    python fetch_exchange_rates.py --month 202605
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import logging
import os
import sys
import time
import urllib.error
import urllib.request

LOG = logging.getLogger("currencies")

# Universo de divisas (union de currency_symbols de todos los paises).
DEFAULT_CURRENCIES = ["EUR", "USD", "GBP", "HKD", "INR", "VND", "MXN", "COP", "SGD", "CHF", "BRL"]
BASE = "EUR"  # ancla para derivar la matriz
API_TMPL = "https://hexarate.paikama.co/api/rates/{base}/{target}/{date}"

DEFAULT_PROJECT = "swo-billingglobal-prod"
DEFAULT_DATASET = "billing_reference"
DEFAULT_TABLE = "currency_exchange_rates"


def first_day_next_month(year: int, month: int) -> dt.date:
    """Primer dia del mes SIGUIENTE al facturado (cierre de mes, igual que Talend)."""
    return dt.date(year + (month // 12), (month % 12) + 1, 1)


def fetch_eur_rate(target: str, rate_date: dt.date, retries: int = 4, timeout: int = 30) -> float:
    """rate(EUR->target) a la fecha dada. EUR->EUR = 1.0 sin llamar a la API."""
    if target == BASE:
        return 1.0
    url = API_TMPL.format(base=BASE, target=target, date=rate_date.isoformat())
    last_err: Exception | None = None
    for attempt in range(1, retries + 1):
        try:
            req = urllib.request.Request(url, headers={
                "Accept": "application/json",
                "User-Agent": "swo-billing-etl/1.0",
            })
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                payload = json.loads(resp.read().decode("utf-8"))
            mid = payload.get("data", {}).get("mid")
            if mid is None:
                raise ValueError(f"respuesta sin 'data.mid': {payload}")
            return float(mid)
        except (urllib.error.URLError, ValueError, json.JSONDecodeError) as err:
            last_err = err
            wait = 2 ** attempt
            LOG.warning("EUR->%s intento %d/%d fallo (%s); reintento en %ds", target, attempt, retries, err, wait)
            time.sleep(wait)
    raise RuntimeError(f"No se pudo obtener EUR->{target} tras {retries} intentos: {last_err}")


def build_matrix(currencies: list[str], rate_date: dt.date, billing_month: str, fetched_at: str) -> list[dict]:
    """Pide EUR->X para cada divisa y deriva todas las parejas base->target."""
    eur = {c: fetch_eur_rate(c, rate_date) for c in currencies}
    LOG.info("Rates EUR->X: %s", {c: round(v, 6) for c, v in eur.items()})
    rows = []
    for base in currencies:
        for target in currencies:
            rate = 1.0 if base == target else eur[target] / eur[base]
            rows.append({
                "base_currency": base,
                "target_currency": target,
                "exchange_rate": round(rate, 10),
                "rate_date": rate_date.isoformat(),
                "billing_month": billing_month,
                "fetched_at": fetched_at,
            })
    return rows


def load_to_bq(rows: list[dict], project: str, dataset: str, table: str, rate_date: dt.date) -> None:
    """Carga idempotente: trunca y reescribe SOLO la particion rate_date."""
    from google.cloud import bigquery  # import perezoso: solo para la carga real

    # En Cloud Run usa ADC (la service account del servicio). En local, si se exporta
    # GOOGLE_OAUTH_ACCESS_TOKEN (cuenta g.softwareone.com), lo usamos para NO caer en el
    # ADC por defecto de la maquina.
    token = os.environ.get("GOOGLE_OAUTH_ACCESS_TOKEN")
    if token:
        from google.oauth2.credentials import Credentials
        client = bigquery.Client(project=project, credentials=Credentials(token=token))
    else:
        client = bigquery.Client(project=project)
    partition = rate_date.strftime("%Y%m%d")
    dest = f"{project}.{dataset}.{table}${partition}"
    job_config = bigquery.LoadJobConfig(
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
        schema=[
            bigquery.SchemaField("base_currency", "STRING", mode="REQUIRED"),
            bigquery.SchemaField("target_currency", "STRING", mode="REQUIRED"),
            bigquery.SchemaField("exchange_rate", "FLOAT", mode="REQUIRED"),
            bigquery.SchemaField("rate_date", "DATE", mode="REQUIRED"),
            bigquery.SchemaField("billing_month", "STRING", mode="REQUIRED"),
            bigquery.SchemaField("fetched_at", "TIMESTAMP", mode="NULLABLE"),
        ],
    )
    job = client.load_table_from_json(rows, dest, job_config=job_config)
    job.result()
    LOG.info("Cargadas %d filas en %s", len(rows), dest)


def parse_month(value: str | None) -> tuple[int, int, str]:
    """YYYYMM -> (year, month, 'YYYYMM'). Default: mes anterior al actual."""
    if value:
        if len(value) != 6 or not value.isdigit():
            raise argparse.ArgumentTypeError("--month debe ser YYYYMM (p.ej. 202605)")
        return int(value[:4]), int(value[4:]), value
    today = dt.date.today()
    prev = (today.replace(day=1) - dt.timedelta(days=1))  # mes anterior (facturacion)
    return prev.year, prev.month, prev.strftime("%Y%m")


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(description="Carga tipos de cambio mensuales en BigQuery.")
    p.add_argument("--month", help="Mes facturado YYYYMM. Default: mes anterior.")
    p.add_argument("--currencies", help="Lista separada por comas. Default: todas las del proyecto.")
    p.add_argument("--project", default=os.environ.get("BQ_PROJECT", DEFAULT_PROJECT))
    p.add_argument("--dataset", default=os.environ.get("BQ_DATASET", DEFAULT_DATASET))
    p.add_argument("--table", default=os.environ.get("BQ_TABLE", DEFAULT_TABLE))
    p.add_argument("--dry-run", action="store_true", help="No carga en BQ; imprime las filas.")
    args = p.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    year, month, billing_month = parse_month(args.month or os.environ.get("BILLING_MONTH"))
    rate_date = first_day_next_month(year, month)
    currencies = [c.strip().upper() for c in args.currencies.split(",")] if args.currencies else DEFAULT_CURRENCIES
    if BASE not in currencies:
        currencies = [BASE] + currencies
    fetched_at = dt.datetime.now(dt.timezone.utc).isoformat()

    LOG.info("Mes facturado %s -> rate_date %s | %d divisas", billing_month, rate_date, len(currencies))
    rows = build_matrix(currencies, rate_date, billing_month, fetched_at)

    if args.dry_run:
        LOG.info("DRY-RUN: %d filas (no se carga en BQ). Muestra:", len(rows))
        for r in rows:
            if r["base_currency"] == BASE:
                print(f"  {r['base_currency']}->{r['target_currency']}: {r['exchange_rate']}")
        return 0

    load_to_bq(rows, args.project, args.dataset, args.table, rate_date)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
