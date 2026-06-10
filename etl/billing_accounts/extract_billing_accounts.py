#!/usr/bin/env python3
"""Extrae de Salesforce el maestro de billing accounts y lo aterriza CRUDO en BigQuery.

Sustituye la parte de EXTRACCION del job de Talend `diary_get_billing_accounts`. La
TRANSFORMACION (union + dedup -> billing_accounts / billing_accounts_full) se hace despues
en SQL (Terraform), no aqui.

Mejoras vs Talend:
- Una sola query a Opportunity (Talend hacia dos casi iguales), pidiendo solo las columnas
  necesarias (Talend pedia ~155 y usaba 8).
- JWT en vez de usuario/password en claro.
- Carga idempotente (WRITE_TRUNCATE) en tablas staging.

Credenciales SF por entorno: SF_CONSUMER_KEY, SF_USERNAME, SF_PRIVATE_KEY_FILE.
Datos del pais desde su tfvars (project_id + sf_empresa_ip).

Ejemplo:
    python -m etl.billing_accounts.extract_billing_accounts --country colombia
"""
from __future__ import annotations

import argparse
import logging
import os
import re
import sys

from etl.common import bq
from etl.common.salesforce import connect_from_env

LOG = logging.getLogger("billing_accounts")

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Columnas que de verdad se usan aguas abajo (Talend pedia ~155).
OPP_COLUMNS = [
    "billing_account_id__c", "billing_account_desc__c",
    "Fecha_Inicio_Contrato__c", "Fecha_Fin_Contrato__c",
    "Desglosar_Facturas__c", "Billing_Model__c",
    "StageName", "Estado_del_contrato__c", "Empresa_IP__c",
]
BILLING_ACCOUNT_COLUMNS = [
    "billing_account_id__c", "billing_account_desc__c", "CurrencyIsoCode",
]


def read_tfvar(country: str, key: str) -> str | None:
    path = os.path.join(REPO_ROOT, "tfvars", f"{country}.tfvars")
    with open(path, "r", encoding="utf-8") as fh:
        text = fh.read()
    m = re.search(rf'{key}\s*=\s*"(.*)"', text)
    return m.group(1) if m else None


def soql(module: str, columns: list[str], where: str | None) -> str:
    q = f"SELECT {', '.join(columns)} FROM {module}"
    if where:
        q += f" WHERE {where}"
    return q


def records(sf, query: str, columns: list[str]) -> list[dict]:
    """Ejecuta SOQL y devuelve filas como dicts STRING (None -> None), sin metadatos SF."""
    rows = []
    for rec in sf.query_all(query)["records"]:
        rows.append({c: (None if rec.get(c) is None else str(rec.get(c))) for c in columns})
    return rows


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(description="Extrae billing accounts de Salesforce a BQ staging.")
    p.add_argument("--country", required=True, help="slug del pais (lee tfvars/<country>.tfvars)")
    p.add_argument("--dataset", default=os.environ.get("BQ_STAGING_DATASET", "billing_views"))
    p.add_argument("--dry-run", action="store_true", help="No carga en BQ; solo cuenta filas.")
    args = p.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    project = read_tfvar(args.country, "project_id")
    empresa = read_tfvar(args.country, "sf_empresa_ip")
    if not project:
        raise SystemExit(f"No encuentro project_id en tfvars/{args.country}.tfvars")
    if not empresa:
        raise SystemExit(f"sf_empresa_ip vacio en tfvars/{args.country}.tfvars (pedir a OPS)")

    LOG.info("Pais %s | project %s | dataset %s", args.country, project, args.dataset)
    sf = connect_from_env()
    LOG.info("Salesforce: %s", sf.sf_instance)

    # Opportunity: scope al pais por Empresa_IP + solo las con billing account.
    opp_where = f"billing_account_id__c != null AND ({empresa})"
    opp_rows = records(sf, soql("Opportunity", OPP_COLUMNS, opp_where), OPP_COLUMNS)
    LOG.info("Opportunity: %d filas", len(opp_rows))

    ba_rows = records(sf, soql("Billing_Account__c", BILLING_ACCOUNT_COLUMNS, None), BILLING_ACCOUNT_COLUMNS)
    LOG.info("Billing_Account__c: %d filas", len(ba_rows))

    if args.dry_run:
        LOG.info("DRY-RUN: no se carga en BQ.")
        return 0

    n1 = bq.load_rows(opp_rows, f"{project}.{args.dataset}.stg_opportunity", OPP_COLUMNS, project)
    n2 = bq.load_rows(ba_rows, f"{project}.{args.dataset}.stg_billing_account", BILLING_ACCOUNT_COLUMNS, project)
    LOG.info("Cargadas %d -> stg_opportunity, %d -> stg_billing_account", n1, n2)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
