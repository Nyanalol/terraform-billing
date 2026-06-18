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

### Estado actual y pendiente para prod (coordinar con Ángel)

- **Sandbox** (`ip-trabajo-apeinado`, dataset compartido `billing_views`): la tabla
  `currencies_exchange_rates` es única, así que un solo run la rellena para todos. ✅ ya funciona.
- **Prod** (un proyecto por país): hoy cada país escribiría su propia
  `{project}.{dataset}.currencies_exchange_rates` (`materialize_importes_*.sql` la leen del
  proyecto del país) → 17× la misma matriz. Lo limpio es una **tabla central** de currencies
  (en el proyecto global) y que los marts la lean de ahí (lectura cross-project + IAM).
  **Pendiente de decidir/implementar con Ángel** (toca el SQL de los marts).
