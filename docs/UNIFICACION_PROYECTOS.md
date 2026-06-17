# Unificación: `terraform-billing` (infra) + `swo-gcp-billing-python` (ETL)

> Análisis de si tiene sentido unir los dos proyectos del sistema de facturación GCP, qué
> sinergias hay, cómo se estructuraría y los pasos a seguir. Escrito el 2026-06-16.

---

## 0. Resumen ejecutivo (TL;DR)

- **Sí tiene sentido unirlos.** Son **las dos mitades de un mismo sistema**: este repo define
  *dónde* vive y se publica el dato (infra BigQuery + consolidado), y el de Ángel define *cómo*
  se produce (ETL: Salesforce/GCP → transformaciones → BigQuery → vuelta a Salesforce).
- Hoy comparten un **contrato implícito** (el modelo de datos / esquemas), pero al estar en repos
  distintos **se duplica SQL y configuración** y hay **riesgo de desincronización** (drift).
- **Recomendación**: **monorepo** con separación clara `infra/` + `etl/` + `sql/` (fuente única
  de SQL), **un solo mapa de países**, y orquestación (Cloud Run jobs provisionados por Terraform).
- Migración **por fases**, sin romper la facturación en producción.

---

## 1. Qué es cada proyecto hoy

### `terraform-billing` (este repo) — la INFRAESTRUCTURA ("dónde")
- **Terraform**: módulo `modules/billing_datasets` que despliega, por país, los datasets BigQuery
  (export, `billing_views`, `looker_views`, `third_party`), tablas, vistas, scheduled queries,
  service accounts e IAM. Root por país (`tfvars/<país>.tfvars`, backend GCS con prefix por país).
- **`global/`**: el **consolidado** (UNION ALL de los 17 países → `looker_views_global`, scheduled
  queries diarias, cross-region para Brasil). Lo construido esta semana.
- **`modules/billing_datasets/sql/`**: los DDL de las vistas/tablas (el **modelo de datos**:
  `sum_costs_credits_per_month`, `consumos_por_account`, `importes_lecturas_*`, etc.).
- **PowerShell**: `deploy-countries.ps1`, `generate-config-billing.ps1`, `refresh-consolidado.ps1`.
- **`etl/`**: ⚠️ trabajo Python **previo** (currencies, billing_accounts, extractor mix_and_match)
  que **ha quedado superado** por el repo de Ángel → candidato a borrar/migrar.

### `swo-gcp-billing-python` (repo de Ángel) — la ETL ("cómo")
- **`src/etl/`**: framework Python 3.12+/uv. `jobs/` (get_billing_accounts, currencies, get_data,
  workspace_reseller_pipeline), `extract/salesforce_extractor.py`, `load/bigquery_loader.py`,
  `utils/`, `main.py`, `config.py`.
- **`config/queries/`**: el **SQL de la lógica ETL** — los 3 marts del motor `mix_and_match`
  (`materialize_importes_flexibles/by_project/soporte.sql`), extractores (`opportunities`,
  `line_items`), `materialize_billing_accounts`, `init_partitioned_tables`.
- **`dbt/`**, **`docker/Dockerfile`**, **`tests/`**, `pyproject.toml` (uv), `MIX_AND_MATCH_SPEC.md`.
- Deps: `google-cloud-bigquery`, `simple-salesforce`, `google-cloud-secret-manager`.

---

## 2. El problema actual: "split-brain"

Ambos repos tocan el **mismo modelo de datos** pero por separado:

| Síntoma | Detalle |
|---|---|
| **SQL duplicado** | `importes_lecturas_by_project` existe como **vista** en `terraform/sql/billing_views/` y como **transformación** en `python/config/queries/materialize_importes_by_project.sql`. Igual con `billing_accounts`, `sum_costs...`. |
| **Doble config de países** | El mapa de 17 países está en `tfvars/` (Terraform) **y** en la config del Python. Cambiar un país obliga a tocar dos sitios. |
| **Drift de esquema** | Si la ETL cambia una columna de salida y la vista/`consolidado_src` no se actualiza (o al revés), la unión del consolidado o el dashboard se rompen. Esta semana ya lo vimos con `consumos_por_account` (+4 columnas derivadas). |
| **Dos despliegues** | Infra se aplica con Terraform; la ETL corre a mano / Talend / (futuro) Cloud Run. No hay un "deploy del sistema" único. |
| **Piezas fuera de IaC** | Los `consolidado_src` por país y los 2 transfers de Brasil se crearon con `bq`/API, **no están en Terraform** todavía. |
| **`etl/` viejo en infra** | Duplica lo que ahora vive (mejor) en el repo de Ángel. |

---

## 3. ¿Tiene sentido unirlos? — Sí, y por qué

El **contrato entre los dos es el modelo de datos**. Cuando dos componentes comparten un contrato
que cambia a la vez, tenerlos juntos elimina el drift y el doble mantenimiento. Concretamente:

