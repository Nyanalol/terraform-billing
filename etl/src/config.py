"""Configuration management using Pydantic Settings.

Fuente única: la config por país NO vive en ficheros .env.<país>, se lee directamente
de countries.yaml (en la raíz del repo). El .env común solo lleva SECRETOS (claves SF) y,
opcionalmente, el modo (ETL_MODE=sandbox|prod) y el proyecto sandbox.
"""

import os
import re
from pathlib import Path
from typing import Optional

import yaml
from pydantic_settings import BaseSettings
from dotenv import load_dotenv

# Raíz del repo: etl/src/config.py -> etl/ -> repo. Override con COUNTRIES_YAML si hace falta
# (p. ej. al empaquetar para Cloud Run, donde countries.yaml se copia junto al código).
REPO_ROOT = Path(__file__).resolve().parents[2]
COUNTRIES_YAML = Path(os.environ.get("COUNTRIES_YAML", REPO_ROOT / "countries.yaml"))
SANDBOX_PROJECT_DEFAULT = "ip-trabajo-apeinado"

# Divisas SIEMPRE necesarias (USD = consumo del export; EUR = reporting). La lista CURRENCIES
# es GLOBAL e igual para todos los países: los tipos de cambio no dependen del país, así que el
# job de currencies se corre UNA vez. Ver docs/GENERADORES_Y_CURRENCIES.md.
_BASE_CURRENCIES = ["EUR", "USD"]


def _empresa_code(clause: str) -> str:
    """De la cláusula Empresa_IP__c de countries.yaml a SF_EMPRESA_CODE:
    código pelado si es único; cláusula (A OR B) si son varios."""
    codes = re.findall(r"Empresa_IP__c='([^']+)'", clause)
    if len(codes) == 1:
        return codes[0]
    return "(" + " OR ".join(f"Empresa_IP__c='{c}'" for c in codes) + ")"


def _global_currencies(data: dict) -> str:
    cur = list(_BASE_CURRENCIES)
    for meta in data.values():
        c = meta.get("currency")
        if c and c not in cur:
            cur.append(c)
    return ",".join(cur)


def _load_countries() -> dict:
    return yaml.safe_load(COUNTRIES_YAML.read_text(encoding="utf-8"))


def _find_country(data: dict, country_code: str) -> dict:
    """Localiza el país por talend_context (p. ej. 'win_es')."""
    for meta in data.values():
        if meta.get("talend_context") == country_code:
            return meta
    raise FileNotFoundError(
        f"País '{country_code}' no encontrado en {COUNTRIES_YAML} "
        f"(busca por talend_context, p. ej. win_es)."
    )


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    # Salesforce (common to all countries, from .env)
    sf_user: str
    sf_stage_name: str = "Cerrada ganada"
    sf_skus: str  # Comma-separated SKU codes
    sf_private_key: Optional[str] = None  # OAuth JWT private key (from .env)
    sf_client_id: Optional[str] = None  # OAuth JWT client ID (from .env)
    sf_sandbox: bool = False

    # Salesforce (country-specific, de countries.yaml vía load_country_settings)
    sf_empresa_code: str

    # BigQuery (country-specific, de countries.yaml vía load_country_settings)
    bq_project_id: str
    bq_raw_dataset: str
    bq_transformed_dataset: str
    bq_input_dataset: str
    bq_workspace_dataset: Optional[str] = None

    # Output table names (defaults; override por .env común si hace falta)
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
    Carga la config de un país combinando:
      - SECRETOS y comunes: del .env base (SF_*, table overrides).
      - Config por país: de countries.yaml (project, datasets, empresa, currencies).

    El modo lo decide ETL_MODE (env, default 'sandbox' por seguridad durante la validación):
      - sandbox: BQ_PROJECT_ID = ip-trabajo-apeinado (o SANDBOX_PROJECT), raw = billing_raw.
      - prod:    BQ_PROJECT_ID = proyecto real del país, raw = su export_dataset.

    Args:
        country_code: contexto Talend del país (p. ej. 'win_uk', 'win_es').

    Raises:
        FileNotFoundError: si el país no está en countries.yaml.
        ValueError: si faltan settings requeridos (p. ej. secretos en .env).
    """
    # 1) .env base (secretos + comunes)
    env_file = Path(__file__).parent.parent / ".env"
    if env_file.exists():
        load_dotenv(env_file)

    # 2) país desde countries.yaml (fuente única)
    data = _load_countries()
    meta = _find_country(data, country_code)

    # 3) modo sandbox/prod
    mode = os.environ.get("ETL_MODE", "sandbox").strip().lower()
    if mode == "prod":
        project = meta["project_id"]
        raw_dataset = meta["export_dataset"]
    else:
        project = os.environ.get("SANDBOX_PROJECT", SANDBOX_PROJECT_DEFAULT)
        raw_dataset = "billing_raw"

    # 4) Settings: los kwargs (config de país derivada) tienen prioridad sobre el .env;
    #    los secretos (sf_user, sf_skus, sf_private_key, ...) siguen viniendo del .env.
    try:
        return Settings(
            sf_empresa_code=_empresa_code(meta["sf_empresa_ip"]),
            bq_project_id=project,
            bq_raw_dataset=raw_dataset,
            bq_transformed_dataset="billing_views",
            bq_input_dataset="billing_views",
            bq_workspace_dataset="billing_views",
            currencies=_global_currencies(data),
        )
    except Exception as e:
        raise ValueError(f"Failed to load settings for country {country_code}: {e}")


def get_settings() -> Settings:
    """Settings solo-comunes desde .env (sin país). Uso puntual; los jobs usan load_country_settings."""
    env_file = Path(__file__).parent.parent / ".env"
    if env_file.exists():
        load_dotenv(env_file)
    return Settings()
