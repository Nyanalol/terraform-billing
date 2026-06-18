"""
Get Currencies Exchange Rates job.

Generates all currency cross-rate combinations using the Hexarate API
and writes results directly to BigQuery (WRITE_TRUNCATE).

Key logic:
- Cartesian product of all currencies from CURRENCIES env var
- Same currency pairs → exchange_rate = 1.0, no API call
- Different pairs → GET https://hexarate.paikama.co/api/rates/{base}/{target}/{date}
- Date = first day of NEXT month (e.g. month=05/year=2026 → 2026-06-01)
- API returns XML, extracts base/target/mid/timestamp from /root/data
- Async HTTP with exponential backoff retry

Usage:
    python -m src.etl.jobs.get_currencies_exchange_rates --country win_uk --month 05 --year 2026
"""

import asyncio
import json
import sys
from datetime import date, timedelta, datetime, timezone
from itertools import product

import httpx
import structlog
from google.cloud import bigquery
from pydantic import BaseModel, ConfigDict

from src.config import load_country_settings
from src.utils.logging_config import configure_logging

logger = structlog.get_logger(__name__)

HEXARATE_BASE_URL = "https://hexarate.paikama.co/api/rates/{base}/{target}/{date}"
MAX_RETRIES = 3
RETRY_BASE_DELAY = 1.0  # seconds
MAX_CONCURRENT = 10     # semaphore limit to avoid hammering the API


class GetCurrenciesJobConfig(BaseModel):
    country: str
    billing_month: str   # zero-padded e.g. "05"
    billing_year: str    # e.g. "2026"

    gcp_project_id: str
    bq_output_dataset: str
    bq_output_table: str = "currency_exchange_rates"   # tabla CENTRAL (singular)

    currencies: list[str]

    model_config = ConfigDict(extra="ignore")


def _first_day_of_next_month(year: str, month: str) -> str:
    """Return YYYY-MM-DD of the first day of the month following year/month."""
    d = date(int(year), int(month), 1)
    # Add ~32 days then replace day to 1
    next_month = (d.replace(day=28) + timedelta(days=4)).replace(day=1)
    return next_month.isoformat()


async def _fetch_rate(
    client: httpx.AsyncClient,
    semaphore: asyncio.Semaphore,
    base: str,
    target: str,
    query_date: str,
) -> dict:
    """Fetch exchange rate from Hexarate API with exponential backoff retry."""
    url = HEXARATE_BASE_URL.format(base=base, target=target, date=query_date)

    for attempt in range(MAX_RETRIES):
        try:
            async with semaphore:
                response = await client.get(url=url, timeout=120.0)
                response.raise_for_status()

            payload = response.json()
            data = payload.get("data")
            if not data:
                logger.warning("hexarate_empty_data", base=base, target=target, date=query_date)
                return {"base_currency": base, "target_currency": target, "exchange_rate": None, "timestamp": None}

            return {
                "base_currency": data.get("base", base),
                "target_currency": data.get("target", target),
                "exchange_rate": float(data.get("mid") or 0),
                "timestamp": data.get("timestamp"),
            }

        except (httpx.HTTPStatusError, httpx.RequestError, KeyError, ValueError) as e:
            if attempt < MAX_RETRIES - 1:
                delay = RETRY_BASE_DELAY * (2 ** attempt)
                logger.warning("hexarate_retry", base=base, target=target, attempt=attempt + 1, error=str(e), retry_in=delay)
                await asyncio.sleep(delay)
            else:
                logger.error("hexarate_failed_after_retries", base=base, target=target, error=str(e))
                return {"base_currency": base, "target_currency": target, "exchange_rate": None, "timestamp": None}


async def fetch_all_rates(config: GetCurrenciesJobConfig) -> list[dict]:
    """Generate cartesian product and fetch all exchange rates."""
    query_date = _first_day_of_next_month(config.billing_year, config.billing_month)
    logger.info("api_query_date", date=query_date)

    currencies = config.currencies
    pairs = list(product(currencies, currencies))

    auth = None
    semaphore = asyncio.Semaphore(MAX_CONCURRENT)

    same_currency = [
        {"base_currency": c, "target_currency": c, "exchange_rate": 1.0, "timestamp": None}
        for c in currencies
    ]

    different_pairs = [(b, t) for b, t in pairs if b != t]

    async with httpx.AsyncClient() as client:
        tasks = [
            _fetch_rate(client, semaphore, base, target, query_date)
            for base, target in different_pairs
        ]
        api_results = await asyncio.gather(*tasks)

    # Enriquecer al schema CENTRAL: rate_date (fecha del cambio), billing_month (YYYYMM para
    # el JOIN con invoice_month) y fetched_at. Se descartan los pares sin rate (exchange_rate
    # REQUIRED en la tabla central); un par ausente lo trata el mart como IFNULL(...,1.0), igual.
    billing_month = f"{config.billing_year}{config.billing_month}"
    fetched_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    out = [
        {
            "base_currency": r["base_currency"],
            "target_currency": r["target_currency"],
            "exchange_rate": r["exchange_rate"],
            "rate_date": query_date,
            "billing_month": billing_month,
            "fetched_at": fetched_at,
        }
        for r in (same_currency + list(api_results))
        if r.get("exchange_rate") is not None
    ]
    logger.info("rates_fetched", total=len(out), same_currency=len(same_currency), api_calls=len(different_pairs))
    return out


