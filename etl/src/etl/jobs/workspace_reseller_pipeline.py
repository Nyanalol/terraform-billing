"""
Workspace Reseller Pipeline - Unified ETL Job

Combines:
  1. get_data_workspace: Extract reseller_view from BQ, stage to bq_workspace_reseller
  2. workspace_reseller: Transform staged data, insert to SF Lectura__c

This is the primary entry point for workspace reseller billing data processing.

Usage:
    python -m src.etl.jobs.workspace_reseller_pipeline --country win_uk --month 05 --year 2026
    
Orchestrator equivalent:
    await run_workspace_reseller_pipeline(country='uk', month='05', year='2026')
"""

import asyncio
import sys
from calendar import monthrange
from datetime import date, datetime
from pathlib import Path
from typing import Any, Optional

import structlog
from pydantic import BaseModel, ConfigDict

from src.config import load_country_settings
from src.utils import build_empresa_filter
from src.etl.extract.salesforce_extractor import SalesforceExtractor
from src.etl.load.bigquery_loader import BigQueryLoader
from src.utils.logging_config import configure_logging

logger = structlog.get_logger(__name__)


class WorkspaceResellerPipelineConfig(BaseModel):
    """Configuration for unified Workspace Reseller pipeline."""

    country: str
    billing_month: str  # zero-padded e.g. "05"
    billing_year: str  # e.g. "2026"

    # BigQuery - Read (staging input)
    gcp_project_id: str
    bq_workspace_dataset: str  # workspace dataset (reseller_view source)

    # BigQuery - Write (staging output & transform input)
    bq_transformed_dataset: str
    bq_workspace_reseller_table: str = "bq_workspace_reseller"
    bq_importes_lecturas_table: str = "importes_lecturas_workspace"

    # Salesforce
    sf_user: str
    sf_empresa_code: str
    sf_stage_name: str = "Cerrada ganada"
    sf_private_key: Optional[str] = None
    sf_client_id: Optional[str] = None
    sf_sandbox: bool = False

    model_config = ConfigDict(extra="ignore")


# ───────────────────────────────────────────────────────────────────────────
# PHASE 1: STAGING (get_data_workspace logic)
# ───────────────────────────────────────────────────────────────────────────


def _load_query_template(query_name: str) -> str:
    """Load SQL query template from config/queries."""
    base_path = Path(__file__).parent.parent.parent.parent
    query_file = base_path / "config" / "queries" / f"{query_name}.sql"
    if not query_file.exists():
        raise FileNotFoundError(f"Query template not found: {query_file}")
    with open(query_file, "r") as f:
        return f.read().strip()


def stage_reseller_view_to_bq(
    config: WorkspaceResellerPipelineConfig,
    loader: BigQueryLoader,
) -> int:
    """
    PHASE 1: Stage reseller_view data to bq_workspace_reseller table.
    
    Equivalent to get_data_workspace job.
    
    Returns:
        Number of rows written to staging table
    """
    logger.info(
        "phase_1_staging_start",
        workspace_dataset=config.bq_workspace_dataset,
        output_table=config.bq_workspace_reseller_table,
    )

    loader.ensure_dataset_exists()

    template = _load_query_template("get_data_workspace_reseller")
    select_sql = template.format_map(
        dict(
            project=config.gcp_project_id,
            workspace_dataset=config.bq_workspace_dataset,
            year=config.billing_year,
            month=config.billing_month,
        )
    )

    output_table = (
        f"`{config.gcp_project_id}."
        f"{config.bq_transformed_dataset}."
        f"{config.bq_workspace_reseller_table}`"
    )
    create_sql = f"CREATE OR REPLACE TABLE {output_table} AS\n{select_sql}"

    logger.info("phase_1_executing_create_or_replace", table=config.bq_workspace_reseller_table)
    query_job = loader.execute_query(create_sql)
    rows_affected = query_job.num_dml_affected_rows or 0

    if rows_affected == 0:
        logger.warning(
            "phase_1_no_reseller_view_data",
            warning_code=42,
            country=config.country,
            invoice_month=f"{config.billing_year}{config.billing_month}",
        )
    else:
        logger.info("phase_1_staging_complete", rows=rows_affected)

    return rows_affected


# ───────────────────────────────────────────────────────────────────────────
# PHASE 2: TRANSFORMATION & LOAD (workspace_reseller logic)
# ───────────────────────────────────────────────────────────────────────────


