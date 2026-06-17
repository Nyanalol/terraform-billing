# swo-gcp-billing — sistema de facturación GCP (monorepo)

Sistema de facturación de Google Cloud por país: extrae consumo (export de Google) y datos de
Salesforce, calcula la facturación (motor `mix_and_match`), la escribe en BigQuery y de vuelta a
Salesforce, y publica un **consolidado** multi-país para reporting.

> Monorepo en construcción — unificación de `terraform-billing` (infra) + `swo-gcp-billing-python`
> (ETL). Ver el plan y las decisiones abiertas en
> [docs/UNIFICACION_PROYECTOS.md](docs/UNIFICACION_PROYECTOS.md).

## Estructura

```
.
├── countries.yaml      # FUENTE ÚNICA de la config de países (17 países)
├── infra/              # Terraform: datasets, tablas, vistas, IAM, scheduled queries, consolidado
│   ├── modules/billing_datasets/   # módulo por país (vistas/tablas, sql/)
│   ├── global/                     # consolidado (looker_views_global)
│   ├── consolidado_src/            # vistas estándar por país antiguo + cadena Brasil (sql/ + deploy.sh)
│   ├── tfvars/                     # config por país (objetivo: generar desde countries.yaml)
│   └── README.md
├── etl/                # ETL Python 3.12+/uv (subtree de swo-gcp-billing-python)
│   ├── src/etl/        # jobs, extract (Salesforce), load (BigQuery)
│   └── config/queries/ # SQL de la ETL (marts mix_and_match, extractores)
├── tools/              # generadores desde countries.yaml + checks (drift de esquema)
└── docs/               # documentación del sistema (incl. CONTRATO_SQL.md)
```

## Las dos mitades

| | Repo origen | Qué hace | Tech |
|---|---|---|---|
| **infra/** | terraform-billing | *Dónde* vive y se publica el dato: datasets, vistas, IAM, scheduled queries, consolidado | Terraform / HCL |
| **etl/** | swo-gcp-billing-python | *Cómo* se produce: extract (SF + export) → transform (mix_and_match) → load BQ → reverse-ETL a SF | Python 3.12+, uv |

El **contrato** entre ambas es el modelo de datos (los esquemas de `importes_lecturas*` y las 7
vistas del consolidado). Ver [docs/CONTRATO_SQL.md](docs/CONTRATO_SQL.md).

## Flujo de extremo a extremo

```
[Salesforce + export GCP] → ETL extract → [staging BQ]
   → mix_and_match (marts) → [importes_lecturas*]
   → reverse-ETL → [Carga_de_lectura__c en Salesforce]
[looker_views / consolidado_src] → UNION (scheduled queries) → [looker_views_global]
```

## Cómo trabajar (hoy, en transición)

- **Infra**: `terraform -chdir=infra ... -var-file=tfvars/<país>.tfvars` (por país);
  `terraform -chdir=infra/global ...` (consolidado). Requiere `GOOGLE_OAUTH_ACCESS_TOKEN` (cuenta
  `g.softwareone.com`) + CA corporativa. Binario en PATH: ver memoria del proyecto.
- **ETL**: `etl/` con `uv` (Python 3.12+). Config de país por `.env.<país>` (objetivo: generar desde `countries.yaml`).

## Estado

- ✅ Consolidado: 17 países en `looker_views_global` (incluida la cadena cross-region de Brasil).
- ✅ ETL: currencies, billing_accounts, get_data, workspace_reseller; motor mix_and_match (flexibles
  validado fila entera; by_project 399/399; soporte 4/4).
- 🚧 Pendiente: completar columnas de by_project/soporte, job orquestador mix_and_match, reverse-ETL,
  terraformizar `consolidado_src` + transfers de Brasil, generadores desde `countries.yaml`, CI.

## Documentación

- [docs/UNIFICACION_PROYECTOS.md](docs/UNIFICACION_PROYECTOS.md) — plan de unificación y decisiones abiertas.
- [docs/DIFERENCIAS_CONSOLIDADO.md](docs/DIFERENCIAS_CONSOLIDADO.md) — transformaciones del consolidado por país.
- [docs/CONTRATO_SQL.md](docs/CONTRATO_SQL.md) — contrato de SQL (dónde vive cada SQL, drift).
- [infra/README.md](infra/README.md) — detalle de la infraestructura Terraform.
- [etl/README.md](etl/README.md) — detalle de la ETL Python.
- [etl/MIX_AND_MATCH_SPEC.md](etl/MIX_AND_MATCH_SPEC.md) — spec del motor de facturación.
