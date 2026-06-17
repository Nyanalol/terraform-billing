# Validación de los marts mix_and_match — estado (2026-06-17)

Tarea de Ángel: testear `materialize_importes_by_project` y `_soporte` + análisis de bugs/mejoras.
Y arrancar la validación país por país (paso 2 del reemplazo de Talend).

## Pipeline DESBLOQUEADO (corre end-to-end en local → sandbox)

- Entorno: `etl/.venv` (deps instaladas SIN `pyjks`; ver bug 3). `.env` con clave SF real (gitignored).
- **Clave del desbloqueo**: para que el cliente BQ de Python use g.softwareone hay que generar el
  token con el entorno gcloud COMPLETO (`CLOUDSDK_PYTHON` + CA), si no sale vacío y Python cae a ADC → 403.
- Probado: `staging` (SF read → sandbox) y `get_data` (sum_costs → bq_group_*) de **España** OK.
- TODO read-only sobre SF + escritura solo al sandbox `ip-trabajo-apeinado`. **NUNCA** ejecutar los
  jobs `mix_and_match_*`/`write_data`/`delete_today_lecturas` (escriben/borran en Salesforce).

### Cómo correr (mañana) — variables + parches runtime
```bash
cd etl
export CLOUDSDK_PYTHON="...google-cloud-sdk/platform/bundledpython/python.exe"
export CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE="$HOME/gcloud-corp-ca.pem"
export CLOUDSDK_CORE_ACCOUNT="miguel.gonzalez-albo@g.softwareone.com"
export REQUESTS_CA_BUNDLE="$HOME/gcloud-corp-ca.pem"; export SSL_CERT_FILE="$HOME/gcloud-corp-ca.pem"
export GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token)   # 261 chars si va bien
```
Parches runtime (NO commitear; son bugs de Ángel, ver abajo) — re-aplicar antes de correr:
- `src/config.py`: `class Config:` → añadir `extra = "ignore"`.
- `src/etl/load/bigquery_loader.py`: cliente BQ con `Credentials(token=GOOGLE_OAUTH_ACCESS_TOKEN)`.

## Resultado validación ESPAÑA 202605 (end-to-end, vs Talend)

| Mart | nuevo | Talend | solo_nuevo | solo_talend | Veredicto |
|---|---|---|---|---|---|
| flexibles | 321 | 316 | 7 | 2 | cerca; revisar 7 extra (¿dups?) + 2 que faltan |
| by_project | 407 | 399 | 4 | 0 | **399/399 exactos** + 8 filas DUPLICADAS (bug) |
| soporte | 7 | 4 | — | 0 | **4/4 exactos** + 3 drift SF (documentado), limpio |

## Bugs / mejoras para Ángel

1. **🔴 `by_project` DUPLICA filas** (doble facturación). El CTE `oli` **no tiene `DISTINCT`**
   (soporte sí). OLIs repetidos en `stg_line_items` (opp `0062p000018CRm9AAG`: SKU 1419×2, 1420×2)
   → cada línea ×2 → `Carga_de_lectura__c` duplicadas en SF. **Fix: `SELECT DISTINCT` en el oli.**
2. **🟡 `by_project` `Margen_SWO`** emite la fracción `swo` (no el importe `mg_*_swo`). En España
   no se ve (swo=0), pero mal para opps con swo≠0. Inconsistente con flexibles.
3. **🟡 `config.py`** rechaza el `.env.example` (campos `GCP_PROJECT_ID`/`LOG_LEVEL`/`ENVIRONMENT`
   no están en `Settings` y prohíbe extras) → ningún job arranca. **Fix: `extra="ignore"`.**
4. **🟢 `pyjks`(→`twofish`)** requiere compilador C++ y NO se usa (PEM del `.env`). Quitar de deps.
5. **🟢 `bigquery_loader`** usa ADC fija; no honra token → cuesta correr fuera de Cloud Run.
6. **🟢 flexibles** `321 vs 316`: revisar (posibles dups por el mismo motivo + el filtro `Desglosar='NO'`).

## Validación país-por-país (flujo SAFE, pendiente para mañana)

Por cada país (todo read-prod / write-sandbox, sin SF-write):
1. Copiar `<pais>.billing_views.sum_costs_credits_per_month` → `ip-trabajo-apeinado.billing_views.sum_costs_credits_per_month`.
2. `gen_env.py --mode sandbox --country win_<xx> --write` → `.env.win_<xx>`.
3. `python -m src.etl.jobs.mix_and_match_staging --country win_<xx> --month 05 --year 2026` (SF read → sandbox stg_*).
4. `python -m src.etl.jobs.get_data --country win_<xx> --month 05 --year 2026` (→ sandbox bq_group_*).
5. Marts en SQL (sed de los 3 `.sql` → bq query → sandbox flex_new/project_new/soporte_new).
6. Diff vs `<pais>` Talend (`importes_lecturas_temp` / `_by_project` 202605).

Hecho: **España**. Pendiente: los otros 16 (sandbox single-tenant → uno a uno, reciclando sum_costs).

## Estado global del reemplazo de Talend
- Jobs migrados: ✅ todos (+ `run_all`). Consolidado (17 países): ✅. Monorepo: ✅ (pusheado a Ángel).
- Falta: **(1)** fix bugs · **(2)** validar 16 países · **(3)** orquestar Cloud Run+Scheduler · **(4)** paralelo+cutover.
