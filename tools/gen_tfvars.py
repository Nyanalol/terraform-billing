#!/usr/bin/env python
"""Genera los infra/tfvars/<país>.tfvars desde countries.yaml (fuente única).

Qué sale de countries.yaml y qué se deriva:
  project_id, country, billing_cloud_platform_dataset, sf_empresa_ip, payer_billing_accounts
      -> directos de countries.yaml (location siempre "EU" en el módulo).
  currency_symbols   -> constante compartida; 11 símbolos (con BRL) para países antiguos
                        (status != new), 10 para los nuevos. Es lo que hay hoy en los tfvars,
                        y como alimenta un seed job hasheado, mantenerlo evita re-seed espurio.
  scheduled_query_service_account -> bigquery-talend@{project} (solo status new).
  staging_bucket_name -> gcp-billing-process-staging-{suffix} (solo si crea HMAC).
  create_service_account / create_hmac_key -> default por status; overrides en `tf:` del yaml.
  sku_third_party_migration_service_account / manage_spain_iam -> solo si `tf:` los declara.

Uso:
    python tools/gen_tfvars.py [--write] [--check] [--country hong-kong]
"""
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
COUNTRIES = ROOT / "countries.yaml"
TFVARS = ROOT / "infra" / "tfvars"

# Símbolos de divisa: lookup global (idéntico en todos). Los países nuevos no llevan BRL hoy;
# los antiguos sí. Se mantiene esa distinción para no re-disparar el seed job (job_id hasheado).
SYMBOLS_10 = [
    ("EUR", "€"), ("USD", "$"), ("GBP", "£"), ("HKD", "HK$"), ("INR", "₹"),
    ("VND", "₫"), ("MXN", "MX$"), ("COP", "COL$"), ("SGD", "S$"), ("CHF", "Fr"),
]
SYMBOLS_11 = SYMBOLS_10 + [("BRL", "R$")]


def _fmt_map(name, items, indent="  "):
    if not items:
        return [f"{name} = {{}}"]
    out = [f"{name} = {{"]
    for k, v in items:
        out.append(f'{indent}"{k}" = "{v}"')
    out.append("}")
    return out


def render(country: str, meta: dict) -> str:
    tf = meta.get("tf", {}) or {}
    status = meta["status"]
    is_new = status == "new"
    project = meta["project_id"]
    ctx = meta["talend_context"]          # win_xx
    suffix = ctx.split("_", 1)[1]         # xx

    # defaults derivados de status, con override por `tf:`
    create_sa = tf.get("create_service_account", True if is_new else False)
    create_hmac = tf.get("create_hmac_key", True if is_new else False)
    country_name = tf.get("country", country)
    symbols = SYMBOLS_10 if is_new else SYMBOLS_11
    payer = list((meta.get("payer_billing_accounts") or {}).items())

    L = ["# GENERADO por tools/gen_tfvars.py desde countries.yaml — NO editar a mano."]
    if not is_new:
        L.append("# PAÍS ANTIGUO / ESQUELETO — NO desplegar tal cual. Ver docs/MIGRACION_PAISES_ANTIGUOS.md.")
    L += [
        "",
        f'project_id                     = "{project}"',
        f'country                        = "{country_name}"',
        f'billing_cloud_platform_dataset = "{meta["export_dataset"]}"',
        'location                       = "EU"',
        "",
    ]
    L += _fmt_map("payer_billing_accounts", payer)
    L.append("")
    L += _fmt_map("currency_symbols", symbols)
    L.append("")

    if is_new:
        L.append(f'scheduled_query_service_account = "bigquery-talend@{project}.iam.gserviceaccount.com"')
        L.append("")
    if not create_sa:
        L.append("create_service_account = false   # la SA ya existe (creada a mano antes de Terraform)")
    if create_hmac:
        L.append(f'staging_bucket_name = "gcp-billing-process-staging-{suffix}"')
    L.append(f"create_hmac_key     = {str(create_hmac).lower()}")
    L.append("")

    if "sku_third_party_migration_service_account" in tf:
        L.append(f'sku_third_party_migration_service_account = "{tf["sku_third_party_migration_service_account"]}"')
    if "manage_spain_iam" in tf:
        L.append(f"manage_spain_iam = {str(tf['manage_spain_iam']).lower()}")
    if "sku_third_party_migration_service_account" in tf or "manage_spain_iam" in tf:
        L.append("")

    L.append("# Cláusula Empresa_IP__c de Salesforce (config Talend). Ver generate-config-billing.ps1.")
    L.append(f'sf_empresa_ip = "{meta["sf_empresa_ip"]}"')
    return "\n".join(L) + "\n"


def values(text: str) -> dict:
    """Extrae los valores semánticos de un .tfvars (ignora comentarios/espacios/orden)
    para comparar equivalencia con Terraform sin necesitar el binario ni credenciales."""
    import re
    d, in_map, mapname = {}, None, None
    for raw in text.splitlines():
        line = raw.split("#", 1)[0].rstrip()
        if not line.strip():
            continue
        if in_map is not None:
            if line.strip() == "}":
                in_map = None
                continue
            m = re.match(r'\s*"([^"]+)"\s*=\s*"([^"]*)"', line)
            if m:
                d[mapname][m.group(1)] = m.group(2)
            continue
        m = re.match(r'\s*(\w+)\s*=\s*\{\s*\}\s*$', line)   # mapa vacío
        if m:
            d[m.group(1)] = {}
            continue
        m = re.match(r'\s*(\w+)\s*=\s*\{\s*$', line)        # apertura de mapa
        if m:
            mapname = m.group(1); d[mapname] = {}; in_map = mapname
            continue
        m = re.match(r'\s*(\w+)\s*=\s*"(.*)"\s*$', line)    # string
        if m:
            d[m.group(1)] = m.group(2); continue
        m = re.match(r'\s*(\w+)\s*=\s*(true|false)\s*$', line)  # bool
        if m:
            d[m.group(1)] = (m.group(2) == "true"); continue
    return d


def main():
    args = sys.argv[1:]
    only = args[args.index("--country") + 1] if "--country" in args else None
    write, check = "--write" in args, "--check" in args

    data = yaml.safe_load(COUNTRIES.read_text(encoding="utf-8"))
    drift = 0
    for country, meta in sorted(data.items()):
        if only and country != only:
            continue
        content = render(country, meta)
        target = TFVARS / f"{country}.tfvars"
        if write:
            target.write_text(content, encoding="utf-8")
            print(f"escrito {target}")
        elif check:
            cur = target.read_text(encoding="utf-8") if target.exists() else ""
            ok = values(cur) == values(content)
            print(f"  {country:14s}: {'OK' if ok else 'DRIFT'}")
            if not ok:
                a, b = values(cur), values(content)
                keys = set(a) | set(b)
                for k in sorted(keys):
                    if a.get(k) != b.get(k):
                        print(f"      {k}: actual={a.get(k)!r} -> generado={b.get(k)!r}")
                drift += 1
        else:
            print(f"===== {country}.tfvars =====")
            print(content)
    if check and drift:
        sys.exit(1)


if __name__ == "__main__":
    main()