def _bq_client(project_id: str) -> bigquery.Client:
    """Honra GOOGLE_OAUTH_ACCESS_TOKEN (correr fuera de Cloud Run); si no, ADC."""
    import os
    token = os.environ.get("GOOGLE_OAUTH_ACCESS_TOKEN")
    if token:
        from google.oauth2.credentials import Credentials
        return bigquery.Client(project=project_id, credentials=Credentials(token=token))
    return bigquery.Client(project=project_id)


def _write_to_bigquery(rows: list[dict], config: GetCurrenciesJobConfig) -> None:
    """Escribe la matriz en la tabla CENTRAL, idempotente por mes (WRITE_TRUNCATE de la
    partición rate_date). Crea la tabla particionada+clusterizada si no existe (p. ej. sandbox)."""
    client = _bq_client(config.gcp_project_id)
    base_table_id = f"{config.gcp_project_id}.{config.bq_output_dataset}.{config.bq_output_table}"

    schema = [
        bigquery.SchemaField("base_currency", "STRING", mode="REQUIRED"),
        bigquery.SchemaField("target_currency", "STRING", mode="REQUIRED"),
        bigquery.SchemaField("exchange_rate", "FLOAT64", mode="REQUIRED"),
        bigquery.SchemaField("rate_date", "DATE", mode="REQUIRED"),
        bigquery.SchemaField("billing_month", "STRING", mode="REQUIRED"),
        bigquery.SchemaField("fetched_at", "TIMESTAMP"),
    ]

    # Crear la tabla si no existe (en prod ya la crea Terraform; en sandbox no).
    table = bigquery.Table(base_table_id, schema=schema)
    table.time_partitioning = bigquery.TimePartitioning(
        type_=bigquery.TimePartitioningType.DAY, field="rate_date"
    )
    table.clustering_fields = ["base_currency", "target_currency"]
    client.create_table(table, exists_ok=True)

    # WRITE_TRUNCATE de la partición del mes (rate_date = primer día del mes siguiente).
    partition = rows[0]["rate_date"].replace("-", "")  # YYYYMMDD
    target = f"{base_table_id}${partition}"

    job_config = bigquery.LoadJobConfig(
        schema=schema,
        write_disposition="WRITE_TRUNCATE",
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
    )

    import io
    buf = io.StringIO()
    for row in rows:
        buf.write(json.dumps(row) + "\n")
    buf.seek(0)

    load_job = client.load_table_from_file(buf, target, job_config=job_config)
    load_job.result()
    logger.info("bigquery_write_complete", table=target, rows=len(rows))


async def main(country: str, month: str, year: str) -> int:
    configure_logging(log_level="INFO", environment="production")

    try:
        settings = load_country_settings(country)
    except FileNotFoundError as e:
        logger.error("country_config_not_found", error=str(e))
        return 1

    currencies = [c.strip() for c in settings.currencies.split(",") if c.strip()]
    logger.info("currencies_loaded", currencies=currencies)

    job_config = GetCurrenciesJobConfig(
        country=country,
        billing_month=month.zfill(2),
        billing_year=year,
        gcp_project_id=settings.bq_currencies_project,
        bq_output_dataset=settings.bq_currencies_dataset,
        bq_output_table=settings.bq_currencies_table,
        currencies=currencies,
    )

    try:
        rows = await fetch_all_rates(job_config)

        # Guard: don't truncate table if all API rates failed
        valid_rows = [r for r in rows if r.get("exchange_rate") is not None]
        if not valid_rows:
            logger.error("all_exchange_rates_failed", total_rows=len(rows))
            return 1

        _write_to_bigquery(rows, job_config)
        logger.info("job_completed_successfully", country=country, rows_written=len(rows))
        return 0
    except Exception as e:
        logger.error("job_failed", error=str(e), exc_info=True)
        return 1


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Get Currencies Exchange Rates")
    parser.add_argument("--country", required=True, help="Country code (e.g., win_uk)")
    parser.add_argument("--month", required=True, help="Billing month (e.g., 05)")
    parser.add_argument("--year", required=True, help="Billing year (e.g., 2026)")
    args = parser.parse_args()

    exit_code = asyncio.run(main(args.country, args.month, args.year))
    sys.exit(exit_code)
