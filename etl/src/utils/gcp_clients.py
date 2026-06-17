"""GCP client factory functions."""

from google.cloud import bigquery, storage, secretmanager
from typing import Optional


def get_bigquery_client(project_id: str) -> bigquery.Client:
    """Create a BigQuery client."""
    return bigquery.Client(project=project_id)


def get_storage_client(project_id: str) -> storage.Client:
    """Create a Cloud Storage client."""
    return storage.Client(project=project_id)


def get_secret_manager_client(
    project_id: str,
) -> secretmanager.SecretManagerServiceClient:
    """Create a Secret Manager client."""
    return secretmanager.SecretManagerServiceClient()


async def get_secret(
    project_id: str,
    secret_name: str,
    version_id: str = "latest",
) -> str:
    """
    Retrieve a secret from Secret Manager.

    Args:
        project_id: GCP project ID
        secret_name: Name of the secret
        version_id: Version of the secret (default: latest)

    Returns:
        Secret value as string
    """
    client = get_secret_manager_client(project_id)
    name = f"projects/{project_id}/secrets/{secret_name}/versions/{version_id}"
    response = client.access_secret_version(request={"name": name})
    return response.payload.data.decode("UTF-8")
