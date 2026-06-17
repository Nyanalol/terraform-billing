"""Main orchestration entry point for ETL jobs."""

import os
import sys
import asyncio
from typing import Optional

import structlog
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

from src.utils.logging_config import configure_logging
from src.etl.jobs.get_billing_accounts import main as run_billing_accounts_job
from src.etl.jobs.get_currencies_exchange_rates import main as run_currencies_job
from src.etl.jobs.get_data import main as run_get_data_job
from src.etl.jobs.workspace_reseller_pipeline import main as run_workspace_reseller_pipeline_job
from src.etl.jobs.mix_and_match_staging import main as run_mix_and_match_staging_job
from src.etl.jobs.mix_and_match_flexibles import main as run_mix_and_match_flexibles_job
from src.etl.jobs.mix_and_match_by_project import main as run_mix_and_match_by_project_job
from src.etl.jobs.mix_and_match_soporte import main as run_mix_and_match_soporte_job
from src.etl.jobs.delete_today_lecturas import main as run_delete_today_lecturas_job

logger = structlog.get_logger(__name__)


async def run_all(country: str, month: int, year: int) -> int:
    """
    Run all ETL jobs in the correct order for a country/period.

    Order:
      1. get_billing_accounts
      2. get_currencies_exchange_rates
      3. get_data
      4. mix_and_match_staging
      5. mix_and_match_flexibles
      6. mix_and_match_by_project
      7. mix_and_match_soporte
      8. workspace_reseller

    Stops on first failure.
    """
    configure_logging(log_level="INFO", environment="production")

    mm = str(month).zfill(2)
    yr = str(year)

    steps: list[tuple[str, any]] = [
        ("get_billing_accounts", lambda: run_billing_accounts_job(country, month, year)),
        ("get_currencies_exchange_rates", lambda: run_currencies_job(country, mm, yr)),
        ("get_data", lambda: run_get_data_job(country, mm, yr)),
        ("mix_and_match_staging", lambda: run_mix_and_match_staging_job(country)),
        ("mix_and_match_flexibles", lambda: run_mix_and_match_flexibles_job(country, mm, yr)),
        ("mix_and_match_by_project", lambda: run_mix_and_match_by_project_job(country, mm, yr)),
        ("mix_and_match_soporte", lambda: run_mix_and_match_soporte_job(country, mm, yr)),
        ("workspace_reseller", lambda: run_workspace_reseller_pipeline_job(country, mm, yr)),
    ]

    logger.info(
        "run_all_start",
        country=country,
        billing_period=f"{mm}/{yr}",
        total_steps=len(steps),
    )

    for i, (name, fn) in enumerate(steps, 1):
        logger.info("step_start", step=f"{i}/{len(steps)}", job=name)
        try:
            rc = await fn()
        except Exception as e:
            logger.error("step_failed_exception", job=name, error=str(e))
            return 1

        if rc != 0:
            logger.error("step_failed", job=name, exit_code=rc)
            return 1

        logger.info("step_complete", step=f"{i}/{len(steps)}", job=name)

    logger.info("run_all_complete", country=country, billing_period=f"{mm}/{yr}")
    return 0


async def run_job(job_name: str, country: str, month: int, year: int) -> int:
    """
    Run an ETL job for a specific country.

    Args:
        job_name: Name of the job to run (e.g., 'get_billing_accounts')
        country: Country code (e.g., 'win_uk', 'win_es')
        month: Billing month (1-12)
        year: Billing year

    Returns:
        Exit code (0 = success, 1 = failure)
    """
    configure_logging(log_level="INFO", environment="production")

    logger.info(
        "starting_etl_job",
        job_name=job_name,
        country=country,
        billing_period=f"{month:02d}/{year}",
    )

    try:
        if job_name == "run_all":
            return await run_all(country, month, year)
        elif job_name == "get_billing_accounts":
            return await run_billing_accounts_job(country, month, year)
        elif job_name == "get_currencies_exchange_rates":
            return await run_currencies_job(
                country, str(month).zfill(2), str(year)
            )
        elif job_name == "get_data":
            return await run_get_data_job(
                country, str(month).zfill(2), str(year)
            )
        elif job_name in ("workspace_reseller", "workspace_reseller_pipeline"):
            return await run_workspace_reseller_pipeline_job(
                country, str(month).zfill(2), str(year)
            )
        elif job_name == "mix_and_match_staging":
            return await run_mix_and_match_staging_job(country)
        elif job_name == "mix_and_match_flexibles":
            return await run_mix_and_match_flexibles_job(
                country, str(month).zfill(2), str(year)
            )
        elif job_name == "mix_and_match_by_project":
            return await run_mix_and_match_by_project_job(
                country, str(month).zfill(2), str(year)
            )
        elif job_name == "mix_and_match_soporte":
            return await run_mix_and_match_soporte_job(
                country, str(month).zfill(2), str(year)
            )
        elif job_name == "delete_today_lecturas":
            return await run_delete_today_lecturas_job(
                country, str(month).zfill(2), str(year)
            )
        else:
            logger.error("unknown_job", job_name=job_name)
            return 1

    except Exception as e:
        logger.error("job_execution_failed", job_name=job_name, error=str(e))
        return 1


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Billing ETL job orchestrator")
    parser.add_argument(
        "--job",
        type=str,
        default="get_billing_accounts",
        help="Job name (run_all, get_billing_accounts, get_currencies_exchange_rates, "
        "get_data, workspace_reseller_pipeline, mix_and_match_staging, "
        "mix_and_match_flexibles, mix_and_match_by_project, mix_and_match_soporte, "
        "delete_today_lecturas)",
    )
    parser.add_argument(
        "--country",
        type=str,
        required=True,
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

    exit_code = asyncio.run(run_job(args.job, args.country, args.month, args.year))
    sys.exit(exit_code)
