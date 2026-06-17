"""Salesforce data extraction module."""

import asyncio
from typing import Any, Optional
from datetime import datetime
import structlog

from simple_salesforce import Salesforce
from simple_salesforce.exceptions import SalesforceError as SalesforceException

logger = structlog.get_logger(__name__)


class SalesforceExtractor:
    """Extract data from Salesforce using OAuth JWT authentication."""

    def __init__(
        self,
        username: str,
        private_key: str,
        client_id: str,
        sandbox: bool = False,
    ):
        """
        Initialize Salesforce extractor.

        Args:
            username: Salesforce username
            private_key: Private key for JWT authentication
            client_id: OAuth client ID
            sandbox: Whether to use sandbox environment
        """
        self.username = username
        self.private_key = private_key.replace("\\n", "\n")
        self.client_id = client_id
        self.sandbox = sandbox
        self.sf: Optional[Salesforce] = None
        self.is_connected = False

    async def connect(self) -> None:
        """Connect to Salesforce using JWT."""
        try:
            logger.info(
                "connecting_to_salesforce",
                username=self.username,
                sandbox=self.sandbox,
            )
            # Simple-salesforce doesn't support async natively, run in thread
            self.sf = await asyncio.to_thread(
                Salesforce,
                username=self.username,
                privatekey=self.private_key,
                consumer_key=self.client_id,
                domain="test" if self.sandbox else "login",
            )
            self.is_connected = True
            logger.info("salesforce_connected_successfully")
        except SalesforceException as e:
            logger.error("salesforce_connection_failed", error=str(e))
            raise

    async def disconnect(self) -> None:
        """Disconnect from Salesforce."""
        self.is_connected = False
        logger.info("salesforce_disconnected")

    async def query(self, soql: str) -> list[dict[str, Any]]:
        """
        Execute a SOQL query and return all records.

        Args:
            soql: SOQL query string

        Returns:
            List of records as dictionaries

        Raises:
            ValueError: If not connected to Salesforce
            SalesforceException: If query fails
        """
        if not self.is_connected or not self.sf:
            raise ValueError("Not connected to Salesforce. Call connect() first.")

        try:
            logger.info("executing_soql_query", query=soql[:100])  # Log first 100 chars
            result = await asyncio.to_thread(self.sf.query_all, soql)
            records = result.get("records", [])
            logger.info("query_executed_successfully", record_count=len(records))
            return records
        except SalesforceException as e:
            logger.error("salesforce_query_failed", error=str(e), query=soql)
            raise

    async def query_all_by_condition(
        self,
        object_type: str,
        conditions: dict[str, Any],
        fields: Optional[list[str]] = None,
    ) -> list[dict[str, Any]]:
        """
        Query Salesforce objects with conditions.

        Args:
            object_type: Salesforce object type (e.g., 'Opportunity')
            conditions: Dictionary of field conditions
            fields: Specific fields to retrieve (None = all)

        Returns:
            List of records matching conditions
        """
        if not self.is_connected or not self.sf:
            raise ValueError("Not connected to Salesforce. Call connect() first.")

        # Build SOQL WHERE clause
        where_clauses = []
        for field, value in conditions.items():
            if isinstance(value, str):
                where_clauses.append(f"{field} = '{value}'")
            elif isinstance(value, (int, float)):
                where_clauses.append(f"{field} = {value}")
            elif isinstance(value, bool):
                where_clauses.append(f"{field} = {str(value).lower()}")
            elif isinstance(value, datetime):
                formatted_date = value.strftime("%Y-%m-%dT%H:%M:%S.000Z")
                where_clauses.append(f"{field} >= {formatted_date}")
            else:
                where_clauses.append(f"{field} = '{value}'")

        where_clause = " AND ".join(where_clauses) if where_clauses else ""

        # Build field list
        field_list = ", ".join(fields) if fields else "*"

        # Build SOQL
        soql = f"SELECT {field_list} FROM {object_type}"
        if where_clause:
            soql += f" WHERE {where_clause}"

        return await self.query(soql)

    async def extract_opportunities(
        self,
        query_condition: str,
    ) -> list[dict[str, Any]]:
        """
        Extract Opportunities matching condition.

        Args:
            query_condition: SOQL WHERE condition (e.g., "CreatedDate > LAST_N_MONTHS:1")

        Returns:
            List of opportunity records
        """
        soql = f"SELECT * FROM Opportunity WHERE {query_condition}"
        return await self.query(soql)

    async def extract_opportunity_line_items(
        self,
        query_condition_1: str,
        query_condition_2: str,
    ) -> list[dict[str, Any]]:
        """
        Extract OpportunityLineItems with dual conditions.

        Args:
            query_condition_1: First WHERE condition
            query_condition_2: Second WHERE condition

        Returns:
            List of opportunity line item records
        """
        soql = f"SELECT * FROM OpportunityLineItem WHERE {query_condition_1} AND {query_condition_2}"
        return await self.query(soql)

    async def extract_billing_accounts_n_a(self) -> list[dict[str, Any]]:
        """
        Extract Billing Accounts marked as N/A.

        Returns:
            List of billing account records
        """
        soql = (
            "SELECT Id, OwnerId, IsDeleted, Name, CurrencyIsoCode, "
            "CreatedDate, CreatedById, LastModifiedDate, LastModifiedById, "
            "SystemModstamp, LastViewedDate, LastReferencedDate, "
            "ConnectionReceivedId, ConnectionSentId, "
            "billing_account_desc__c, billing_account_id__c "
            "FROM Account WHERE billing_account_id__c != null"
        )
        return await self.query(soql)

    async def insert_records(
        self,
        object_name: str,
        records: list[dict[str, Any]],
        batch_size: int = 200,
    ) -> dict[str, Any]:
        """
        Insert records into a Salesforce object using bulk API.

        Args:
            object_name: Salesforce object API name (e.g., 'Lectura__c')
            records: List of record dicts to insert
            batch_size: Number of records per batch

        Returns:
            Dict with total, success, and errors counts
        """
        if not self.is_connected or not self.sf:
            raise ValueError("Not connected to Salesforce. Call connect() first.")

        if not records:
            logger.warning("no_records_to_insert", object_name=object_name)
            return {"total": 0, "success": 0, "errors": 0}

        logger.info(
            "inserting_records_to_salesforce",
            object_name=object_name,
            record_count=len(records),
            batch_size=batch_size,
        )

        try:
            sf_object = getattr(self.sf.bulk, object_name)
            results = await asyncio.to_thread(
                sf_object.insert,
                records,
                batch_size=batch_size,
            )

            success_count = sum(1 for r in results if r.get("success"))
            error_count = len(results) - success_count

            logger.info(
                "salesforce_insert_completed",
                object_name=object_name,
                success_count=success_count,
                error_count=error_count,
            )

            if error_count > 0:
                errors = [r for r in results if not r.get("success")]
                logger.warning(
                    "salesforce_insert_had_errors",
                    error_count=error_count,
                    sample_errors=errors[:5],
                )

            return {
                "total": len(records),
                "success": success_count,
                "errors": error_count,
            }
        except SalesforceException as e:
            logger.error(
                "salesforce_insert_failed",
                error=str(e),
                object_name=object_name,
            )
            raise

    async def delete_records(
        self,
        object_name: str,
        record_ids: list[str],
        batch_size: int = 200,
    ) -> dict[str, Any]:
        """
        Delete records from a Salesforce object using bulk API.

        Args:
            object_name: Salesforce object API name (e.g., 'Carga_de_lectura__c')
            record_ids: List of record IDs to delete
            batch_size: Number of records per batch

        Returns:
            Dict with total, success, and errors counts
        """
        if not self.is_connected or not self.sf:
            raise ValueError("Not connected to Salesforce. Call connect() first.")

        if not record_ids:
            logger.warning("no_records_to_delete", object_name=object_name)
            return {"total": 0, "success": 0, "errors": 0}

        logger.info(
            "deleting_records_from_salesforce",
            object_name=object_name,
            record_count=len(record_ids),
            batch_size=batch_size,
        )

        try:
            records = [{"Id": rid} for rid in record_ids]
            sf_object = getattr(self.sf.bulk, object_name)
            results = await asyncio.to_thread(
                sf_object.delete,
                records,
                batch_size=batch_size,
            )

            success_count = sum(1 for r in results if r.get("success"))
            error_count = len(results) - success_count

            logger.info(
                "salesforce_delete_completed",
                object_name=object_name,
                success_count=success_count,
                error_count=error_count,
            )

            if error_count > 0:
                errors = [r for r in results if not r.get("success")]
                logger.warning(
                    "salesforce_delete_had_errors",
                    error_count=error_count,
                    sample_errors=errors[:5],
                )

            return {
                "total": len(records),
                "success": success_count,
                "errors": error_count,
            }
        except SalesforceException as e:
            logger.error(
                "salesforce_delete_failed",
                error=str(e),
                object_name=object_name,
            )
            raise

    async def extract_multiple_parallel(
        self,
        queries: dict[str, str],
    ) -> dict[str, list[dict[str, Any]]]:
        """
        Execute multiple SOQL queries in parallel.

        Args:
            queries: Dictionary mapping query names to SOQL strings

        Returns:
            Dictionary mapping query names to result lists
        """
        tasks = {name: self.query(soql) for name, soql in queries.items()}
        results = await asyncio.gather(*tasks.values(), return_exceptions=True)

        output = {}
        for (name, _), result in zip(tasks.items(), results):
            if isinstance(result, Exception):
                logger.error(f"query_failed_for_{name}", error=str(result))
                output[name] = []
            else:
                output[name] = result

        return output
