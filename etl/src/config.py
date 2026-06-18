"""Configuration management using Pydantic Settings."""

import os
from pathlib import Path
from typing import Optional

from pydantic_settings import BaseSettings
from dotenv import load_dotenv


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    # Salesforce (common to all countries, from .env)
    sf_user: str
    sf_stage_name: str = "Cerrada ganada"
    sf_skus: str  # Comma-separated SKU codes
    sf_private_key: Optional[str] = None  # OAuth JWT private key (from .env)
    sf_client_id: Optional[str] = None  # OAuth JWT client ID (from .env)
    sf_sandbox: bool = False

    # Salesforce (country-specific, from .env.{country})
    sf_empresa_code: str

    # BigQuery (country-specific, from .env.{country})
    bq_project_id: str
    bq_raw_dataset: str
    bq_transformed_dataset: str
    bq_input_dataset: str
    bq_workspace_dataset: Optional[str] = None

    # Output table names (can be overridden per country, from .env.{country})
    bq_output_table_billing_accounts: str = "billing_accounts"
    bq_output_table_billing_accounts_full: str = "billing_accounts_full"
    bq_output_table_flex: str = "importes_lecturas_temp"
    bq_output_table_flex_desglosadas: str = "importes_lecturas_by_project"
    bq_output_table_workspace: str = "importes_lecturas_workspace"

    # Currencies (common)
    currencies: str

    class Config:
        env_file = ".env"
        case_sensitive = False
        extra = "ignore"  # ignora claves del .env no declaradas (GCP_PROJECT_ID, LOG_LEVEL, ENVIRONMENT)


def load_country_settings(country_code: str) -> Settings:
    """
    Load settings for a specific country.

    Loads .env base first, then overlays .env.{country_code} if it exists.

    Args:
        country_code: Country code (e.g., 'win_uk', 'win_es')

    Returns:
        Settings object with country-specific configuration

    Raises:
        FileNotFoundError: If country .env file doesn't exist
        ValueError: If required settings are missing
    """
    # Get project root
    base_path = Path(__file__).parent.parent

    # Load base .env
    env_file = base_path / ".env"
    if env_file.exists():
        load_dotenv(env_file)

    # Load country-specific .env
    country_env_file = base_path / f".env.{country_code}"
    if not country_env_file.exists():
        raise FileNotFoundError(
            f"Country configuration not found: {country_env_file}. "
            f"Create .env.{country_code} with country-specific settings."
        )

    load_dotenv(country_env_file, override=True)

    try:
        return Settings()
    except Exception as e:
        raise ValueError(f"Failed to load settings for country {country_code}: {e}")


def get_settings() -> Settings:
    """Get application settings from .env."""
    return Settings()