- La ETL **escribe** en tablas que la infra **provisiona**; la infra **lee** (vistas/consolidado)
  lo que la ETL escribe. Es un único pipeline lógico partido en dos repos.
- El **flujo de extremo a extremo** hoy salta de repo en repo sin un dueño único:

```
[Salesforce + export GCP]
        │  (ETL Python: extract)            ← repo Ángel
        ▼
[staging BQ] ── mix_and_match (SQL marts) ─►[importes_lecturas...]   ← repo Ángel (lógica)
        │                                          en tablas que...
        ▼                                          ...define Terraform ← este repo (infra)
[looker_views / consolidado_src] ── UNION ──►[looker_views_global]   ← este repo (global/)
        │
        ▼
[reverse-ETL → Carga_de_lectura__c en Salesforce]                    ← repo Ángel (pendiente)
```

---

## 4. Sinergias concretas

| Sinergia | Qué se gana |
|---|---|
| **Fuente única de SQL** | Un solo `sql/` con los marts y las vistas. La ETL los ejecuta; Terraform los publica como vistas/scheduled queries. Cero duplicación, cero drift. |
| **Un solo mapa de países** | Un `countries.yaml`/`.tfvars` que consumen **ambos** (Terraform vía tfvars, Python vía loader). Añadir país = un sitio. |
| **Deploy del sistema** | `terraform apply` provisiona infra **y** los Cloud Run jobs + Cloud Scheduler que ejecutan la ETL. Un solo "estado deseado". |
| **Esquemas como contrato** | El esquema de salida de cada mart (p.ej. `importes_lecturas`) se valida contra la vista del consolidado en CI → no se mergea algo que rompa la unión. |
| **Onboarding y CI/CD único** | Un repo, un README, un pipeline (lint Python + `terraform validate` + tests + diff de esquemas). |
| **Observabilidad común** | Logs/alertas de la cadena entera (extract → marts → consolidado → reverse-ETL) en un sitio. |
| **Reutiliza lo de esta semana** | El consolidado y los `consolidado_src`/transfers de Brasil entran al mismo IaC. |

---

## 5. Opciones de unificación

### Opción A — Monorepo (RECOMENDADA)
Un repo con separación por tecnología y un `sql/` compartido. Máxima sinergia; convive bien con
toolchains distintos (carpetas + jobs de CI distintos).

**Pros**: elimina drift y duplicación, un deploy, un onboarding.
**Contras**: hay que migrar/mover código y reconciliar el SQL duplicado; cambia gobernanza
(acordar con Ángel quién es owner de qué carpeta).

### Opción B — Dos repos con "contrato"
Se quedan separados, pero se formaliza la interfaz: el `sql/` compartido se publica como
**submódulo git** o paquete versionado, y el mapa de países como artefacto común.

**Pros**: menos disrupción, cada equipo mantiene su repo.
**Contras**: sinergia parcial; el contrato hay que vigilarlo a mano; sigue habiendo dos deploys.

> Recomendación: **A (monorepo)**. B solo si la gobernanza/equipos lo exigen a corto plazo.

---

## 6. Estructura propuesta (monorepo)

```
swo-gcp-billing/                      # repo unificado
├── README.md                         # visión de todo el sistema
├── countries.yaml                    # ÚNICO mapa de países (lo leen infra y etl)
│
├── infra/                            # Terraform (= este repo, movido)
│   ├── modules/billing_datasets/     # datasets, tablas, vistas, IAM, scheduled queries
│   ├── global/                       # consolidado (looker_views_global)
│   ├── orchestration/                # NUEVO: Cloud Run jobs + Cloud Scheduler de la ETL
│   ├── tfvars/                        # por país (generados desde countries.yaml)
│   └── ...
│
├── etl/                              # Python (= repo de Ángel, movido)
│   ├── src/etl/                       # jobs, extract, load, utils, main
│   ├── pyproject.toml / uv.lock
│   ├── docker/Dockerfile
│   └── tests/
│
├── sql/                             # FUENTE ÚNICA de SQL (resuelve la duplicación)
│   ├── model/                        # vistas del modelo (billing_views, looker_views) → las publica Terraform
│   ├── marts/                        # mix_and_match: flexibles, by_project, soporte → las ejecuta la ETL
│   └── consolidado/                  # union del consolidado (hoy generado en global/locals.tf)
│
├── docs/                            # specs + esta documentación + DIFERENCIAS_CONSOLIDADO.md
└── .github/workflows/              # CI: lint+test Python, terraform validate, diff de esquemas
```

Reglas de propiedad:
- `infra/` la posee quien lleva Terraform; `etl/` quien lleva Python; **`sql/` es compartido** y los
  cambios en `sql/marts/**` o `sql/model/**` exigen revisión cruzada (CODEOWNERS).

---

## 7. Cómo encajan las piezas (orquestación)

- **Terraform provisiona, no ejecuta lógica de negocio**: crea los datasets/tablas/vistas, los
  **Cloud Run Jobs** (imagen de `etl/docker`), los **Cloud Scheduler** que los disparan, las SA e IAM,
  y las scheduled queries del consolidado.
