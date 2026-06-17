"""
Billing Accounts ETL job - Extract from Salesforce, Load to BigQuery, Materialize with backups.

This script:
1. Extracts billing accounts and opportunities from Salesforce
2. Loads them as raw data to BigQuery staging tables (per country)
3. Creates backup of current data, then materializes to final tables (TRUNCATE + INSERT)

Usage:
    python -m src.etl.jobs.get_billing_accounts --country win_uk --month 5 --year 2026
"""

import asyncio
import sys
from pathlib import Path
from typing import Optional
from string import Template
from datetime import datetime

import structlog
from pydantic import BaseModel, ConfigDict

from src.config import load_country_settings
from src.utils import build_empresa_filter
from src.utils.logging_config import configure_logging
from src.etl.extract.salesforce_extractor import SalesforceExtractor
from src.etl.load.bigquery_loader import BigQueryLoader

logger = structlog.get_logger(__name__)


class BillingAccountsJobConfig(BaseModel):
    """Configuration for Billing Accounts extraction job."""

    country: str
    billing_month: int
    billing_year: int

    # Loaded from .env.{country}
    gcp_project_id: str
    bq_raw_dataset: str
    bq_transformed_dataset: str
    sf_user: str
    sf_empresa_code: str
    sf_stage_name: str
    sf_skus: str
    sf_private_key: Optional[str] = None
    sf_client_id: Optional[str] = None
    sf_sandbox: bool = False

    # Output tables
    bq_output_table_billing_accounts: str = "billing_accounts"
    bq_output_table_billing_accounts_full: str = "billing_accounts_full"

    # Rendered queries
    sf_opp_query: str = ""
    sf_n_a_query: str = ""
    sf_all_opp_query: str = ""

    model_config = ConfigDict(extra="ignore")


def _load_query_template(query_name: str) -> str:
    """
    Load query template from file.

    Args:
        query_name: Query name (e.g., 'opportunities', 'line_items')

    Returns:
        Query template content with placeholders

    Raises:
        FileNotFoundError: If query file doesn't exist
    """
    base_path = Path(__file__).parent.parent.parent.parent
    query_file = base_path / "config" / "queries" / f"{query_name}.sql"

    if not query_file.exists():
        raise FileNotFoundError(f"Query template not found: {query_file}")

    with open(query_file, "r") as f:
        return f.read().strip()


def _render_query(template: str, **kwargs) -> str:
    """
    Render query template with parameters.

    Args:
        template: SQL template with {placeholders}
        **kwargs: Parameter values to substitute

    Returns:
        Rendered SQL query stripped of SQL comments
    """
    try:
        rendered = _strip_sql_comments(template).format_map(kwargs)
    except KeyError as e:
        raise ValueError(f"Missing query parameter: {e}")
    return rendered


def _strip_sql_comments(sql: str) -> str:
    """Remove SQL -- comments and blank lines from a query."""
    lines = []
    for line in sql.splitlines():
        stripped = line.strip()
        if stripped.startswith("--") or not stripped:
            continue
        # Remove inline trailing comments
        if " --" in line:
            line = line[:line.index(" --")]
        lines.append(line.rstrip())
    return " ".join(lines)


