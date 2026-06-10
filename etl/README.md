# ETL de facturación (migración desde Talend)

Sustituye al ETL de Talend (`C:\facturacion\swo-product_facturacion-es`). Ver
[AUDIT.md](AUDIT.md) para el análisis de los jobs originales y el plan de migración.

## Arquitectura

- **Python (extracción/carga)** — único punto que toca Salesforce y APIs externas.
- **BigQuery SQL (transformación)** — gestionado con Terraform (vistas / scheduled queries).
- **Orquestación**: Cloud Run + Cloud Scheduler (destino final).

Los datos intermedios viven en BigQuery, no en CSV. Cada job se migra de uno en uno,
corriendo en paralelo con Talend y comparando las tablas BQ hasta que cuadran.

## Estado de la migración

| Job Talend | Estado | Destino |
|---|---|---|
| `currencies_exchange_rates` | 🟡 en curso | `currencies/fetch_exchange_rates.py` → `billing_reference.currency_exchange_rates` |
| `diary_get/write_billing_accounts` | ⏳ pendiente | Python (SOQL) + BQ SQL |
| `get_data` / `get_data_workspace` | ⏳ pendiente | columnas `total_*` a las vistas |
| `workspace_reseller` | ⏳ pendiente | Python (SOQL) + BQ SQL + UPSERT SF |
| `mix_and_match` | ⏳ pendiente | Python (SOQL) + BQ SQL + UPSERT SF |
| `write_data` | ⏳ se elimina | las tablas se escriben directas desde SQL |

## currencies — tipos de cambio

Pide a Hexarate `EUR→cada divisa` para el cierre del mes y deriva la matriz completa de
parejas. Carga idempotente en la partición `rate_date` de la tabla compartida del proyecto
global (`swo-billingglobal-prod.billing_reference.currency_exchange_rates`, creada por
Terraform en `global/reference.tf`).

```bash
# validar sin tocar BQ (solo stdlib):
python etl/currencies/fetch_exchange_rates.py --month 202605 --dry-run

# cargar de verdad (requiere google-cloud-bigquery y credenciales con write en el proyecto global):
python etl/currencies/fetch_exchange_rates.py --month 202605
```

Sin `--month`, usa el mes anterior al actual (el que se factura).
