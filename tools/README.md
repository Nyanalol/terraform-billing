# `tools/` — generadores desde `countries.yaml`

`countries.yaml` (raíz) es la **fuente única** de la config de país. Se edita ahí y de ahí salen
los ficheros de Terraform. La **ETL no usa generador**: lee `countries.yaml` directamente
(`etl/src/config.py::load_country_settings`). Ver [docs/GENERADORES_Y_CURRENCIES.md](../docs/GENERADORES_Y_CURRENCIES.md).

| Script | Genera | Verificación |
|---|---|---|
| `gen_tfvars.py` | `infra/tfvars/<país>.tfvars` (despliegue por país) | `--check` = OK en los 17 (compara por valor → `terraform plan` sin cambios) |
| `gen_global_tfvars.py` | `infra/global/terraform.tfvars` (mapa del consolidado + overrides) | `terraform plan` = *No changes* |

## Uso

```bash
# tfvars por país
python tools/gen_tfvars.py                       # stdout (todos)
python tools/gen_tfvars.py --country hong-kong   # stdout (uno)
python tools/gen_tfvars.py --write               # escribe infra/tfvars/*.tfvars
python tools/gen_tfvars.py --check               # CI: drift vs countries.yaml (por valor semántico)

# Consolidado (Terraform)
python tools/gen_global_tfvars.py --write        # escribe infra/global/terraform.tfvars
python tools/gen_global_tfvars.py --check        # CI: drift vs countries.yaml
```

Los `.tfvars` se versionan (no llevan secretos; el equipo los necesita para desplegar) pero son
artefacto generado: `--check` garantiza que no divergen de `countries.yaml`.

La ETL elige proyecto/dataset por `ETL_MODE` (env, default `sandbox`):
- **sandbox** (default): `ip-trabajo-apeinado` / `billing_raw` / `billing_views` (pruebas).
- **prod**: `BQ_PROJECT_ID` = proyecto real del país; `BQ_RAW_DATASET` = `export_dataset`.

Requiere `pyyaml` (en `etl/pyproject.toml`; para los scripts de `tools/`, el `python` del sistema).

## Pendiente (ampliable)

- Añadir `--check` de ambos generadores al CI (`.github/workflows/ci.yml`).
