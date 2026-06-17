"""BigQuery data loading module."""

from typing import Any, Optional
from datetime import datetime
import structlog

from google.cloud import bigquery
from google.cloud.bigquery import LoadJobConfig, SourceFormat, SchemaUpdateOption
from google.cloud.exceptions import GoogleCloudError

logger = structlog.get_logger(__name__)


class BigQueryLoader:
    """Load data to BigQuery staging tables."""

    def __init__(self, project_id: str, dataset_id: str):
        """
        Initialize BigQuery loader.

        Args:
            project_id: GCP project ID
            dataset_id: BigQuery dataset ID for staging
        """
        self.project_id = project_id
        self.dataset_id = dataset_id
        self.client = bigquery.Client(project=project_id)
        logger.info(
            "bigquery_loader_initialized",
            project_id=project_id,
            dataset_id=dataset_id,
        )

    def _get_table_id(self, table_name: str) -> str:
        """Get fully qualified table ID."""
        return f"{self.project_id}.{self.dataset_id}.{table_name}"

    def load_raw_data(
        self,
        table_name: str,
        data: list[dict[str, Any]],
        write_disposition: str = "WRITE_TRUNCATE",
        autodetect_schema: bool = True,
    ) -> bigquery.LoadJob:
        """
        Load raw data to a BigQuery staging table.

        Args:
            table_name: Target table name
            data: List of dictionaries to load
            write_disposition: How to handle existing data (WRITE_TRUNCATE, WRITE_APPEND)
            autodetect_schema: Whether to auto-detect schema from data

        Returns:
            Completed LoadJob

        Raises:
            ValueError: If data is empty
            GoogleCloudError: If load fails
        """
        if not data:
            logger.warning("attempting_to_load_empty_data", table_name=table_name)
            raise ValueError(f"Cannot load empty data to {table_name}")

        table_id = self._get_table_id(table_name)
        logger.info(
            "starting_load_to_bigquery",
            table_id=table_id,
            record_count=len(data),
            write_disposition=write_disposition,
        )

        try:
            # Configure load job
            job_config = LoadJobConfig(
                source_format=SourceFormat.NEWLINE_DELIMITED_JSON,
                write_disposition=write_disposition,
                autodetect=autodetect_schema,
            )

            # Convert data to newline-delimited JSON
            json_data = self._convert_to_json_lines(data)

            # Load data
            load_job = self.client.load_table_from_file(
                json_data,
                table_id,
                job_config=job_config,
            )

            # Wait for job to complete
            load_job.result()

            logger.info(
                "data_loaded_successfully",
                table_id=table_id,
                output_rows=load_job.output_rows,
                bytes_loaded=load_job.output_bytes,
            )

            return load_job

        except GoogleCloudError as e:
            logger.error("bigquery_load_failed", table_id=table_id, error=str(e))
            raise

    def _convert_to_json_lines(self, data: list[dict[str, Any]]) -> str:
        """
        Convert list of dicts to newline-delimited JSON.

        Args:
            data: List of dictionaries

        Returns:
            Newline-delimited JSON string
        """
        import json
        import io

        output = io.StringIO()
        for record in data:
            # Handle non-serializable types
            record_cleaned = self._serialize_record(record)
            output.write(json.dumps(record_cleaned) + "\n")

        output.seek(0)
        return output

    def _serialize_record(self, record: dict[str, Any]) -> dict[str, Any]:
        """
        Serialize record for JSON encoding.

        Args:
            record: Dictionary to serialize

        Returns:
            Serializable dictionary
        """
        output = {}
        for key, value in record.items():
            if isinstance(value, datetime):
                output[key] = value.isoformat()
            elif isinstance(value, bytes):
                output[key] = value.decode("utf-8", errors="ignore")
            elif value is None:
                output[key] = None
            else:
                output[key] = value
        return output

    def load_raw_parquet(
        self,
        table_name: str,
        parquet_path: str,
        write_disposition: str = "WRITE_TRUNCATE",
    ) -> bigquery.LoadJob:
        """
        Load Parquet file to BigQuery.

        Args:
            table_name: Target table name
            parquet_path: Path to Parquet file (GCS URI or local)
            write_disposition: How to handle existing data

        Returns:
            Completed LoadJob

        Raises:
            GoogleCloudError: If load fails
        """
        table_id = self._get_table_id(table_name)
        logger.info(
            "starting_parquet_load",
            table_id=table_id,
            parquet_path=parquet_path,
        )

        try:
            job_config = LoadJobConfig(
                source_format=SourceFormat.PARQUET,
                write_disposition=write_disposition,
                schema_update_options=[
                    SchemaUpdateOptions.ALLOW_FIELD_ADDITION,
                ],
            )

            load_job = self.client.load_table_from_uri(
                parquet_path,
                table_id,
                job_config=job_config,
            )

            load_job.result()

            logger.info(
                "parquet_loaded_successfully",
                table_id=table_id,
                output_rows=load_job.output_rows,
            )

            return load_job

        except GoogleCloudError as e:
            logger.error(
                "bigquery_parquet_load_failed", table_id=table_id, error=str(e)
            )
            raise

    def ensure_dataset_exists(self) -> None:
        """Create dataset if it doesn't exist."""
        dataset_id_full = f"{self.project_id}.{self.dataset_id}"

        try:
            self.client.get_dataset(dataset_id_full)
            logger.info("dataset_already_exists", dataset_id=self.dataset_id)
        except Exception:
            logger.info("creating_dataset", dataset_id=self.dataset_id)
            dataset = bigquery.Dataset(dataset_id_full)
            dataset.location = "EU"  # Adjust based on your region
            self.client.create_dataset(dataset, timeout=30)
            logger.info("dataset_created", dataset_id=self.dataset_id)

    def get_table_schema(self, table_name: str) -> list[bigquery.schema.SchemaField]:
        """
        Get schema of an existing table.

        Args:
            table_name: Table name

        Returns:
            List of schema fields
        """
        table_id = self._get_table_id(table_name)

        try:
            table = self.client.get_table(table_id)
            return table.schema
        except GoogleCloudError as e:
            logger.error(
                "failed_to_get_table_schema",
                table_id=table_id,
                error=str(e),
            )
            raise

    def delete_table(self, table_name: str, not_found_ok: bool = True) -> None:
        """
        Delete a table.

        Args:
            table_name: Table to delete
            not_found_ok: Don't raise if table doesn't exist
        """
        table_id = self._get_table_id(table_name)
        logger.info("deleting_table", table_id=table_id)

        try:
            self.client.delete_table(table_id, not_found_ok=not_found_ok)
            logger.info("table_deleted", table_id=table_id)
        except GoogleCloudError as e:
            logger.error("failed_to_delete_table", table_id=table_id, error=str(e))
            raise

    def query_to_dicts(self, query: str) -> list[dict[str, Any]]:
        """
        Execute a query and return results as list of dictionaries.

        Args:
            query: SQL query to execute

        Returns:
            List of row dictionaries
        """
        logger.info("querying_bigquery_to_dicts", query_preview=query[:200])

        try:
            query_job = self.client.query(query)
            rows = query_job.result()
            data = [dict(row) for row in rows]
            logger.info("query_returned_rows", row_count=len(data))
            return data
        except GoogleCloudError as e:
            logger.error("bigquery_query_to_dicts_failed", error=str(e))
            raise

    def execute_query(
        self,
        query: str,
        job_config: Optional[bigquery.QueryJobConfig] = None,
    ) -> bigquery.QueryJob:
        """
        Execute a SQL query.

        Args:
            query: SQL query to execute
            job_config: Optional QueryJobConfig for the job

        Returns:
            Completed QueryJob

        Raises:
            GoogleCloudError: If query fails
        """
        logger.info("executing_query", query_preview=query[:200])

        try:
            if job_config is None:
                job_config = bigquery.QueryJobConfig()

            query_job = self.client.query(query, job_config=job_config)
            query_job.result()

            logger.info(
                "query_executed_successfully",
                rows_affected=query_job.num_dml_affected_rows or 0,
            )

            return query_job

        except GoogleCloudError as e:
            logger.error("query_execution_failed", error=str(e))
            raise
