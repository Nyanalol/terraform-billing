#!/usr/bin/env python
"""Verifica que las 7 vistas del consolidado tienen el MISMO esquema (nombre:tipo) en los 17 países.

El UNION ALL del consolidado es posicional: si un país difiere en una columna/tipo, la unión falla
o mete drift. Esto caza justo lo que sufrimos esta sesión (SKU STRING vs FLOAT64 en España, las 4
columnas derivadas de consumos_por_account, etc.). Lee los países de countries.yaml.

Uso:
    python tools/check_consolidado_schema.py [--ref vietnam]
Requiere el CLI `bq` autenticado (cuenta g.softwareone.com).
"""
import subprocess
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
COUNTRIES = ROOT / "countries.yaml"

VIEWS = [
    "importes_lecturas", "vista_importes_lecturas", "consumos_por_account",
    "consumos_por_proyecto_new", "consumos_support_flex", "gcp_billing_adjustment",
    "consumos_google_reseller_factura",
]


# Tipos numéricos que el UNION ALL coacciona entre sí (no son drift real).
_NUM = {"INT64": "NUM", "NUMERIC": "NUM", "BIGNUMERIC": "NUM", "FLOAT64": "NUM"}


def schema_sig(project: str, dataset: str, view: str) -> str:
    # Normaliza el tipo: los numéricos coercibles cuentan como iguales (la unión los une).
    q = (f"SELECT STRING_AGG(CONCAT(column_name,':',"
         f"CASE data_type WHEN 'INT64' THEN 'NUM' WHEN 'NUMERIC' THEN 'NUM' "
         f"WHEN 'BIGNUMERIC' THEN 'NUM' WHEN 'FLOAT64' THEN 'NUM' ELSE data_type END) "
         f"ORDER BY ordinal_position) "
         f"FROM `{project}.{dataset}.INFORMATION_SCHEMA.COLUMNS` WHERE table_name='{view}'")
    cmd = (f'bq --project_id={project} --location=EU query '
           f'--use_legacy_sql=false --format=csv "{q}"')
    out = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    lines = [l for l in out.stdout.splitlines() if l and l != "f0_"]
    return lines[-1].strip('"') if lines else ""


def main():
    args = sys.argv[1:]
    ref = args[args.index("--ref") + 1] if "--ref" in args else "vietnam"
    data = yaml.safe_load(COUNTRIES.read_text(encoding="utf-8"))

    drift = 0
    for view in VIEWS:
        sigs = {}
        for country, meta in data.items():
            c = meta["consolidado"]
            sigs[country] = schema_sig(c["source_project"], c["looker_dataset"], view)
        ref_sig = sigs.get(ref) or next(iter(sigs.values()))
        bad = {c: s for c, s in sigs.items() if s and s != ref_sig}
        missing = [c for c, s in sigs.items() if not s]
        if not bad and not missing:
            print(f"  OK   {view} (17 países cuadran)")
        else:
            drift += 1
            print(f"  DRIFT {view}:")
            for c in bad:
                print(f"        {c}: difiere del ref ({ref})")
            if missing:
                print(f"        sin la vista: {missing}")
    if drift:
        print(f"\n{drift} vista(s) con drift entre países.")
        sys.exit(1)
    print("\nConsolidado OK: las 7 vistas cuadran en los 17 países.")


if __name__ == "__main__":
    main()
