# `sql/` — contrato de SQL del sistema (fuente única declarada)

> El SQL del sistema vive físicamente en dos sitios por una razón técnica (el `etl/` se trae por
> **git subtree** del repo de Ángel y mover sus ficheros rompería el `subtree pull`). Por eso, en
> vez de un único directorio físico, este `sql/` define **el contrato**: qué SQL existe, cuál es la
> versión canónica, dónde vive y qué se valida en CI. La consolidación física es Fase 1 (ver
> [docs/UNIFICACION_PROYECTOS.md](UNIFICACION_PROYECTOS.md)) y se hará cuando el equipo
> congele el repo separado de Ángel y se trabaje solo en el monorepo.

## Dónde vive cada SQL hoy

| Dominio | Ubicación física | Dueño | Lo ejecuta/publica |
|---|---|---|---|
| **Modelo** (vistas: `sum_costs_*`, `consumos_por_account`, `importes_lecturas_*`, `billing_*`) | `infra/modules/billing_datasets/sql/` | Infra (Terraform) | Terraform las crea como vistas |
| **Marts mix_and_match** (`materialize_importes_flexibles/by_project/soporte.sql`) | `etl/config/queries/` | ETL (Ángel) | El job Python las ejecuta → `importes_lecturas*` |
| **Extractores** (`opportunities`, `line_items`, `all_opportunities`, `get_data_*`) | `etl/config/queries/` | ETL (Ángel) | Jobs Python (extract/staging) |
| **Consolidado** (UNION ALL de los 17 países) | `infra/global/locals.tf` (generado en HCL) | Infra | Scheduled queries del componente `global/` |
| **Materialización Brasil** | `infra/scripts/br_materialize.sql` | Infra | Scheduled query en southamerica-east1 |

## Fase 1 (hecha 2026-06-16): NO hay duplicación de lógica

Al investigar resultó que **no hay SQL de lógica duplicado** entre infra y etl:

- Las **vistas con lógica** de infra (`billing_gcp`, `sum_costs_*`, `reseller_view`, las 7
  `looker_views`) se cargan vía `templatefile()` y son el **modelo** que publica Terraform.
- Las **tablas** tipo `importes_lecturas_*` / `billing_accounts` tienen su esquema en
  `tables_billing_views.tf` (`schema = jsonencode([...])`, con `ignore_changes=[schema]` porque
  las llena la ETL/Talend). El esquema real está ahí, **no** en un `.sql`.
- Los ficheros `sql/billing_views/{importes_lecturas_*,billing_accounts*}.sql` y varios de
  `sql/billing_cloud_platform/`, `sql/third_party/` son **stubs vestigiales NO referenciados por
  ningún `.tf`** (restos de un diseño anterior). Estaban además **desincronizados** (al de
  `importes_lecturas_temp` le faltaba `Margen_SWO`). → **Recomendación: borrarlos** (no se usan).
  No se borraron en esta sesión por prudencia; dejar la decisión al equipo.
- Los marts de la ETL (`etl/config/queries/`) producen el dato; no hay vista de infra que
  recalcule lo mismo. La separación "infra=esquema/dónde, etl=lógica/cómo" **ya existe de facto**.

## Lo que valida CI

- **`tools/check_consolidado_schema.py`**: las 7 vistas del consolidado tienen el mismo esquema
  (nombre:tipo, con numéricos coercibles normalizados) en los 17 países → caza el drift real que
  sufrimos (SKU STRING vs FLOAT64 en España, +4 columnas de `consumos_por_account`). Verificado:
  17/17 cuadran.
- Validaciones de importe vs Talend (ya hechas: flexibles fila entera; by_project 399/399; soporte 4/4).

## Apéndice: el modelo de datos (vistas que publica la infra)

Las 7 vistas estándar que une el consolidado: `consumos_por_account`, `consumos_por_proyecto_new`,
`consumos_support_flex`, `gcp_billing_adjustment`, `consumos_google_reseller_factura`,
`importes_lecturas`, `vista_importes_lecturas` (+ `importes_lecturas_workspace`). Ver
[docs/DIFERENCIAS_CONSOLIDADO.md](DIFERENCIAS_CONSOLIDADO.md) para las transformaciones por país.
