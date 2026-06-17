# `consolidado_src` — fuentes del consolidado por país antiguo

Los países antiguos no exponen sus 7 vistas estándar en `looker_views` (las tienen viejas/typos, o
en otro dataset). Para **no tocar su reporting heredado**, el consolidado lee de un dataset aparte
`consolidado_src` (y `br_src` para Brasil). Esto se creó a mano en la sesión de migración; aquí está
**versionado y reproducible**.

El consolidado (`infra/global/`) las lee vía `looker_dataset_overrides` / `billing_dataset_overrides`
en `infra/global/terraform.tfvars` (generado desde `countries.yaml`).

## Estructura

```
sql/<país>/<vista>.sql   # DDL exacto de cada vista de consolidado_src (extraído de BigQuery)
deploy.sh                # despliegue idempotente (datasets + vistas + cadena Brasil)
```

Países EU (in-vivo): `switzerland, france, uk, germany, netherlands, spain` (7 vistas c/u; España +
`importes_lecturas_workspace`). Brasil: cross-region (ver abajo).

## Despliegue

```bash
bash infra/consolidado_src/deploy.sh all          # todos
bash infra/consolidado_src/deploy.sh france        # un país
bash infra/consolidado_src/deploy.sh brazil        # solo la cadena de Brasil
```

## Brasil — cadena cross-region (southamerica-east1 → EU)

BigQuery no une cross-region; se materializa en BR y se copia a EU. Cadena diaria:
`03:30 BR materializa → 04:00 EU copia → 05:00 EU unión del consolidado`.

### IAM (una vez)
```bash
# SA global (lee la copia) -> READER en el consolidado_src de Brasil
#   (dataset ACL: añadir userByEmail bq-global-union@swo-billingglobal-prod... rol READER)
# SA Talend (materializa) -> WRITER en consolidado_src (ya tiene roles/bigquery.admin en el proyecto)
```

### Transfer 1 — materialización (en ipdb-billing-interno, southamerica-east1, SA Talend, 03:30)
```bash
bq --project_id=ipdb-billing-interno mk --transfer_config \
  --location=southamerica-east1 --data_source=scheduled_query \
  --display_name="brazil_consolidado_src_materialize" \
  --service_account_name="bigquery-talend@ipdb-billing-interno.iam.gserviceaccount.com" \
  --schedule="every day 03:30" \
  --params="{\"query\": \"$(cat infra/scripts/br_materialize.sql)\"}"
```

### Transfer 2 — copia cross-region (en swo-billingglobal-prod, EU, SA global, 04:00)
```bash
bq --project_id=swo-billingglobal-prod mk --transfer_config \
  --location=EU --data_source=cross_region_copy --target_dataset=br_src \
  --display_name="brazil_consolidado_src_to_eu" \
  --service_account_name="bq-global-union@swo-billingglobal-prod.iam.gserviceaccount.com" \
  --schedule="every day 04:00" \
  --params='{"source_project_id":"ipdb-billing-interno","source_dataset_id":"consolidado_src","overwrite_destination_table":"true"}'
```

IDs actuales de los transfers (para `bq update`/`bq rm`):
- materialización: `projects/982456479631/locations/southamerica-east1/transferConfigs/6a2e72e6-0000-2565-a85f-f40304367504`
- copia: `projects/700435170242/locations/europe/transferConfigs/6a3deb93-0000-2859-845c-089e082b23f0`

## Por qué script y no Terraform

Importar ~50 vistas hechas a mano a Terraform (un `import` por recurso) es alto esfuerzo y bajo
valor sobre un script idempotente. El repo ya usa scripts para operaciones del consolidado
(`infra/refresh-consolidado.ps1`). Los DDL versionados en `sql/` son la fuente de verdad; si se
quisiera Terraform en el futuro, se generaría desde estos `.sql`.

## Verificación

`python tools/check_consolidado_schema.py` → las 7 vistas cuadran (nombre:tipo) en los 17 países.
