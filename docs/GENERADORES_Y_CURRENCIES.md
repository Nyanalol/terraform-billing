# Fuente única (`countries.yaml`) + generadores, y currencies

## 1. `countries.yaml` como fuente única

Toda la configuración por país vive en `countries.yaml`. Hay dos consumidores con estrategias
distintas:

**Terraform** usa ficheros generados (artefacto versionado + `--check`):

| Generador | Produce | Notas |
|---|---|---|
| `tools/gen_tfvars.py` | `infra/tfvars/<país>.tfvars` | despliegue por país (versionado: sin secretos) |
| `tools/gen_global_tfvars.py` | `infra/global/terraform.tfvars` | mapa del consolidado |

**ETL** NO usa generador: `etl/src/config.py::load_country_settings` **lee `countries.yaml`
directamente**. El `.env` común queda **solo para secretos** (claves SF) y el modo
(`ETL_MODE=sandbox|prod`). No hay ficheros `.env.<país>`.

Flujo Terraform: se edita `countries.yaml` → `--write` regenera → `--check` valida que no haya drift.
Flujo ETL: se edita `countries.yaml` y ya (la ETL lo lee en cada ejecución).

`gen_tfvars.py --check` compara **por valor semántico** (ignora comentarios, espacios y orden),
que es exactamente lo que evalúa Terraform. Hoy los 17 países dan **OK** (los `.tfvars`
generados son equivalentes a los que había → `terraform plan` = sin cambios). Únicas
particularidades preservadas a propósito:

- **Hong Kong** (único país desplegado): `country = "honk-kong"` es un **typo histórico del
  estado desplegado**. Se mantiene vía `tf.country` para que el plan siga siendo no-op;
  corregirlo es un apply deliberado (re-seed de las tablas lookup).
- `currency_symbols`: 10 símbolos para países `new`, 11 (con BRL) para los antiguos. Es lo
  que había; como alimenta un seed job con `job_id` hasheado, mantener la distinción evita
  re-disparar el seed.

### Derivación de flags por `status`

`gen_tfvars.py` deriva los flags del `.tfvars` del `status`, y solo se declara en el bloque
`tf:` lo que se desvía:

| status | create_service_account | create_hmac_key | staging_bucket | scheduled_query_sa | currency_symbols |
|---|---|---|---|---|---|
| `new` | true (omitido) | true | sí (`...-{sufijo}`) | sí | 10 |
| `legacy_eu` / `cross_region` / `central` | false | false | no | no | 11 |

Overrides actuales: HK (`create_service_account=false`, `country`, `sku_third_party...=""`),
Italia (`create_hmac_key=false`, org policy), Brasil/España (`sku_third_party...`, `manage_spain_iam`).

## 2. Currencies: se ejecuta UNA vez, lista global

Los tipos de cambio son **globales**: `USD→HKD` no depende del país. Por eso:

- `load_country_settings` calcula la **misma** lista `CURRENCIES` para todos los países: la
  unión de las divisas de facturación de los 17 (`currency` en countries.yaml), más USD
  (consumo) y EUR (reporting). No depende del país que se pase.
- El job `get_currencies_exchange_rates` se corre **una sola vez** por periodo y produce la
  matriz completa de pares, que sirve a todos.

### Tabla CENTRAL en el proyecto del consolidado (implementado)

Una sola `currency_exchange_rates` en `swo-billingglobal-prod.billing_reference`
(Terraform `infra/global/reference.tf`; particionada por `rate_date`, clúster por divisa,
con `billing_month` para el JOIN con `invoice_month`). El job la escribe una vez por periodo
(idempotente: `WRITE_TRUNCATE` de la partición del mes) y los marts la leen de ahí.

- **Método de cruces**: fetch DIRECTO de cada par a Hexarate (el más preciso y el validado
  contra Talend), no derivar desde EUR.
- **Brasil**: como BigQuery no une cross-region, hay una copia `billing_reference_sa`
  (southamerica-east1, también en `reference.tf`). El job, al correr para `win_br`, escribe ahí.
- **Resolución de ubicación** (`config.py::load_country_settings`): prod EU → `billing_reference`;
  prod Brasil → `billing_reference_sa`; sandbox → el propio sandbox. Override por env
  `CURRENCIES_PROJECT`/`CURRENCIES_DATASET`.
- **Validado** en sandbox: rates idénticos a la tabla per-país ya validada (121=121, 0 difieren)
  y CH flexibles 5/5 cross-currency → **cero cambio de importes**.

Pendiente de DEPLOY (no de código): `terraform -chdir=infra/global apply` (crea `billing_reference_sa`),
IAM para que el SA de la ETL escriba en `billing_reference*` y los runners de marts lean cross-project,
y el primer run del job en prod para sobreescribir el 202605 de la central con los rates validados.
