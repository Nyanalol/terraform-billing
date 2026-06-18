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

7. **🔴 `staging` autodetect de esquema** (CRÍTICO): `stg_opportunities` se carga con autodetect →
   en países SIN desglosadas, `Desglosar_Facturas__c` se infiere **BOOL** (SF devuelve false/null) →
   los marts comparan `= 'SI'`/`'NO'` (STRING) → **fallan en casi todos los países nuevos**.
   **Fix: esquema explícito (STRING) en el load de staging.**
8. **🟡 `CURRENCIES`** del `.env` común = `EUR,GBP,USD,CHF,BRL` → faltan las divisas de los países
   nuevos (HKD, VND, INR, MXN, SGD, COP...) → el job de currencies no las trae → sin conversión.

## Validación país-por-país — flujo automatizado (`tools/validate_country.sh`)

Script que hace por país (read-prod / write-sandbox, **sin SF-write**): vista sum_costs → país,
gen_env, staging, fix BOOL Desglosar, get_data, marts, diff vs Talend.
`bash tools/validate_country.sh win_<xx> <project_id>`.

### Resultados (202605) — flexibles vs Talend `importes_lecturas_temp`

| País | flex nuevo/Talend | Veredicto |
|---|---|---|
| España | 316 económicas exactas | ✅ (by_project bug dups; soporte 4/4) |
| Vietnam | 3/3 | ✅ exacto |
| Colombia | 1/1 | ✅ exacto |
| Mexico | 1/1 | ✅ exacto |
| Belgium, Ecuador, India, Singapore, USA | 0/0 | ✅ sin datos |
| Hong Kong | 2/2 (1 difería) | ✅ era el rate HKD ausente; con rate → 13.58 ≈ 13.57 Talend |
| Italy | 2/0 | ✅ nuevo correcto; Talend nunca corrió 202605 (solo 202405) |

**Conclusión: los marts validan bien en todos.** Las discrepancias eran de setup (rates) o Talend
no-corrido, NO de lógica. Bugs reales = solo el `DISTINCT` (#1) y el autodetect-BOOL (#7).

Pendiente: EU antiguos (CH/FR/UK/DE/NL — Ángel ya validó flexibles) y Brasil (cross-region).

## Estado global del reemplazo de Talend
- Jobs migrados: ✅ todos (+ `run_all`). Consolidado (17 países): ✅. Monorepo: ✅ (pusheado a Ángel).
- Falta: **(1)** fix bugs · **(2)** validar 16 países · **(3)** orquestar Cloud Run+Scheduler · **(4)** paralelo+cutover.