def _build_opportunity_query(empresa_code: str) -> str:
    """Build SOQL query for flexible, active, won opportunities."""
    empresa_filter = build_empresa_filter(empresa_code)
    return (
        "SELECT Id FROM Opportunity "
        "WHERE StageName = 'Cerrada ganada' "
        "AND Estado_del_contrato__c = 'Activado' "
        "AND RecordTypeName__c = 'Op Flexible' "
        "AND Linea_negocio_Intelligence_Partner__c IN "
        "('Google Cloud Services', 'Google Apps') "
        f"AND {empresa_filter}"
    )


def _build_line_items_query(year: str, month: str) -> str:
    """Build SOQL query for opportunity line items within billing period."""
    year_int = int(year)
    month_int = int(month)
    last_day = monthrange(year_int, month_int)[1]

    start_date = f"{year}-{month}-01"
    end_date = f"{year}-{month}-{last_day:02d}"

    return (
        "SELECT sku__c, dominio__c, OpportunityId "
        "FROM OpportunityLineItem "
        f"WHERE (Fecha_Fin_Contrato_Opp__c = NULL "
        f"OR Fecha_Fin_Contrato_Opp__c >= {start_date}) "
        f"AND Fecha_Inicio_Contrato_Opp__c <= {end_date}"
    )


def _build_excluded_query() -> str:
    """Build SOQL query for excluded billing domains."""
    return "SELECT Dominio__c, SKU2__c FROM GwsExcludedBilling__c"


def _clean_sku(value: Any) -> str:
    """Remove trailing '.0' from SKU values."""
    if value is None:
        return ""
    return str(value).replace(".0", "")


def _build_description(row: dict[str, Any]) -> str:
    """Build description string from BQ row."""
    return (
        f"Usage of {row.get('usage_amount', '')} seats, "
        f"Order:{row.get('order_id', '')}, "
        f"{row.get('domain_name', '')}, "
        f"{row.get('service_description', '')}-"
        f"{row.get('sku_description', '')} | "
        f"{row.get('usage_type', '')}"
    )


def _serialize_for_sf(record: dict[str, Any]) -> dict[str, Any]:
    """Serialize Python types to SF-compatible values."""
    output: dict[str, Any] = {}
    for key, value in record.items():
        if isinstance(value, datetime):
            output[key] = value.strftime("%Y-%m-%dT%H:%M:%S.000Z")
        elif isinstance(value, date):
            output[key] = value.isoformat()
        else:
            output[key] = value
    return output


_SF_LECTURA_COLUMNS = {
    "Cargo_Google__c",
    "Descripcion__c",
    "Definicion_del_producto__c",
    "Fecha_Inicio__c",
    "Fecha_Fin__c",
    "Dominio__c",
    "Anyo__c",
    "Mes__c",
    "CurrencyIsoCode",
    "SKU2__c",
    "Oportunidad__c",
    "Order_Number__c",
}


