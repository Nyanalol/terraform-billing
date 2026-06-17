"""
Delete Today's Lecturas & Cargas de Lectura

Deletes Carga_de_lectura__c and Lectura__c records created today
for the selected country context (filtered by Empresa_IP__c via Opportunity).

Usage:
    python -m src.etl.jobs.delete_today_lecturas --country win_uk
"""

import asyncio
import sys
from typing import Any

import structlog

from src.config import load_country_settings, Settings
from src.utils import build_empresa_filter
from src.etl.extract.salesforce_extractor import SalesforceExtractor
from src.utils.logging_config import configure_logging

logger = structlog.get_logger(__name__)


# ───────────────────────────────────────────────────────────────────────────
# SOQL base queries — empresa filter is appended dynamically
# ───────────────────────────────────────────────────────────────────────────

_CARGAS_BASE = "SELECT Id FROM Carga_de_lectura__c WHERE CreatedDate = TODAY"
_LECTURAS_BASE = "SELECT Id FROM Lectura__c WHERE CreatedDate = TODAY"


# ───────────────────────────────────────────────────────────────────────────
# Pipeline
# ───────────────────────────────────────────────────────────────────────────


async def _delete_sf_object(
    extractor: SalesforceExtractor,
    object_name: str,
    soql: str,
) -> dict[str, int]:
    """Query and delete records for a single SF object."""
    records = await extractor.query(soql)
    record_ids = [r["Id"] for r in records]
    found = len(record_ids)

    logger.info(
        "records_found_for_deletion",
        object_name=object_name,
        count=found,
    )

    if not record_ids:
        return {"found": 0, "deleted": 0, "errors": 0}

    result = await extractor.delete_records(object_name, record_ids)
    return {
        "found": found,
        "deleted": result["success"],
        "errors": result["errors"],
    }


async def run_delete_today_lecturas(settings: Settings) -> dict[str, Any]:
    """
    Delete today's Carga_de_lectura__c and Lectura__c records
    for the configured Empresa_IP__c.
    """
    extractor = SalesforceExtractor(
        username=settings.sf_user,
        private_key=settings.sf_private_key or "",
        client_id=settings.sf_client_id or "",
        sandbox=settings.sf_sandbox,
    )
    await extractor.connect()

    stats: dict[str, Any] = {}

    try:
        empresa_code = settings.sf_empresa_code

        # 1. Delete Carga_de_lectura__c
        cargas_filter = build_empresa_filter(empresa_code, prefix="OpportunityId__r")
        cargas_soql = f"{_CARGAS_BASE} AND {cargas_filter}"
        cargas_result = await _delete_sf_object(
            extractor, "Carga_de_lectura__c", cargas_soql,
        )
        stats["cargas_found"] = cargas_result["found"]
        stats["cargas_deleted"] = cargas_result["deleted"]
        stats["cargas_errors"] = cargas_result["errors"]

        # 2. Delete Lectura__c
        lecturas_filter = build_empresa_filter(empresa_code, prefix="Oportunidad__r")
        lecturas_soql = f"{_LECTURAS_BASE} AND {lecturas_filter}"
        lecturas_result = await _delete_sf_object(
            extractor, "Lectura__c", lecturas_soql,
        )
        stats["lecturas_found"] = lecturas_result["found"]
        stats["lecturas_deleted"] = lecturas_result["deleted"]
        stats["lecturas_errors"] = lecturas_result["errors"]

    finally:
        await extractor.disconnect()

    return stats


# ───────────────────────────────────────────────────────────────────────────
# Entry point
# ───────────────────────────────────────────────────────────────────────────


async def main(country: str) -> int:
    """Main entry point."""
    configure_logging(log_level="INFO", environment="production")

    try:
        settings = load_country_settings(country)
    except FileNotFoundError as e:
        logger.error("country_config_not_found", error=str(e))
        return 1

    logger.info("delete_today_lecturas_start", country=country)
    stats = await run_delete_today_lecturas(settings)
    logger.info("delete_today_lecturas_complete", **stats)

    total_errors = stats.get("cargas_errors", 0) + stats.get("lecturas_errors", 0)
    if total_errors > 0:
        logger.warning("delete_had_errors", stats=stats)
        return 1
    return 0


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(
        description="Delete today's Lectura and Carga de lectura records",
    )
    parser.add_argument(
        "--country",
        type=str,
        required=True,
        help="Country code (e.g., win_uk, win_es)",
    )
    args = parser.parse_args()
    sys.exit(asyncio.run(main(args.country)))
