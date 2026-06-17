"""
Delete Lecturas & Cargas de Lectura by Billing Period

Deletes Carga_de_lectura__c and Lectura__c records matching the billing
period (Anio__c/Mes__c) for the selected country context (filtered by
Empresa_IP__c via Opportunity).

Usage:
    python -m src.etl.jobs.delete_today_lecturas --country win_uk --month 05 --year 2026
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
# SOQL base queries — empresa filter and period are appended dynamically
# ───────────────────────────────────────────────────────────────────────────

_CARGAS_BASE = "SELECT Id FROM Carga_de_lectura__c WHERE Anio__c = {year} AND Mes__c = {month} AND OwnerId = '00520000001crCbAAI'"
_LECTURAS_BASE = "SELECT Id FROM Lectura__c WHERE Anyo__c = {year} AND Mes__c = {month} AND OwnerId = '00520000001crCbAAI'"


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


async def run_delete_today_lecturas(
    settings: Settings, month: str, year: str,
) -> dict[str, Any]:
    """
    Delete Carga_de_lectura__c and Lectura__c records matching the billing
    period (Anio__c/Mes__c) for the configured Empresa_IP__c.

    Also logs orphan records (matching period but missing Opportunity link).
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
        cargas_base = _CARGAS_BASE.format(year=year, month=month)
        cargas_filter = build_empresa_filter(empresa_code, prefix="OpportunityId__r")
        cargas_soql = f"{cargas_base} AND {cargas_filter}"
        cargas_result = await _delete_sf_object(
            extractor, "Carga_de_lectura__c", cargas_soql,
        )
        stats["cargas_found"] = cargas_result["found"]
        stats["cargas_deleted"] = cargas_result["deleted"]
        stats["cargas_errors"] = cargas_result["errors"]

        # Bug #D: detect orphan Cargas (matching period but null Opportunity)
        orphan_cargas_soql = (
            f"{cargas_base} AND OpportunityId__c = null"
        )
        orphan_cargas = await extractor.query(orphan_cargas_soql)
        if orphan_cargas:
            logger.warning(
                "orphan_cargas_detected",
                count=len(orphan_cargas),
                month=month,
                year=year,
            )
            stats["cargas_orphans"] = len(orphan_cargas)

        # 2. Delete Lectura__c
        lecturas_base = _LECTURAS_BASE.format(year=year, month=month)
        lecturas_filter = build_empresa_filter(empresa_code, prefix="Oportunidad__r")
        lecturas_soql = f"{lecturas_base} AND {lecturas_filter}"
        lecturas_result = await _delete_sf_object(
            extractor, "Lectura__c", lecturas_soql,
        )
        stats["lecturas_found"] = lecturas_result["found"]
        stats["lecturas_deleted"] = lecturas_result["deleted"]
        stats["lecturas_errors"] = lecturas_result["errors"]

        # Bug #D: detect orphan Lecturas (matching period but null Opportunity)
        orphan_lecturas_soql = (
            f"{lecturas_base} AND Oportunidad__c = null"
        )
        orphan_lecturas = await extractor.query(orphan_lecturas_soql)
        if orphan_lecturas:
            logger.warning(
                "orphan_lecturas_detected",
                count=len(orphan_lecturas),
                month=month,
                year=year,
            )
            stats["lecturas_orphans"] = len(orphan_lecturas)

    finally:
        await extractor.disconnect()

    return stats


# ───────────────────────────────────────────────────────────────────────────
# Entry point
# ───────────────────────────────────────────────────────────────────────────


async def main(country: str, month: str, year: str) -> int:
    """Main entry point."""
    configure_logging(log_level="INFO", environment="production")

    try:
        settings = load_country_settings(country)
    except FileNotFoundError as e:
        logger.error("country_config_not_found", error=str(e))
        return 1

    logger.info(
        "delete_lecturas_start", country=country, month=month, year=year,
    )
    stats = await run_delete_today_lecturas(settings, month=month, year=year)
    logger.info("delete_lecturas_complete", **stats)

    total_errors = stats.get("cargas_errors", 0) + stats.get("lecturas_errors", 0)
    if total_errors > 0:
        logger.warning("delete_had_errors", stats=stats)
        return 1
    return 0


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(
        description="Delete Lectura and Carga de lectura records by billing period",
    )
    parser.add_argument(
        "--country",
        type=str,
        required=True,
        help="Country code (e.g., win_uk, win_es)",
    )
    parser.add_argument(
        "--month",
        type=str,
        required=True,
        help="Billing month (e.g., 05)",
    )
    parser.add_argument(
        "--year",
        type=str,
        required=True,
        help="Billing year (e.g., 2026)",
    )
    args = parser.parse_args()
    sys.exit(asyncio.run(main(args.country, args.month, args.year)))
