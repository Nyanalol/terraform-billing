#!/usr/bin/env python
"""Genera los etl/.env.<talend_context> desde countries.yaml (fuente única).

Modo:
  sandbox (default): todo a ip-trabajo-apeinado / billing_raw / billing_views (como las .env de Angel).
  prod             : BQ_PROJECT_ID = proyecto real del país; BQ_RAW_DATASET = export_dataset.

Uso:
    python tools/gen_env.py [--mode sandbox|prod] [--write] [--check] [--country win_es]
"""
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
COUNTRIES = ROOT / "countries.yaml"
ETL = ROOT / "etl"

SANDBOX_PROJECT = "ip-trabajo-apeinado"


def empresa_code(clause: str) -> str:
    """De la cláusula Talend a SF_EMPRESA_CODE: código pelado si es único; cláusula (OR) si son varios."""
    codes = re.findall(r"Empresa_IP__c='([^']+)'", clause)
    if len(codes) == 1:
        return codes[0]
    return "(" + " OR ".join(f"Empresa_IP__c='{c}'" for c in codes) + ")"


# Divisas SIEMPRE necesarias aunque un país no las facture:
#   USD = moneda del consumo (el export de Google viene en USD)
#   EUR = moneda de reporting del consolidado
BASE_CURRENCIES = ["EUR", "USD"]


def global_currencies(data: dict) -> list[str]:
    """Unión GLOBAL de divisas = USD + EUR + la divisa de facturación de cada país.
    Los tipos de cambio son globales (USD→HKD no depende del país), así que el job
    get_currencies_exchange_rates se ejecuta UNA vez con esta lista y produce la matriz
    completa que sirve a todos. Ver docs (orquestación) para la tabla central en prod."""
    cur = list(BASE_CURRENCIES)
    for meta in data.values():
        c = meta.get("currency")
        if c and c not in cur:
            cur.append(c)
    return cur


def render(ctx: str, meta: dict, mode: str, currencies: str) -> str:
    if mode == "prod":
        project = meta["project_id"]
        raw = meta["export_dataset"]
    else:
        project = SANDBOX_PROJECT
        raw = "billing_raw"
    lines = [
        f"# GENERADO por tools/gen_env.py (--mode {mode}) desde countries.yaml — NO editar a mano.",
        f"# País: {ctx}. Comunes en .env; periodo (mes/año) por CLI.",
        "",
        f"SF_EMPRESA_CODE={empresa_code(meta['sf_empresa_ip'])}",
        "",
        f"BQ_PROJECT_ID={project}",
        f"BQ_RAW_DATASET={raw}",
        "BQ_TRANSFORMED_DATASET=billing_views",
        "BQ_INPUT_DATASET=billing_views",
        "BQ_WORKSPACE_DATASET=billing_views",
        "",
        f"# Divisa de facturación de este país: {meta.get('currency', '?')}.",
        "# CURRENCIES es la lista GLOBAL (igual en todos los países): el job de currencies",
        "# se corre UNA sola vez y rellena la matriz completa de tipos de cambio.",
        f"CURRENCIES={currencies}",
    ]
    return "\n".join(lines) + "\n"


def main():
    args = sys.argv[1:]
    mode = "sandbox"
    if "--mode" in args:
        mode = args[args.index("--mode") + 1]
    only = args[args.index("--country") + 1] if "--country" in args else None
    write, check = "--write" in args, "--check" in args

    data = yaml.safe_load(COUNTRIES.read_text(encoding="utf-8"))
    currencies = ",".join(global_currencies(data))
    drift = 0
    for ctx_country, meta in sorted(data.items()):
        ctx = meta["talend_context"]
        if only and ctx != only:
            continue
        content = render(ctx, meta, mode, currencies)
        target = ETL / f".env.{ctx}"
        if write:
            target.write_text(content, encoding="utf-8")
            print(f"escrito {target}")
        elif check:
            cur = target.read_text(encoding="utf-8") if target.exists() else ""
            # comparar solo las líneas KEY=VALUE (ignora comentarios)
            kv = lambda t: sorted(l for l in t.splitlines() if "=" in l and not l.startswith("#"))
            ok = kv(cur) == kv(content)
            print(f"  {ctx}: {'OK' if ok else 'DRIFT'}")
            drift += 0 if ok else 1
        else:
            print(f"===== .env.{ctx} =====")
            print(content)
    if check and drift:
        sys.exit(1)


if __name__ == "__main__":
    main()
