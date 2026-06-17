"""
Mix and Match - By Project Pipeline

Materializes per-project billing breakdown (Desglosar_Facturas='SI' accounts)
and loads to SF Carga_de_lectura__c + BQ output table.

Usage:
    python -m src.etl.jobs.mix_and_match_by_project --country win_uk --month 05 --year 2026
"""

import asyncio
import sys
from typing import Any

import structlog

from src.config import load_country_settings
from src.etl.extract.salesforce_extractor import SalesforceExtractor
from src.etl.load.bigquery_loader import BigQueryLoader
from src.etl.jobs.mix_and_match_staging import (
    MixAndMatchConfig,
    execute_materialize_query,
    write_to_output_table,
)
from src.utils.logging_config import configure_logging

logger = structlog.get_logger(__name__)


# ───────────────────────────────────────────────────────────────────────────
# SF field mapping (21 fields → Carga_de_lectura__c)
# Derived from Talend tMap_8 → tSalesforceOutput_3
# ───────────────────────────────────────────────────────────────────────────


def _map_project_to_sf(
    row: dict[str, Any], config: MixAndMatchConfig
) -> dict[str, Any]:
    """Map project_new row to Carga_de_lectura__c SF fields."""
    total_gcp = float(row.get("Total_gcp", 0))
    total_gmp = float(row.get("Total_gmp", 0))
    cargo_google = total_gcp + total_gmp

    return {
        "OpportunityId__c": row["OpportunityId__c"],
        "Dominio__c": "",  # Not in by_project SQL output
        "SKU__c": float(row.get("SKU__c", 0)),
        "CurrencyIsoCode__c": row.get("CurrencyIsoCode__c", ""),
        "Margen__c": 0.0,  # Not computed in by_project SQL
        "Cargo_Google__c": cargo_google,
        "Anio__c": float(config.billing_year),
        "Mes__c": float(config.billing_month),
        "Fecha_Inicio__c": config.first_day,
        "Fecha_Fin__c": config.last_day,
        "Importe__c": float(row.get("Importe__c", 0)),
        "Descripcion_del_producto__c": row.get("descripcion", ""),
        "Proyecto__c": row.get("project_id", ""),
        "Margen_gmp_euros__c": 0.0,  # Not computed in by_project SQL
        "Margen_gcp_euros__c": 0.0,  # Not computed in by_project SQL
        "Margen_soporte_euros__c": 0.0,  # Hardcoded 0 (same as Talend)
        "Margen_soporte_maps_euros__c": 0.0,  # Hardcoded 0 (same as Talend)
        "Cargo_Google_Numero__c": cargo_google,
        "Importe_Numero__c": float(row.get("Importe__c", 0)),
        "Cargo_Google_GCP__c": total_gcp,
        "Cargo_Google_GMP__c": total_gmp,
    }


# ───────────────────────────────────────────────────────────────────────────
# Pipeline
# ───────────────────────────────────────────────────────────────────────────


async def run_mix_and_match_by_project(config: MixAndMatchConfig) -> dict[str, Any]:
    """
    Execute mix_and_match by_project pipeline:
      1. Materialize: Execute materialize_importes_by_project.sql → project_new
      2. SF insert: project_new → Carga_de_lectura__c
      3. BQ write: project_new → bq_output_table_flex_desglosadas (DELETE+INSERT)

    Requires staging tables (stg_opportunities, stg_line_items) to exist.
    Run mix_and_match_staging first.
    """
    logger.info(
        "mix_and_match_by_project_start",
        country=config.country,
        invoice_month=config.invoice_month,
    )

    loader = BigQueryLoader(
        project_id=config.gcp_project_id,
        dataset_id=config.bq_transformed_dataset,
    )
    extractor = SalesforceExtractor(
        username=config.sf_user,
        private_key=config.sf_private_key or "",
        client_id=config.sf_client_id or "",
        sandbox=config.sf_sandbox,
    )
    await extractor.connect()

    stats: dict[str, Any] = {
        "project_rows": 0,
        "sf_inserted": 0,
        "sf_errors": 0,
        "bq_written": 0,
    }

    try:
        # Phase 1: Materialize
        execute_materialize_query(config, loader, "materialize_importes_by_project")

        # Phase 2: Read materialized data
        fq_temp = (
            f"`{config.gcp_project_id}"
            f".{config.bq_transformed_dataset}.project_new`"
        )
        data = loader.query_to_dicts(f"SELECT * FROM {fq_temp}")
        stats["project_rows"] = len(data)
        logger.info("project_rows_materialized", count=len(data))

        if not data:
            logger.warning("no_project_data_materialized")
            return stats

        # Phase 3: SF insert
        sf_records = [_map_project_to_sf(row, config) for row in data]
        result = await extractor.insert_records("Carga_de_lectura__c", sf_records)
        stats["sf_inserted"] = result.get("success", 0)
        stats["sf_errors"] = result.get("errors", 0)
        logger.info(
            "project_sf_insert_complete",
            inserted=stats["sf_inserted"],
            errors=stats["sf_errors"],
        )

        # Phase 4: BQ output (DELETE+INSERT by invoice_month)
        stats["bq_written"] = write_to_output_table(
            config, loader, "project_new", config.bq_output_table_flex_desglosadas,
            period_column="invoice_month",
            extra_delete_filter="AND source = 'by_project'",
        )

    finally:
        await extractor.disconnect()

    logger.info("mix_and_match_by_project_complete", stats=stats)
    return stats


async def main(country: str, month: str, year: str) -> int:
    """Main entry point."""
    configure_logging(log_level="INFO", environment="production")

    try:
        settings = load_country_settings(country)
    except FileNotFoundError as e:
        logger.error("country_config_not_found", error=str(e))
        return 1

    config = MixAndMatchConfig(
        country=country,
        billing_month=month.zfill(2),
        billing_year=year,
        gcp_project_id=settings.bq_project_id,
        bq_transformed_dataset=settings.bq_transformed_dataset,
        bq_input_dataset=settings.bq_input_dataset,
        sf_user=settings.sf_user,
        sf_empresa_code=settings.sf_empresa_code,
        sf_stage_name=settings.sf_stage_name,
        sf_skus=settings.sf_skus,
        sf_private_key=settings.sf_private_key,
        sf_client_id=settings.sf_client_id,
        sf_sandbox=settings.sf_sandbox,
        bq_output_table_flex_desglosadas=getattr(
            settings, "bq_output_table_flex_desglosadas", "importes_lecturas_by_project"
        ),
    )

    try:
        await run_mix_and_match_by_project(config)
        return 0
    except Exception as e:
        logger.error("mix_and_match_by_project_failed", error=str(e), exc_info=True)
        return 1


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(
        description="Mix and Match - By Project Pipeline"
    )
    parser.add_argument("--country", required=True, help="Country config (e.g., win_uk)")
    parser.add_argument("--month", required=True, help="Billing month (e.g., 05)")
    parser.add_argument("--year", required=True, help="Billing year (e.g., 2026)")
    args = parser.parse_args()

    exit_code = asyncio.run(main(args.country, args.month, args.year))
    sys.exit(exit_code)