async def extract_and_load_billing_accounts(
    config: BillingAccountsJobConfig,
) -> dict:
    """
    Extract billing accounts from Salesforce and load to BigQuery.

    Args:
        config: Job configuration

    Returns:
        Dictionary with extraction statistics
    """
    logger.info(
        "starting_billing_accounts_extraction",
        country=config.country,
        month=config.billing_month,
        year=config.billing_year,
        project=config.gcp_project_id,
        dataset=config.bq_raw_dataset,
    )

    # Initialize clients
    extractor = SalesforceExtractor(
        username=config.sf_user,
        private_key=config.sf_private_key or "",
        client_id=config.sf_client_id or "",
        sandbox=config.sf_sandbox,
    )

    loader = BigQueryLoader(
        project_id=config.gcp_project_id,
        dataset_id=config.bq_raw_dataset,
    )

    # Ensure dataset exists
    loader.ensure_dataset_exists()

    stats = {
        "country": config.country,
        "billing_period": f"{config.billing_month:02d}/{config.billing_year}",
        "opportunities_extracted": 0,
        "opportunities_n_a_extracted": 0,
        "all_opportunities_extracted": 0,
        "tables_loaded": 0,
        "errors": [],
    }

    try:
        # Connect to Salesforce
        await extractor.connect()

        # Log rendered queries (first 200 chars for debugging)
        logger.info(
            "executing_parallel_salesforce_queries",
            country=config.country,
            opp_query_preview=config.sf_opp_query[:200],
        )

        # Execute 3 parallel queries
        queries = {
            "opportunities": config.sf_opp_query,
            "opportunities_n_a": config.sf_n_a_query,
            "all_opportunities": config.sf_all_opp_query,
        }

        results = await extractor.extract_multiple_parallel(queries)

        # Load to BigQuery
        logger.info(
            "loading_extracted_data_to_bigquery",
            country=config.country,
            tables_count=len([r for r in results.values() if r]),
        )

        if results["opportunities"]:
            loader.load_raw_data(
                table_name="raw_opportunities",
                data=results["opportunities"],
                write_disposition="WRITE_TRUNCATE",
            )
            stats["opportunities_extracted"] = len(results["opportunities"])
            stats["tables_loaded"] += 1
            logger.info(
                "opportunities_loaded",
                country=config.country,
                count=len(results["opportunities"]),
                table="raw_opportunities",
            )

        if results["opportunities_n_a"]:
            loader.load_raw_data(
                table_name="raw_n_a_opportunities",
                data=results["opportunities_n_a"],
                write_disposition="WRITE_TRUNCATE",
            )
            stats["opportunities_n_a_extracted"] = len(results["opportunities_n_a"])
            stats["tables_loaded"] += 1
            logger.info(
                "opportunities_n_a_loaded",
                country=config.country,
                count=len(results["opportunities_n_a"]),
                table="raw_n_a_opportunities",
            )

        if results["all_opportunities"]:
            loader.load_raw_data(
                table_name="raw_all_opportunities",
                data=results["all_opportunities"],
                write_disposition="WRITE_TRUNCATE",
            )
            stats["all_opportunities_extracted"] = len(results["all_opportunities"])
            stats["tables_loaded"] += 1
            logger.info(
                "all_opportunities_loaded",
                country=config.country,
                count=len(results["all_opportunities"]),
                table="raw_all_opportunities",
            )

        logger.info(
            "billing_accounts_extraction_completed",
            country=config.country,
            stats=stats,
        )

    except Exception as e:
        logger.error("extraction_failed", country=config.country, error=str(e))
        stats["errors"].append(str(e))
        raise

    finally:
        await extractor.disconnect()

    return stats


async def materialize_billing_accounts(
    config: BillingAccountsJobConfig,
    loader: BigQueryLoader,
) -> dict:
    """
    Materialize raw data to final tables with backup.

    Creates backup of current data, then truncates and reloads with new data.

    Args:
        config: Job configuration
        loader: BigQueryLoader instance

    Returns:
        Dictionary with materialization statistics
    """
    logger.info(
        "starting_materialization",
        country=config.country,
        month=config.billing_month,
        year=config.billing_year,
        dataset=config.bq_transformed_dataset,
    )

    stats = {
        "billing_accounts_materialized": False,
        "billing_accounts_full_materialized": False,
        "backup_timestamp": None,
        "errors": [],
    }

    try:
        # Generate backup timestamp (YYYYMMDD)
        backup_timestamp = datetime.now().strftime("%Y%m%d")
        stats["backup_timestamp"] = backup_timestamp

        logger.info(
            "backup_timestamp_generated",
            timestamp=backup_timestamp,
        )

        # Load materialization query templates
        materialize_template = _load_query_template("materialize_billing_accounts")
        materialize_full_template = _load_query_template(
            "materialize_billing_accounts_full"
        )

        # Format and execute billing_accounts materialization
        materialize_query = materialize_template.format(
            project=config.gcp_project_id,
            raw_dataset=config.bq_raw_dataset,
            transformed_dataset=config.bq_transformed_dataset,
            table_name=config.bq_output_table_billing_accounts,
            backup_timestamp=backup_timestamp,
        )

        # Split by SQL statements
        materialize_statements = [
            stmt.strip() for stmt in materialize_query.split(";") if stmt.strip()
        ]

        logger.info(
            "materializing_billing_accounts",
            table=config.bq_output_table_billing_accounts,
            backup_table=f"{config.bq_output_table_billing_accounts}_backup_{backup_timestamp}",
            statements_count=len(materialize_statements),
        )

        for i, stmt in enumerate(materialize_statements):
            logger.debug(
                "executing_materialization_statement",
                table=config.bq_output_table_billing_accounts,
                statement_index=i + 1,
            )
            try:
                loader.execute_query(stmt)
            except Exception as e:
                if i == 0 and "Not found" in str(e):
                    logger.warning("backup_skipped_table_not_exist", table=config.bq_output_table_billing_accounts)
                else:
                    raise

        stats["billing_accounts_materialized"] = True

        # Format and execute billing_accounts_full materialization
        materialize_full_query = materialize_full_template.format(
            project=config.gcp_project_id,
            raw_dataset=config.bq_raw_dataset,
            transformed_dataset=config.bq_transformed_dataset,
            table_name=config.bq_output_table_billing_accounts_full,
            backup_timestamp=backup_timestamp,
        )

        materialize_full_statements = [
            stmt.strip() for stmt in materialize_full_query.split(";") if stmt.strip()
        ]

        logger.info(
            "materializing_billing_accounts_full",
            table=config.bq_output_table_billing_accounts_full,
            backup_table=f"{config.bq_output_table_billing_accounts_full}_backup_{backup_timestamp}",
            statements_count=len(materialize_full_statements),
        )

        for i, stmt in enumerate(materialize_full_statements):
            logger.debug(
                "executing_materialization_statement",
                table=config.bq_output_table_billing_accounts_full,
                statement_index=i + 1,
            )
            try:
                loader.execute_query(stmt)
            except Exception as e:
                if i == 0 and "Not found" in str(e):
                    logger.warning("backup_skipped_table_not_exist", table=config.bq_output_table_billing_accounts_full)
                else:
                    raise

        stats["billing_accounts_full_materialized"] = True

        logger.info(
            "materialization_completed",
            country=config.country,
            backup_timestamp=backup_timestamp,
            stats=stats,
        )

    except Exception as e:
        logger.error(
            "materialization_failed",
            country=config.country,
            error=str(e),
        )
        stats["errors"].append(str(e))
        raise

    return stats


