"""
Mix and Match - Staging Job

Extracts SF opportunities + line items and loads to BQ staging tables
(stg_opportunities, stg_line_items) for use by the 3 mix_and_match jobs.

Run once before the 3 mix_and_match jobs.

Usage:
    python -m src.etl.jobs.mix_and_match_staging --country win_uk
"""

from calendar import monthrange
from pathlib import Path
from typing import Optional

import asyncio
import sys
import structlog
from pydantic import BaseModel, ConfigDict

from src.config import load_country_settings
from src.utils import build_empresa_filter
from src.etl.extract.salesforce_extractor import SalesforceExtractor
from src.etl.load.bigquery_loader import BigQueryLoader
from src.utils.logging_config import configure_logging

logger = structlog.get_logger(__name__)


class MixAndMatchConfig(BaseModel):
    """Shared configuration for all mix_and_match jobs."""

    country: str
    billing_month: str  # zero-padded e.g. "05"
    billing_year: str  # e.g. "2026"

    # BigQuery
    gcp_project_id: str
    bq_transformed_dataset: str  # staging tables + output tables
    bq_input_dataset: str  # consumption data (sum_costs_credits tables)

    # Salesforce
    sf_user: str
    sf_empresa_code: str
    sf_stage_name: str = "Cerrada ganada"
    sf_skus: str  # Comma-separated SKU codes
    sf_private_key: Optional[str] = None
    sf_client_id: Optional[str] = None
    sf_sandbox: bool = False

    # Output tables (overridable per country via .env)
    bq_output_table_flex: str = "importes_lecturas_temp"
    bq_output_table_flex_desglosadas: str = "importes_lecturas_by_project"

    model_config = ConfigDict(extra="ignore")

    @property
    def invoice_month(self) -> str:
        """YYYYMM format for SQL parameters."""
        return f"{self.billing_year}{self.billing_month}"

    @property
    def first_day(self) -> str:
        """First day of billing month (YYYY-MM-DD)."""
        return f"{self.billing_year}-{self.billing_month}-01"

    @property
    def last_day(self) -> str:
        """Last day of billing month (YYYY-MM-DD)."""
        day = monthrange(int(self.billing_year), int(self.billing_month))[1]
        return f"{self.billing_year}-{self.billing_month}-{day:02d}"


# ───────────────────────────────────────────────────────────────────────────
# SOQL templates for staging extraction
# SOQL requires explicit field names (no SELECT *)
# Fields listed = all fields referenced by the 3 materialize SQL queries
# ───────────────────────────────────────────────────────────────────────────

_STG_OPPORTUNITIES_SOQL = (
    "SELECT Id, billing_account_id__c, CurrencyIsoCode, Billing_Model__c, "
    "Desglosar_Facturas__c, googleInvoiceTypeOpp__c, "
    "Margen_SWO__c, "
    "Margen_de_partner_Descuento_GCP__c, Margen_de_partner_Descuento_GMP__c, "
    "Margen_de_partner_Descuento_Soporte__c, Margen_de_partner_Descuento_Soporte_Maps__c, "
    "Margen_de_partner_Margen_Soporte__c, Margen_de_partner_Margen_Soporte_Maps__c, "
    "Sop_Tec_Porcent__c, Sop_Tec_Maps_Porcent__c, "
    "Sop_Tec_imp_minimo__c, Sop_Tec_Maps_imp_minimo__c, "
    "Sop_Tec_imp_fijo__c, Sop_Tec_Maps_Importe_Fijo__c "
    "FROM Opportunity "
    "WHERE {empresa_filter} "
    "AND billing_account_id__c != null "
    "AND StageName = '{stage_name}' "
    "AND (Estado_del_contrato__c = 'Activado' "
    "OR Estado_del_contrato__c = '' "
    "OR Estado_del_contrato__c = null)"
)

_STG_LINE_ITEMS_SOQL = (
    "SELECT OpportunityId, SKU__c, Dominio__c, "
    "Fecha_Inicio_Contrato_Opp__c, Fecha_Fin_Contrato_Opp__c, "
    "Descripci_n_del_producto__c "
    "FROM OpportunityLineItem "
    "WHERE SKU__c IN ({skus}) "
    "AND (Fecha_Inicio_Contrato_Opp__c = NULL "
    "OR Fecha_Inicio_Contrato_Opp__c < TODAY) "
    "AND (Fecha_Fin_Contrato_Opp__c = NULL "
    "OR Fecha_Fin_Contrato_Opp__c >= TODAY)"
)


def load_query_template(query_name: str) -> str:
    """Load SQL query template from config/queries."""
    base_path = Path(__file__).parent.parent.parent.parent
    query_file = base_path / "config" / "queries" / f"{query_name}.sql"
    if not query_file.exists():
        raise FileNotFoundError(f"Query template not found: {query_file}")
    return query_file.read_text(encoding="utf-8").strip()


def get_sql_params(config: MixAndMatchConfig) -> dict[str, str]:
    """Build the parameter dict for materialize SQL queries."""
    return {
        "project": config.gcp_project_id,
        "transformed_dataset": config.bq_transformed_dataset,
        "input_dataset": config.bq_input_dataset,
        "invoice_month": config.invoice_month,
    }


def execute_materialize_query(
    config: MixAndMatchConfig,
    loader: BigQueryLoader,
    query_name: str,
) -> None:
    """Execute a materialize SQL query (CREATE OR REPLACE TABLE)."""
    template = load_query_template(query_name)
    sql = template.format_map(get_sql_params(config))
    logger.info("executing_materialize_query", query_name=query_name)
    loader.execute_query(sql)
    logger.info("materialize_query_complete", query_name=query_name)