async def transform_and_load_to_sf(
    config: WorkspaceResellerPipelineConfig,
    loader: BigQueryLoader,
    extractor: SalesforceExtractor,
    staged_rows: int,
) -> dict[str, Any]:
    """
    PHASE 2: Transform staged data and load to Salesforce Lectura__c.
    
    Equivalent to workspace_reseller job.
    
    Returns:
        Dictionary with transformation & load statistics
    """
    logger.info("phase_2_transform_start")

    stats: dict[str, Any] = {
        "bq_rows_read": staged_rows,
        "sf_opportunities": 0,
        "sf_line_items": 0,
        "sf_excluded": 0,
        "pass_count": 0,
        "reject_count": 0,
        "na_count": 0,
        "sf_inserted": 0,
        "sf_insert_errors": 0,
        "bq_importes_written": 0,
    }

    if staged_rows == 0:
        logger.warning("phase_2_skipped_no_staged_data")
        return stats

    # Read staged data from BQ
    bq_table = (
        f"`{config.gcp_project_id}"
        f".{config.bq_transformed_dataset}"
        f".{config.bq_workspace_reseller_table}`"
    )
    bq_data = loader.query_to_dicts(f"SELECT * FROM {bq_table}")
    logger.info("phase_2_staged_data_loaded", rows=len(bq_data))

    # Extract from Salesforce in parallel
    sf_results = await extractor.extract_multiple_parallel(
        {
            "opportunities": _build_opportunity_query(config.sf_empresa_code),
            "line_items": _build_line_items_query(config.billing_year, config.billing_month),
            "excluded": _build_excluded_query(),
        }
    )

    opportunities = sf_results["opportunities"]
    line_items = sf_results["line_items"]
    excluded_billing = sf_results["excluded"]

    stats["sf_opportunities"] = len(opportunities)
    stats["sf_line_items"] = len(line_items)
    stats["sf_excluded"] = len(excluded_billing)

    logger.info(
        "phase_2_salesforce_data_extracted",
        opportunities=len(opportunities),
        line_items=len(line_items),
        excluded=len(excluded_billing),
    )

    # Transform: Clean SKUs
    for item in line_items:
        item["sku__c"] = _clean_sku(item.get("sku__c"))
    for item in excluded_billing:
        item["SKU2__c"] = _clean_sku(item.get("SKU2__c"))

    # Transform: Build opportunity lookup
    valid_opp_ids: set[str] = {opp["Id"] for opp in opportunities if "Id" in opp}
    opportunity_lookup: dict[tuple[str, str], str] = {}
    for item in line_items:
        opp_id = item.get("OpportunityId", "")
        if opp_id in valid_opp_ids:
            key = (item.get("sku__c", ""), item.get("dominio__c", ""))
            if key not in opportunity_lookup:
                opportunity_lookup[key] = opp_id

    logger.info("phase_2_opportunity_lookup_built", entries=len(opportunity_lookup))

    # Transform: Cross-reference and classify
    pass_records = []
    reject_records = []

    for row in bq_data:
        sku_sf = str(row.get("sku_sf", ""))
        domain_name = str(row.get("domain_name", ""))
        invoice_month = str(row.get("invoice_month", ""))
        description = _build_description(row)

        opp_id = opportunity_lookup.get((sku_sf, domain_name))

        usage_type = str(row.get("usage_type", ""))

        base_record = {
            "Cargo_Google__c": row.get("google_charge"),
            "Descripcion__c": description,
            "Definicion_del_producto__c": description,
            "Fecha_Inicio__c": row.get("usage_start_time"),
            "Fecha_Fin__c": row.get("usage_end_time"),
            "Dominio__c": domain_name,
            "Anyo__c": invoice_month[:4] if len(invoice_month) >= 4 else "",
            "Mes__c": invoice_month[-2:] if len(invoice_month) >= 2 else "",
            "CurrencyIsoCode": row.get("currency"),
            "SKU2__c": sku_sf,
            "Oportunidad__c": opp_id or "",
            "Order_Number__c": row.get("order_id"),
            "usage_type": usage_type,
        }

        if opp_id:
            base_record["type"] = "pass"
            pass_records.append(base_record)
        else:
            base_record["type"] = "reject"
            reject_records.append(base_record)

    stats["pass_count"] = len(pass_records)

    # Classify rejects
    excluded_set = {
        (str(item.get("Dominio__c", "")), str(item.get("SKU2__c", "")))
        for item in excluded_billing
    }

    na_count = 0
    for record in reject_records:
        excl_key = (record["Dominio__c"], record["SKU2__c"])
        if excl_key in excluded_set:
            record["type"] = "NA"
            na_count += 1

    stats["reject_count"] = len(reject_records) - na_count
    stats["na_count"] = na_count

    logger.info(
        "phase_2_classification_complete",
        pass_count=len(pass_records),
        reject_count=stats["reject_count"],
        na_count=na_count,
    )

    # Load to Salesforce
    if pass_records:
        logger.info("phase_2_inserting_to_salesforce", count=len(pass_records))

        # Serialize for SF
        sf_records = [_serialize_for_sf(record) for record in pass_records]

        # Insert with error handling
        result = await extractor.insert_records("Lectura__c", sf_records)
        stats["sf_inserted"] = result.get("success", 0)
        stats["sf_insert_errors"] = result.get("errors", 0)

        logger.info(
            "phase_2_salesforce_insert_complete",
            inserted=stats["sf_inserted"],
            errors=stats["sf_insert_errors"],
        )
    else:
        logger.info("phase_2_no_pass_records_to_insert")

    # Write ALL classified records to BQ importes_lecturas_workspace (APPEND)
    # Delete existing records for same year/month first to avoid duplicates on re-runs
    all_records = pass_records + reject_records
    if all_records:
        bq_records = [_serialize_for_sf(record) for record in all_records]

        # Idempotent: delete previous data for this billing period before appending
        importes_table = (
            f"`{config.gcp_project_id}"
            f".{config.bq_transformed_dataset}"
            f".{config.bq_importes_lecturas_table}`"
        )
        delete_sql = (
            f"DELETE FROM {importes_table} "
            f"WHERE Anyo__c = '{config.billing_year}' "
            f"AND Mes__c = '{config.billing_month}'"
        )
        try:
            delete_job = loader.execute_query(delete_sql)
            deleted_rows = delete_job.num_dml_affected_rows or 0
            logger.info(
                "phase_2_deleted_previous_importes",
                table=config.bq_importes_lecturas_table,
                year=config.billing_year,
                month=config.billing_month,
                deleted_rows=deleted_rows,
            )
        except Exception:
            # Table may not exist yet on first run
            logger.info("phase_2_importes_table_not_found_will_create")

        logger.info(
            "phase_2_writing_importes_lecturas_to_bq",
            table=config.bq_importes_lecturas_table,
            total_records=len(bq_records),
            pass_count=len(pass_records),
            reject_count=stats["reject_count"],
            na_count=na_count,
        )
        loader.load_raw_data(
            table_name=config.bq_importes_lecturas_table,
            data=bq_records,
            write_disposition="WRITE_APPEND",
        )
        stats["bq_importes_written"] = len(bq_records)
        logger.info(
            "phase_2_importes_lecturas_written",
            rows=len(bq_records),
        )
    else:
        logger.info("phase_2_no_records_for_importes_lecturas")

    logger.info("phase_2_transform_complete", stats=stats)
    return stats


