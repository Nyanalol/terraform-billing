#!/usr/bin/env python
"""Genera infra/global/terraform.tfvars (config del consolidado) desde countries.yaml.

Fuente única: countries.yaml. Esto produce el mapa `countries` (país -> source_project del
consolidado) y los overrides de dataset (looker/billing) donde difieren del default.

Uso:
    python tools/gen_global_tfvars.py            # imprime a stdout
    python tools/gen_global_tfvars.py --write    # escribe infra/global/terraform.tfvars
    python tools/gen_global_tfvars.py --check     # falla si el fichero actual no coincide
"""
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
COUNTRIES = ROOT / "countries.yaml"
TARGET = ROOT / "infra" / "global" / "terraform.tfvars"

DEFAULT_LOOKER = "looker_views"
DEFAULT_BILLING = "billing_views"


def render() -> str:
    data = yaml.safe_load(COUNTRIES.read_text(encoding="utf-8"))
    rows = sorted(data.items())  # orden estable por código de país

    def block(title, pairs):
        w = max(len(f'"{k}"') for k, _ in pairs)
        body = "\n".join(f'  {f'"{k}"':<{w}} = "{v}"' for k, v in pairs)
        return f"{title} = {{\n{body}\n}}\n"

    countries = [(c, m["consolidado"]["source_project"]) for c, m in rows]
    looker = [(c, m["consolidado"]["looker_dataset"]) for c, m in rows
              if m["consolidado"]["looker_dataset"] != DEFAULT_LOOKER]
    billing = [(c, m["consolidado"]["billing_dataset"]) for c, m in rows
               if m["consolidado"]["billing_dataset"] != DEFAULT_BILLING]

    out = [
        "# GENERADO por tools/gen_global_tfvars.py desde countries.yaml — NO editar a mano.",
        "# Fuente única de la config de países: countries.yaml.",
        "",
        block("countries", countries),
        "# Países antiguos: el consolidado lee sus vistas estándar de 'consolidado_src' (looker_views intacto).",
        block("looker_dataset_overrides", looker).rstrip("\n"),
        "",
        "# La 8ª tabla (importes_lecturas_workspace) donde no está en billing_views.",
        block("billing_dataset_overrides", billing).rstrip("\n"),
    ]
    return "\n".join(out) + "\n"


def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else ""
    content = render()
    if arg == "--write":
        TARGET.write_text(content, encoding="utf-8")
        print(f"escrito {TARGET}")
    elif arg == "--check":
        current = TARGET.read_text(encoding="utf-8") if TARGET.exists() else ""
        if current.strip() == content.strip():
            print("OK: terraform.tfvars coincide con countries.yaml")
        else:
            print("DRIFT: terraform.tfvars NO coincide con countries.yaml (correr --write)")
            sys.exit(1)
    else:
        print(content)


if __name__ == "__main__":
    main()
