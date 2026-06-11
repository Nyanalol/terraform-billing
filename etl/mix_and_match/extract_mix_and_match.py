#!/usr/bin/env python3
"""Extrae de Salesforce los inputs de mix_and_match y los aterriza en BQ (staging).

Parte de EXTRACCION del job Talend `mix_and_match`. Trae:
  - stg_opportunities : Opportunity (margenes, descuentos, soporte, billing_model, marketplace flag)
  - stg_line_items    : OpportunityLineItem de esas oportunidades (SKU, fechas, dominio)
La TRANSFORMACION (motor de margenes/importe) se hace despues en SQL.

Extraccion AMPLIA a proposito: trae todos los OLI de las oportunidades en scope (sin filtrar
SKU/fechas aqui); el filtro fino se aplica en el SQL para poder iterar contra el diff con Talend.

Credenciales SF por entorno: SF_CONSUMER_KEY, SF_USERNAME, SF_PRIVATE_KEY_FILE.
Empresa_IP del pais desde tfvars/<country>.tfvars (sf_empresa_ip).

Ejemplo:
    python -m etl.mix_and_match.extract_mix_and_match --country germany \
        --dest-project ip-trabajo-apeinado --dest-dataset mixmatch_validation
"""
from __future__ import annotations

import argparse
import logging
import os
import re
import sys

from etl.common import bq
from etl.common.salesforce import connect_from_env

LOG = logging.getLogger("mix_and_match.extract")
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Sufijo fijo del filtro de Opportunity (igual en todos los paises; solo cambia Empresa_IP).
OPP_COND_SUFFIX = (
    " and billing_account_id__c <> null and StageName = 'Cerrada ganada'"
    " and (Estado_del_contrato__c='Activado' or Estado_del_contrato__c='' or Estado_del_contrato__c=NULL)"
)

OPP_COLUMNS = [
    "Id", "billing_account_id__c", "billing_account_desc__c", "CurrencyIsoCode",
    "Margen_de_partner_Margen_GCP__c", "Margen_de_partner_Margen_GMP__c",
    "Margen_de_partner_Margen_Soporte__c", "Margen_de_partner_Margen_Soporte_Maps__c",
    "Margen_de_partner_Descuento_GCP__c", "Margen_de_partner_Descuento_GMP__c",
    "Margen_de_partner_Descuento_Soporte__c", "Margen_de_partner_Descuento_Soporte_Maps__c",
    "Desglosar_Facturas__c", "Billing_Model__c",
    "Sop_Tec_Porcent__c", "Sop_Tec_Maps_Porcent__c",
    "Sop_Tec_imp_minimo__c", "Sop_Tec_Maps_imp_minimo__c",
    "Sop_Tec_imp_fijo__c", "Sop_Tec_Maps_Importe_Fijo__c",
    "Control_lectura_anuales_Consumo__c", "Margen_SWO__c",
    "Empresa_IP__c", "GoogleInvoiceTypeOpp__c",
]
OLI_COLUMNS = [
    "OpportunityId", "Descripci_n_del_producto__c", "SKU__c", "CurrencyIsoCode",
    "Fecha_Inicio_Contrato__c", "Fecha_Fin_Contrato__c",
    "Fecha_Inicio_Contrato_Opp__c", "Fecha_Fin_Contrato_Opp__c", "Dominio__c",
]


def read_tfvar(country: str, key: str) -> str | None:
    with open(os.path.join(REPO_ROOT, "tfvars", f"{country}.tfvars"), "r", encoding="utf-8") as fh:
        m = re.search(rf'{key}\s*=\s*"(.*)"', fh.read())
    return m.group(1) if m else None


def records(sf, module: str, columns: list[str], where: str) -> list[dict]:
    query = f"SELECT {', '.join(columns)} FROM {module} WHERE {where}"
    LOG.info("SOQL %s: %s", module, where[:120])
    rows = []
    for rec in sf.query_all(query)["records"]:
        rows.append({c: (None if rec.get(c) is None else str(rec.get(c))) for c in columns})
    return rows


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(description="Extrae inputs SF de mix_and_match a BQ staging.")
    p.add_argument("--country", required=True)
    p.add_argument("--dest-project", required=True, help="proyecto BQ destino (sandbox)")
    p.add_argument("--dest-dataset", required=True, help="dataset BQ destino")
    p.add_argument("--dry-run", action="store_true")
    args = p.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    empresa = read_tfvar(args.country, "sf_empresa_ip")
    if not empresa:
        raise SystemExit(f"sf_empresa_ip vacio en tfvars/{args.country}.tfvars")
    opp_where = empresa + OPP_COND_SUFFIX

    sf = connect_from_env()
    LOG.info("Salesforce: %s | pais %s", sf.sf_instance, args.country)

    opp_rows = records(sf, "Opportunity", OPP_COLUMNS, opp_where)
    LOG.info("Opportunity: %d filas", len(opp_rows))
    # OLI de esas oportunidades (semi-join por Empresa_IP, amplio).
    oli_where = f"OpportunityId IN (SELECT Id FROM Opportunity WHERE {opp_where})"
    oli_rows = records(sf, "OpportunityLineItem", OLI_COLUMNS, oli_where)
    LOG.info("OpportunityLineItem: %d filas", len(oli_rows))

    if args.dry_run:
        LOG.info("DRY-RUN: no se carga en BQ.")
        return 0

    ds = f"{args.dest_project}.{args.dest_dataset}"
    n1 = bq.load_rows(opp_rows, f"{ds}.stg_opportunities", OPP_COLUMNS, args.dest_project)
    n2 = bq.load_rows(oli_rows, f"{ds}.stg_line_items", OLI_COLUMNS, args.dest_project)
    LOG.info("Cargadas %d -> stg_opportunities, %d -> stg_line_items (%s)", n1, n2, ds)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