# ───────────────────────────────────────────────────────────────────────────
# UNIFIED PIPELINE
# ───────────────────────────────────────────────────────────────────────────


async def run_workspace_reseller_pipeline(
    config: WorkspaceResellerPipelineConfig,
) -> dict[str, Any]:
    """
    Execute unified workspace reseller pipeline:
      1. Stage: Extract reseller_view, write to bq_workspace_reseller
      2. Transform: Cross-reference with SF opportunities, classify records
      3. Load: Insert PASS records to SF Lectura__c
      4. Write: All classified records (PASS/REJECT/NA) to BQ importes_lecturas_workspace
    
    Returns:
        Dictionary with combined statistics from both phases
    """
    logger.info(
        "workspace_reseller_pipeline_start",
        country=config.country,
        billing_year=config.billing_year,
        billing_month=config.billing_month,
    )

    # Initialize clients
    bq_loader = BigQueryLoader(
        project_id=config.gcp_project_id,
        dataset_id=config.bq_transformed_dataset,
    )

    sf_extractor = SalesforceExtractor(
        username=config.sf_user,
        private_key=config.sf_private_key or "",
        client_id=config.sf_client_id or "",
        sandbox=config.sf_sandbox,
    )
    await sf_extractor.connect()

    try:
        # Phase 1: Stage
        staged_rows = await asyncio.to_thread(
            stage_reseller_view_to_bq, config, bq_loader
        )

        # Phase 2: Transform & Load
        transform_stats = await transform_and_load_to_sf(
            config, bq_loader, sf_extractor, staged_rows
        )

        combined_stats = {
            "phase_1_staged_rows": staged_rows,
            **transform_stats,
        }

        logger.info(
            "workspace_reseller_pipeline_complete",
            country=config.country,
            stats=combined_stats,
        )

        return combined_stats

    finally:
        await sf_extractor.disconnect()


async def main(country: str, month: str, year: str) -> int:
    """Main entry point."""
    configure_logging(log_level="INFO", environment="production")

    try:
        settings = load_country_settings(country)
    except FileNotFoundError as e:
        logger.error("country_config_not_found", error=str(e))
        return 1

    if not settings.bq_workspace_dataset:
        logger.error("bq_workspace_dataset_not_configured", country=country)
        return 1

    job_config = WorkspaceResellerPipelineConfig(
        country=country,
        billing_month=month.zfill(2),
        billing_year=year,
        gcp_project_id=settings.bq_project_id,
        bq_workspace_dataset=settings.bq_workspace_dataset,
        bq_transformed_dataset=settings.bq_transformed_dataset,
        sf_user=settings.sf_user,
        sf_empresa_code=settings.sf_empresa_code,
        sf_private_key=settings.sf_private_key,
        sf_client_id=settings.sf_client_id,
        sf_sandbox=settings.sf_sandbox,
    )

    try:
        stats = await run_workspace_reseller_pipeline(job_config)
        logger.info("job_completed_successfully", stats=stats)
        return 0
    except Exception as e:
        logger.error("job_failed", error=str(e), exc_info=True)
        return 1


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(
        description="Workspace Reseller Pipeline - Extract, transform, load reseller data"
    )
    parser.add_argument("--country", required=True, help="Country config (e.g., win_uk)")
    parser.add_argument("--month", required=True, help="Billing month (e.g., 05)")
    parser.add_argument("--year", required=True, help="Billing year (e.g., 2026)")
    args = parser.parse_args()

    exit_code = asyncio.run(main(args.country, args.month, args.year))
    sys.exit(exit_code)
