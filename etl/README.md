# SWO GCP Billing - Pipeline de Facturación

Migración de jobs de facturación de Talend a Python 3.12+ / GCP.

## Estructura

```
src/
├── config.py                           # Pydantic Settings (.env + .env.{country})
├── etl/
│   ├── main.py                         # Orquestador CLI
│   ├── extract/
│   │   └── salesforce_extractor.py     # SF OAuth JWT, queries paralelas, Bulk API
│   ├── load/
│   │   └── bigquery_loader.py          # BQ staging, load, execute_query
│   └── jobs/
│       ├── get_billing_accounts.py     # ✅ Migrado
│       ├── get_data.py                 # ✅ Migrado
│       ├── get_currencies_exchange_rates.py  # ✅ Migrado
│       └── workspace_reseller_pipeline.py    # ✅ Migrado (unificado)
├── utils/
│   ├── logging_config.py              # structlog JSON
│   └── gcp_clients.py                 # Factories GCP
config/
└── queries/                           # Templates SQL parametrizados
docker/
└── Dockerfile                         # Cloud Run ready
```

## Jobs Migrados

### 1. `get_billing_accounts`

Extrae cuentas de facturación de Salesforce y materializa en BigQuery.

```
SF (3 queries paralelas) → BQ raw_* (TRUNCATE)
                              ↓
                   materialize SQL (backup + rebuild)
                              ↓
               billing_accounts + billing_accounts_full
```

### 2. `workspace_reseller_pipeline`

Pipeline unificado (antes eran 2 jobs Talend: `get_data_workspace` + `workspace_reseller`).

```
BQ reseller_view → bq_workspace_reseller (staging)
                        ↓
          SF queries paralelas (opportunities, line_items, excluded)
                        ↓
          Cross-reference + clasificación (PASS / REJECT / NA)
                        ↓
          ├─ SF Lectura__c (INSERT solo PASS)
          └─ BQ importes_lecturas_workspace (TODOS, DELETE+APPEND idempotente)
```

### 3. `get_data`

Extrae datos de facturación por grupos (billing/project) desde BigQuery.

### 4. `get_currencies_exchange_rates`

Obtiene tipos de cambio de divisas.

### 5. `mix_and_match` — **Pendiente de migración**

Job principal de cruce de datos de facturación. Es el más complejo.

## Instalación

```bash
uv sync
cp .env.example .env          # Rellenar credenciales comunes
cp .env.example .env.win_uk   # Rellenar config de país
```

## Configuración

Jerarquía de variables de entorno:

| Archivo | Contenido |
|---------|-----------|
| `.env` | Comunes: `SF_USER`, `SF_PRIVATE_KEY`, `SF_CLIENT_ID`, `SF_SKUS`, `CURRENCIES` |
| `.env.{country}` | Por país: `BQ_PROJECT_ID`, `BQ_RAW_DATASET`, `SF_EMPRESA_CODE`, etc. |
| CLI args | Runtime: `--country`, `--month`, `--year` |

## Ejecución

```bash
# Via orquestador
python -m src.etl.main --job get_billing_accounts --country win_uk --month 5 --year 2026
python -m src.etl.main --job workspace_reseller --country win_uk --month 5 --year 2026

# Directamente
python -m src.etl.jobs.get_billing_accounts --country win_uk --month 5 --year 2026
python -m src.etl.jobs.workspace_reseller_pipeline --country win_uk --month 05 --year 2026
```

## Stack

- **Python 3.12+** con `uv` como package manager
- **Pydantic v2** para config y validación
- **simple-salesforce** con OAuth JWT (no passwords)
- **google-cloud-bigquery** para lectura/escritura BQ
- **structlog** para logging JSON (Cloud Logging compatible)
- **asyncio** para queries paralelas a SF

## Principios

- Sin credenciales hardcodeadas (`.env` + Secret Manager)
- Idempotencia: re-ejecuciones seguras (DELETE+APPEND por periodo)
- Logging estructurado JSON en cada operación
- Type hints estrictos en todo el código
