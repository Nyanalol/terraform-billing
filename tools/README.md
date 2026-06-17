# `tools/` — generadores desde `countries.yaml`

Eliminan el doble mantenimiento de la config de país: se edita **solo `countries.yaml`** y de ahí
se generan los ficheros que consumen Terraform y la ETL (Fase 2 de [docs/UNIFICACION_PROYECTOS.md](../docs/UNIFICACION_PROYECTOS.md)).

| Script | Genera | Verificación |
|---|---|---|
| `gen_global_tfvars.py` | `infra/global/terraform.tfvars` (mapa del consolidado + overrides) | `terraform plan` = *No changes* (equivalente a lo desplegado) |
| `gen_env.py` | `etl/.env.<talend_context>` (config de país de la ETL) | reproduce las `.env.win_es`/`.env.win_uk` de Angel (modo sandbox) |

## Uso

```bash
# Consolidado (Terraform)
python tools/gen_global_tfvars.py            # stdout
python tools/gen_global_tfvars.py --write    # escribe infra/global/terraform.tfvars
python tools/gen_global_tfvars.py --check    # CI: falla si hay drift vs countries.yaml

# ETL (.env por país)
python tools/gen_env.py --mode sandbox --country win_es   # stdout (sandbox: ip-trabajo-apeinado)
python tools/gen_env.py --mode prod --write               # escribe .env.<país> de todos (proyecto real)
python tools/gen_env.py --mode sandbox --check            # CI: drift vs countries.yaml
```

- **Modo sandbox** (default): apunta a `ip-trabajo-apeinado` / `billing_raw` / `billing_views` (pruebas).
- **Modo prod**: `BQ_PROJECT_ID` = proyecto real del país; `BQ_RAW_DATASET` = `export_dataset`.

Requiere `pip install pyyaml` (o el `python` del sistema, que ya lo trae).

## Pendiente (Fase 2, ampliable)

- Generar también los `infra/tfvars/<país>.tfvars` per-país (hoy tienen campos extra que
  `countries.yaml` aún no captura: `payer_billing_accounts`, `currency_symbols`, flags HMAC/SA).
  Enriquecer `countries.yaml` o generar solo el subconjunto y dejar el resto en plantilla.
- Añadir `--check` de ambos generadores al CI (`.github/workflows/ci.yml`).
