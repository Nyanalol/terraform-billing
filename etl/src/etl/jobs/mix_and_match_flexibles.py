"""
Mix and Match - Flexibles Pipeline

Materializes flexible billing data and loads to SF Carga_de_lectura__c + BQ output table.

Usage:
    python -m src.etl.jobs.mix_and_match_flexibles --country win_uk --month 05 --year 2026
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
# SF field mapping (20 fields → Carga_de_lectura__c)
# Derived from Talend tMap_3 → tSalesforceOutput_2
# ───────────────────────────────────────────────────────────────────────────


def _map_flex_to_sf(row: dict[str, Any], config: MixAndMatchConfig) -> dict[str, Any]:
    """Map flex_new row to Carga_de_lectura__c SF fields."""
    return {
        "OpportunityId__c": row["OpportunityId__c"],
        "Dominio__c": row.get("Dominio__c", ""),
        "SKU__c": float(row.get("SKU__c", 0)),
        "CurrencyIsoCode__c": row.get("CurrencyIsoCode__c", ""),
        "Margen__c": float(row.get("Margen__c", 0)),
        "Cargo_Google__c": float(row.get("Cargo_Google__c", 0)),
        "Anio__c": float(config.billing_year),
        "Mes__c": float(config.billing_month),
        "Fecha_Inicio__c": config.first_day,
        "Fecha_Fin__c": config.last_day,
        "Importe__c": float(row.get("Importe__c", 0)),
        "Descripcion_del_producto__c": row.get("descripcion", ""),
        "Margen_gcp_euros__c": float(row.get("Margen_gcp_euros", 0)),
        "Margen_gmp_euros__c": float(row.get("Margen_gmp_euros", 0)),
        "Margen_soporte_euros__c": float(row.get("Margen_soporte_euros", 0)),
        "Margen_Soporte_Maps_Euros__c": float(row.get("Margen_soporte_maps_euros", 0)),
        "Cargo_Google_Numero__c": float(row.get("Cargo_Google__c", 0)),
        "Importe_Numero__c": float(row.get("Importe__c", 0)),
        "Cargo_Google_GCP__c": float(row.get("Total_gcp", 0)),
        "Cargo_Google_GMP__c": float(row.get("Total_gmp", 0)),
    }


# ───────────────────────────────────────────────────────────────────────────
# Pipeline
# ───────────────────────────────────────────────────────────────────────────


async def run_mix_and_match_flexibles(config: MixAndMatchConfig) -> dict[str, Any]:
    """
    Execute mix_and_match flexibles pipeline:
      1. Materialize: Execute materialize_importes_flexibles.sql → flex_new
      2. SF insert: flex_new → Carga_de_lectura__c
      3. BQ write: flex_new → bq_output_table_flex (DELETE+INSERT)

    Requires staging tables (stg_opportunities, stg_line_items) to exist.
    Run mix_and_match_staging first.
    """
    logger.info(
        "mix_and_match_flexibles_start",
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
        "flex_rows": 0,
        "sf_inserted": 0,
        "sf_errors": 0,
        "bq_written": 0,
    }

    try:
        # Phase 1: Materialize
        execute_materialize_query(config, loader, "materialize_importes_flexibles")

        # Phase 2: Read materialized data
        fq_temp = (
            f"`{config.gcp_project_id}"
            f".{config.bq_transformed_dataset}.flex_new`"
        )
        data = loader.query_to_dicts(f"SELECT * FROM {fq_temp}")
        stats["flex_rows"] = len(data)
        logger.info("flex_rows_materialized", count=len(data))

        if not data:
            logger.warning("no_flex_data_materialized")
            return stats

        # Phase 3: SF insert (flex_new already has Desglosar='NO' + Importe!=0;
        # Talend SF path uses Importe!=0 which is already guaranteed)
        sf_records = [_map_flex_to_sf(row, config) for row in data]
        if sf_records:
            result = await extractor.insert_records("Carga_de_lectura__c", sf_records)
            stats["sf_inserted"] = result.get("success", 0)
            stats["sf_errors"] = result.get("errors", 0)
        else:
            stats["sf_inserted"] = 0
            stats["sf_errors"] = 0
        logger.info(
            "flex_sf_insert_complete",
            inserted=stats["sf_inserted"],
            errors=stats["sf_errors"],
            total_rows=len(data),
        )

        # Phase 4: BQ output (DELETE+INSERT by invoice_month, only Importe > 0)
        stats["bq_written"] = write_to_output_table(
            config, loader, "flex_new", config.bq_output_table_flex,
            period_column="invoice_month",
            source_where="CAST(Importe__c AS FLOAT64) > 0",
        )

    finally:
        await extractor.disconnect()

    logger.info("mix_and_match_flexibles_complete", stats=stats)
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
        bq_output_table_flex=getattr(
            settings, "bq_output_table_flex", "importes_lecturas_temp"
        ),
    )

    try:
        await run_mix_and_match_flexibles(config)
        return 0
    except Exception as e:
        logger.error("mix_and_match_flexibles_failed", error=str(e), exc_info=True)
        return 1


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(
        description="Mix and Match - Flexibles Pipeline"
    )
    parser.add_argument("--country", required=True, help="Country config (e.g., win_uk)")
    parser.add_argument("--month", required=True, help="Billing month (e.g., 05)")
    parser.add_argument("--year", required=True, help="Billing year (e.g., 2026)")
    args = parser.parse_args()

    exit_code = asyncio.run(main(args.country, args.month, args.year))
    sys.exit(exit_code)