- **El Python ejecuta la ETL**: cada job (`currencies`, `billing_accounts`, `get_data`,
  `mix_and_match`, `workspace_reseller`, `reverse-etl`) corre como Cloud Run Job, leyendo el
  `countries.yaml` y el `sql/` del propio repo.
- **Cadencia** (ejemplo mensual de facturación):
  1. `currencies` + `billing_accounts` (prep).
  2. `get_data` (consumo) por país.
  3. `mix_and_match` (marts) → `importes_lecturas*`.
  4. `reverse-etl` → `Carga_de_lectura__c` en Salesforce.
  5. Consolidado (scheduled queries) refresca `looker_views_global` (incluida la cadena de Brasil).

---

## 8. Pasos a seguir (plan por fases, sin romper producción)

**Fase 0 — Inventario y contrato (1-2 días)**
- Listar las tablas/vistas que la ETL escribe y que la infra publica → tabla de "contrato" (nombre,
  esquema, dueño).
- Detectar todo el SQL duplicado (p.ej. `importes_lecturas_by_project`) y decidir versión canónica.

**Fase 1 — `sql/` como fuente única**
- Mover los SQL a `sql/model|marts|consolidado`. Terraform y Python apuntan al mismo fichero.
- Reconciliar duplicados; los marts de Python pasan a ser la fuente que genera lo que la vista
  describía. Validar con diffs (como hicimos: flexibles fila entera, by_project 399/399).

**Fase 2 — `countries.yaml` único**
- Generar `tfvars/` desde `countries.yaml` (script) y que el Python lo lea también. Un solo sitio.

**Fase 3 — Cerrar el IaC pendiente**
- Terraformizar: `consolidado_src` por país (las 7 vistas) y los **2 transfers de Brasil**
  (materialización + cross-region copy) → import a estado, sin recrear.

**Fase 4 — Completar la ETL Python**
- `by_project` y `soporte` a columnas completas + diff fila entera (como flexibles).
- Job `mix_and_match` que orquesta extractor + 3 marts.
- Reverse-ETL `Carga_de_lectura__c` (Bulk API, con entorno de pruebas SF).

**Fase 5 — Orquestación**
- Dockerizar la ETL, Cloud Run Jobs + Cloud Scheduler provisionados por Terraform (`infra/orchestration/`).

**Fase 6 — CI/CD y limpieza**
- CI: `ruff`/`pytest` + `terraform validate/plan` + **check de esquemas** (mart vs vista del consolidado).
- Borrar el `etl/` viejo de este repo y el `dbt/` si se confirma que no se usa.

---

## 9. Riesgos y mitigaciones

| Riesgo | Mitigación |
|---|---|
| Romper la facturación en la migración | Todo en paralelo; no se sobrescriben tablas de producción; Terraform con `-target`. (Regla ya establecida.) |
| Reconciliar SQL duplicado introduce diferencias | Validar cada mart con diff fila-entera vs Talend/vista antes de cambiar la canónica. |
| Toolchains mezclados confunden el CI | Jobs de CI separados por carpeta; no se mezclan `uv` y `terraform` en el mismo paso. |
| Gobernanza/ownership | CODEOWNERS por carpeta; `sql/` con revisión cruzada obligatoria. |
| `terraform.tfstate` sensible en el repo | Ya hay backend GCS; no versionar state local (revisar `.gitignore`). |

---

## 10. Decisiones abiertas (necesitan acuerdo con Ángel/equipo)

1. **¿Monorepo (A) o contrato entre repos (B)?** — recomendado A.
2. **¿Quién es owner de `sql/`?** y política de revisión cruzada.
3. **¿dbt sí o no?** — hay una carpeta `dbt/` en el repo de Ángel pese a la decisión previa de
   "no dbt". Confirmar si se usa o se elimina.
4. **Orquestación**: Cloud Run Jobs + Scheduler (propuesto) vs Composer/Airflow vs Workflows.
5. **Nombre y ubicación** del repo unificado, y estrategia de migración del historial git
   (subtree/merge preservando histórico de ambos).

---

## Apéndice — Mapa rápido "qué vive dónde hoy"

| Pieza | Repo hoy | Destino propuesto |
|---|---|---|
| Datasets/tablas/vistas/IAM (Terraform) | terraform-billing | `infra/` |
| Consolidado `global/` | terraform-billing | `infra/global/` |
| `consolidado_src` + transfers Brasil | (creado por API, sin repo) | `infra/` (terraformizar) |
| Jobs ETL Python | swo-gcp-billing-python | `etl/` |
| SQL marts mix_and_match | swo-gcp-billing-python `config/queries/` | `sql/marts/` |
| SQL vistas/modelo | terraform-billing `modules/.../sql/` | `sql/model/` |
| Mapa de países | tfvars/ + config Python | `countries.yaml` (único) |
| `etl/` Python viejo | terraform-billing | borrar (superado) |
