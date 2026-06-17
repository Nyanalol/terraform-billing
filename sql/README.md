# `sql/` — contrato de SQL del sistema (fuente única declarada)

> El SQL del sistema vive físicamente en dos sitios por una razón técnica (el `etl/` se trae por
> **git subtree** del repo de Ángel y mover sus ficheros rompería el `subtree pull`). Por eso, en
> vez de un único directorio físico, este `sql/` define **el contrato**: qué SQL existe, cuál es la
> versión canónica, dónde vive y qué se valida en CI. La consolidación física es Fase 1 (ver
> [docs/UNIFICACION_PROYECTOS.md](../docs/UNIFICACION_PROYECTOS.md)) y se hará cuando el equipo
> congele el repo separado de Ángel y se trabaje solo en el monorepo.

## Dónde vive cada SQL hoy

| Dominio | Ubicación física | Dueño | Lo ejecuta/publica |
|---|---|---|---|
| **Modelo** (vistas: `sum_costs_*`, `consumos_por_account`, `importes_lecturas_*`, `billing_*`) | `infra/modules/billing_datasets/sql/` | Infra (Terraform) | Terraform las crea como vistas |
| **Marts mix_and_match** (`materialize_importes_flexibles/by_project/soporte.sql`) | `etl/config/queries/` | ETL (Ángel) | El job Python las ejecuta → `importes_lecturas*` |
| **Extractores** (`opportunities`, `line_items`, `all_opportunities`, `get_data_*`) | `etl/config/queries/` | ETL (Ángel) | Jobs Python (extract/staging) |
| **Consolidado** (UNION ALL de los 17 países) | `infra/global/locals.tf` (generado en HCL) | Infra | Scheduled queries del componente `global/` |
| **Materialización Brasil** | `infra/scripts/br_materialize.sql` | Infra | Scheduled query en southamerica-east1 |

## Duplicación detectada (a reconciliar en Fase 1)

| Pieza | Como VISTA (infra) | Como TRANSFORMACIÓN (etl) | Canónica propuesta |
|---|---|---|---|
| `importes_lecturas_by_project` | `infra/.../sql/billing_views/importes_lecturas_by_project.sql` | `etl/config/queries/materialize_importes_by_project.sql` | **etl** (la que produce el dato); la "vista" pasa a describir el esquema/contrato |
| `importes_lecturas` (flexibles) | `infra/.../sql/billing_views/importes_lecturas_temp.sql` | `etl/config/queries/materialize_importes_flexibles.sql` | **etl** |
| `importes_lecturas_workspace` | `infra/.../sql/billing_views/importes_lecturas_workspace.sql` | `etl/.../workspace_reseller_pipeline` | **etl** |
| `billing_accounts` | `infra/.../sql/billing_views/billing_accounts.sql` | `etl/config/queries/materialize_billing_accounts.sql` | **etl** |

Regla: **la ETL produce el dato; la infra define dónde vive y publica el esquema.** Donde hoy hay
una vista que "calcula", la canónica pasa a ser el mart de la ETL, y la infra se queda con la
definición de tabla/esquema (el contrato).

## Lo que valida CI (objetivo)

- Que el **esquema de salida** de cada mart (`importes_lecturas*`) coincide con lo que la vista del
  **consolidado** (`looker_views_global`) espera unir → evita el drift que vimos esta semana
  (p.ej. `consumos_por_account` con +4 columnas derivadas, SKU STRING vs FLOAT64 en España).
- Validaciones de importe vs Talend (ya hechas: flexibles fila entera; by_project 399/399; soporte 4/4).

## Apéndice: el modelo de datos (vistas que publica la infra)

Las 7 vistas estándar que une el consolidado: `consumos_por_account`, `consumos_por_proyecto_new`,
`consumos_support_flex`, `gcp_billing_adjustment`, `consumos_google_reseller_factura`,
`importes_lecturas`, `vista_importes_lecturas` (+ `importes_lecturas_workspace`). Ver
[docs/DIFERENCIAS_CONSOLIDADO.md](../docs/DIFERENCIAS_CONSOLIDADO.md) para las transformaciones por país.
