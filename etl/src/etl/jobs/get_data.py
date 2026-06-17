"""
Get Data job - Read from BigQuery source tables and write consolidated output tables.

This script:
1. Reads cost data from sum_costs_credits_per_month (by billing account)
2. Reads cost data from sum_costs_credits_per_month_by_project (by project)
3. Writes results directly to output tables in BigQuery via CREATE OR REPLACE TABLE

No data is downloaded to memory - all processing happens inside BigQuery.

Usage:
    python -m src.etl.jobs.get_data --country win_uk --month 05 --year 2026
"""

import asyncio
import sys
from pathlib import Path
from typing import Optional

import structlog
from pydantic import BaseModel, ConfigDict

from src.config import load_country_settings
from src.utils.logging_config import configure_logging
from src.etl.load.bigquery_loader import BigQueryLoader

logger = structlog.get_logger(__name__)


class GetDataJobConfig(BaseModel):
    """Configuration for Get Data job."""

    country: str
    billing_month: str   # zero-padded string e.g. "05"
    billing_year: str    # string e.g. "2026"

    gcp_project_id: str
    bq_input_dataset: str
    bq_output_dataset: str

    # Output table names
    bq_output_table_group_billing: str = "bq_group_billing"
    bq_output_table_group_project: str = "bq_group_project"

    model_config = ConfigDict(extra="ignore")


def _load_query_template(query_name: str) -> str:
    base_path = Path(__file__).parent.parent.parent.parent
    query_file = base_path / "config" / "queries" / f"{query_name}.sql"
    if not query_file.exists():
        raise FileNotFoundError(f"Query template not found: {query_file}")
    with open(query_file, "r") as f:
        return f.read().strip()


async def run_get_data(config: GetDataJobConfig) -> dict:
    """
    Execute both in-database queries and write results to BigQuery output tables.

    No data is pulled to Python memory. BigQuery executes everything server-side.
    """
    logger.info(
        "starting_get_data",
        country=config.country,
        billing_year=config.billing_year,
        billing_month=config.billing_month,
        input_dataset=config.bq_input_dataset,
        output_dataset=config.bq_output_dataset,
    )

    loader = BigQueryLoader(
        project_id=config.gcp_project_id,
        dataset_id=config.bq_output_dataset,
    )
    loader.ensure_dataset_exists()

    group_billing_template = _load_query_template("get_data_group_billing")
    group_project_template = _load_query_template("get_data_group_project")

    params = dict(
        project=config.gcp_project_id,
        input_dataset=config.bq_input_dataset,
        output_dataset=config.bq_output_dataset,
        year=config.billing_year,
        month=config.billing_month,
    )

    group_billing_sql = group_billing_template.format_map(params)
    group_project_sql = group_project_template.format_map(params)

    group_billing_table = f"`{config.gcp_project_id}.{config.bq_output_dataset}.{config.bq_output_table_group_billing}`"
    group_project_table = f"`{config.gcp_project_id}.{config.bq_output_dataset}.{config.bq_output_table_group_project}`"

    create_group_billing = f"CREATE OR REPLACE TABLE {group_billing_table} AS\n{group_billing_sql}"
    create_group_project = f"CREATE OR REPLACE TABLE {group_project_table} AS\n{group_project_sql}"

    stats = {"tables_written": 0, "errors": []}

    for label, sql, table in [
        ("bq_group_billing", create_group_billing, config.bq_output_table_group_billing),
        ("bq_group_project", create_group_project, config.bq_output_table_group_project),
    ]:
        try:
            logger.info("executing_create_or_replace", table=table)
            loader.execute_query(sql)
            stats["tables_written"] += 1
            logger.info("table_written_successfully", table=table)
        except Exception as e:
            logger.error("table_write_failed", table=table, error=str(e))
            stats["errors"].append(str(e))
            raise

    return stats


async def main(country: str, month: str, year: str) -> int:
    configure_logging(log_level="INFO", environment="production")

    try:
        settings = load_country_settings(country)
    except FileNotFoundError as e:
        logger.error("country_config_not_found", error=str(e))
        return 1

    job_config = GetDataJobConfig(
        country=country,
        billing_month=month.zfill(2),
        billing_year=year,
        gcp_project_id=settings.bq_project_id,
        bq_input_dataset=settings.bq_input_dataset,
        bq_output_dataset=settings.bq_transformed_dataset,
    )

    try:
        stats = await run_get_data(job_config)
        logger.info("job_completed_successfully", country=country, stats=stats)
        return 0
    except Exception as e:
        logger.error("job_failed", error=str(e), exc_info=True)
        return 1


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Get Data - BQ cost aggregation job")
    parser.add_argument("--country", required=True, help="Country code (e.g., win_uk)")
    parser.add_argument("--month", required=True, help="Billing month (e.g., 05)")
    parser.add_argument("--year", required=True, help="Billing year (e.g., 2026)")
    args = parser.parse_args()

    exit_code = asyncio.run(main(args.country, args.month, args.year))
    sys.exit(exit_code)