async def main(
    country: str,
    month: int,
    year: int,
) -> int:
    """
    Main entry point for job execution.

    Args:
        country: Country code (e.g., 'win_uk', 'win_es')
        month: Billing month (1-12)
        year: Billing year (e.g., 2026)

    Returns:
        Exit code (0 = success, 1 = failure)
    """
    configure_logging(log_level="INFO", environment="production")

    try:
        # Load country-specific settings
        try:
            settings = load_country_settings(country)
        except FileNotFoundError as e:
            logger.error("country_config_not_found", error=str(e))
            return 1
        except ValueError as e:
            logger.error("country_settings_error", error=str(e))
            return 1

        # Load query templates
        try:
            opp_template = _load_query_template("opportunities")
            all_opp_template = _load_query_template("all_opportunities")
            n_a_template = _load_query_template("billing_accounts_n_a")
        except FileNotFoundError as e:
            logger.error("query_template_not_found", error=str(e))
            return 1

        # Render queries with parameters
        try:
            opp_query = _render_query(
                opp_template,
                empresa_filter=build_empresa_filter(settings.sf_empresa_code),
                stage_name=settings.sf_stage_name,
            )
            all_opp_query = _render_query(
                all_opp_template,
                empresa_filter=build_empresa_filter(settings.sf_empresa_code),
                stage_name=settings.sf_stage_name,
            )
            n_a_query = _strip_sql_comments(n_a_template)
        except ValueError as e:
            logger.error("query_rendering_failed", error=str(e))
            return 1

        # Build job config
        job_config = BillingAccountsJobConfig(
            country=country,
            billing_month=month,
            billing_year=year,
            gcp_project_id=settings.bq_project_id,
            bq_raw_dataset=settings.bq_raw_dataset,
            bq_transformed_dataset=settings.bq_transformed_dataset,
            sf_user=settings.sf_user,
            sf_empresa_code=settings.sf_empresa_code,
            sf_stage_name=settings.sf_stage_name,
            sf_skus=settings.sf_skus,
            sf_private_key=settings.sf_private_key,
            sf_client_id=settings.sf_client_id,
            sf_sandbox=settings.sf_sandbox,
            bq_output_table_billing_accounts=settings.bq_output_table_billing_accounts,
            bq_output_table_billing_accounts_full=settings.bq_output_table_billing_accounts_full,
            sf_opp_query=opp_query,
            sf_n_a_query=n_a_query,
            sf_all_opp_query=all_opp_query,
        )

        # Run extraction
        stats = await extract_and_load_billing_accounts(job_config)

        # Run materialization
        loader = BigQueryLoader(
            project_id=settings.bq_project_id,
            dataset_id=settings.bq_transformed_dataset,
        )
        loader.ensure_dataset_exists()
        materialize_stats = await materialize_billing_accounts(job_config, loader)

        stats["materialization"] = materialize_stats

        logger.info("job_completed_successfully", country=country, stats=stats)
        return 0

    except Exception as e:
        logger.error("job_failed", error=str(e), exc_info=True)
        return 1


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(
        description="Extract billing accounts from Salesforce to BigQuery"
    )
    parser.add_argument(
        "--country",
        type=str,
        default="win_uk",
        help="Country code (e.g., win_uk, win_es, win_ar)",
    )
    parser.add_argument(
        "--month",
        type=int,
        required=True,
        help="Billing month (1-12)",
    )
    parser.add_argument(
        "--year",
        type=int,
        required=True,
        help="Billing year (e.g., 2026)",
    )

    args = parser.parse_args()

    # Validate month
    if not 1 <= args.month <= 12:
        print("Error: month must be between 1 and 12")
        sys.exit(1)

    exit_code = asyncio.run(main(args.country, args.month, args.year))
    sys.exit(exit_code)