def write_to_output_table(
    config: MixAndMatchConfig,
    loader: BigQueryLoader,
    temp_table_name: str,
    output_table_name: str,
    period_column: Optional[str] = None,
) -> int:
    """
    Write temp table data to output table.

    If period_column is set (e.g. 'invoice_month'), uses DELETE+INSERT for
    idempotency.  Otherwise plain APPEND (matches Talend behaviour).

    Returns:
        Number of rows inserted
    """
    fq_temp = (
        f"`{config.gcp_project_id}.{config.bq_transformed_dataset}.{temp_table_name}`"
    )
    fq_output = (
        f"`{config.gcp_project_id}.{config.bq_transformed_dataset}.{output_table_name}`"
    )

    # Idempotent DELETE when the temp table carries a period column
    if period_column:
        try:
            delete_job = loader.execute_query(
                f"DELETE FROM {fq_output} "
                f"WHERE {period_column} = '{config.invoice_month}'"
            )
            deleted = delete_job.num_dml_affected_rows or 0
            logger.info(
                "deleted_existing_rows",
                table=output_table_name,
                invoice_month=config.invoice_month,
                deleted_rows=deleted,
            )
        except Exception:
            # Table doesn't exist yet — will be created below
            logger.info("output_table_not_found_will_create", table=output_table_name)

    # Try INSERT INTO existing table; if table doesn't exist, CREATE from temp
    try:
        loader.execute_query(
            f"SELECT 1 FROM {fq_output} LIMIT 0"
        )
        insert_job = loader.execute_query(
            f"INSERT INTO {fq_output} SELECT * FROM {fq_temp}"
        )
        inserted = insert_job.num_dml_affected_rows or 0
    except Exception:
        logger.info("creating_output_table_from_temp", table=output_table_name)
        loader.execute_query(
            f"CREATE TABLE {fq_output} AS SELECT * FROM {fq_temp}"
        )
        # Count rows from temp table
        count_result = loader.query_to_dicts(
            f"SELECT COUNT(*) AS cnt FROM {fq_temp}"
        )
        inserted = count_result[0]["cnt"] if count_result else 0

    logger.info(
        "inserted_to_output_table",
        table=output_table_name,
        rows=inserted,
    )
    return inserted


async def create_staging_tables(
    config: MixAndMatchConfig,
    loader: BigQueryLoader,
    extractor: SalesforceExtractor,
) -> dict[str, int]:
    """
    Extract SF opportunities + line items → BQ staging tables.

    Creates stg_opportunities and stg_line_items (WRITE_TRUNCATE).

    Returns:
        Row counts: {"stg_opportunities": n, "stg_line_items": m}
    """
    logger.info(
        "mix_and_match_staging_start",
        empresa_code=config.sf_empresa_code,
    )

    # Format SKUs for SOQL IN clause (double field, no quotes): 1417,1409,...
    skus_formatted = ",".join(
        s.strip() for s in config.sf_skus.split(",")
    )

    opp_soql = _STG_OPPORTUNITIES_SOQL.format(
        empresa_filter=build_empresa_filter(config.sf_empresa_code),
        stage_name=config.sf_stage_name,
    )
    oli_soql = _STG_LINE_ITEMS_SOQL.format(skus=skus_formatted)

    # Extract from SF in parallel
    results = await extractor.extract_multiple_parallel(
        {
            "opportunities": opp_soql,
            "line_items": oli_soql,
        }
    )

    opp_data = results["opportunities"]
    oli_data = results["line_items"]

    logger.info(
        "mix_and_match_sf_extracted",
        opportunities=len(opp_data),
        line_items=len(oli_data),
    )

    counts: dict[str, int] = {}

    if opp_data:
        loader.load_raw_data("stg_opportunities", opp_data, "WRITE_TRUNCATE")
        counts["stg_opportunities"] = len(opp_data)
    else:
        logger.warning("no_opportunities_extracted")
        counts["stg_opportunities"] = 0

    if oli_data:
        loader.load_raw_data("stg_line_items", oli_data, "WRITE_TRUNCATE")
        counts["stg_line_items"] = len(oli_data)
    else:
        logger.warning("no_line_items_extracted")
        counts["stg_line_items"] = 0

    logger.info("mix_and_match_staging_complete", counts=counts)
    return counts


async def main(country: str) -> int:
    """Main entry point."""
    configure_logging(log_level="INFO", environment="production")

    try:
        settings = load_country_settings(country)
    except FileNotFoundError as e:
        logger.error("country_config_not_found", error=str(e))
        return 1

    config = MixAndMatchConfig(
        country=country,
        billing_month="01",  # Not used for staging, placeholder
        billing_year="2026",  # Not used for staging, placeholder
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

    try:
        counts = await create_staging_tables(config, loader, extractor)
        logger.info("staging_job_completed", counts=counts)
        return 0
    except Exception as e:
        logger.error("staging_job_failed", error=str(e), exc_info=True)
        return 1
    finally:
        await extractor.disconnect()


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(
        description="Mix and Match - Staging (run once before mix_and_match jobs)"
    )
    parser.add_argument("--country", required=True, help="Country config (e.g., win_uk)")
    args = parser.parse_args()

    exit_code = asyncio.run(main(args.country))
    sys.exit(exit_code)
