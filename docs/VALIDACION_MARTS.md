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

## Resultado validación BRASIL 202605 (cross-region, vs Talend)

Brasil corre en `southamerica-east1` (export en US, marts en southamerica). Validado **prod-safe**:
round-trip de `sum_costs` (63+619 filas) southamerica → sandbox EU (read-only en Brasil), y el
resto del flujo (staging SF, get_data, currencies, marts) en el sandbox EU. Comparación cross-region
fila a fila (clave + importe redondeado) a local.

| Mart | nuevo | Talend | Veredicto |
|---|---|---|---|
| flexibles | 69 | 69 | **69/69 exactas, 0 diferencias** ✓ |
| by_project | 0 | 0 | ✓ (Brasil es todo `Desglosar='NO'`, sin desglosadas) |
| soporte | 0 | — | ✓ |

Particularidades de Brasil encontradas: (a) `sum_costs` antiguo SIN `reseller_margin_thirdparty_marketplace`
(Brasil es ThirdParty-Reseller=FALSE → se añade NULL); (b) destapó la root cause real del bug 7
(autodetect BOOL del string "NO"); (c) el job de currencies no honraba el token (bug 9).

## Resultado validación PAÍSES ANTIGUOS EU 202605 (vs Talend)

Todos en EU (sin cross-region). Flujo estándar `validate_country.sh` (staging SF → get_data →
marts → diff). Talend `importes_lecturas_by_project` = 0 en los 5 (verificado) → sin desglosadas.

| País | flexibles nuevo/Talend | by_project | soporte | Veredicto |
|---|---|---|---|---|
| Francia | 8/8 | 0/0 | 0 | **exacto** ✓ |
| Suiza | 5/5 | 0/0 | 0 | **exacto** ✓ |
| Holanda | 39/39 | 0/0 | 0 | **exacto** ✓ |
| UK | 10/8 (solo_n=2, solo_t=0) | 0/0 | 0 | reproduce los 8 + 2 opps NUEVAS (SF drift, verificado) |
| Alemania | 20/18 (solo_n=4, solo_t=2) | 0/0 | 0 | 16 comunes (= los de Ángel) + drift SF |

Los extras de UK/DE NO son bugs: son oportunidades cerradas-ganadas en SF **después** del run de
Talend (probado en UK: las 2 filas de más son 2 OpportunityIds nuevos distintos, ausentes en Talend,
importes 0.14/0.03 GBP). El sistema nuevo lee SF en vivo → está más al día que el Talend de 202605.
Consistente con lo que documentó Ángel (FR 8/8, NL 39/39, CH 5/5, UK 7/8*, DE 16/18).

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

7. **🔴 `staging` autodetect de esquema** (CRÍTICO, root cause corregida en validación de Brasil):
   `stg_opportunities` se carga con autodetect. El bug NO es solo que SF devuelva bool: el
   **autodetect de BigQuery interpreta el propio string `"NO"` como BOOLEAN** (lo trata como
   literal booleano). Probado aislado: `{"Desglosar_Facturas__c":"NO"}` → columna BOOLEAN. Por eso
   en países con TODO "NO" (Brasil) sale BOOL aunque el Python ya escriba el string 'NO'; en los
   mixtos (con algún "SI") autodetect ve STRING y cuela. Los marts comparan `= 'SI'/'NO'` → fallan.
   **Fix aplicado:** normalizar EN BQ tras el load (`CREATE OR REPLACE TABLE ... SELECT * REPLACE(
   IF(UPPER(CAST(Desglosar_Facturas__c AS STRING)) IN ('SI','TRUE'),'SI','NO') ...)`), que no
   depende del autodetect y cubre bool y string por igual. (La coerción en Python era inútil.)
8. **🟡 `CURRENCIES`** del `.env` común = `EUR,GBP,USD,CHF,BRL` → faltan las divisas de los países
   nuevos (HKD, VND, INR, MXN, SGD, COP...) → el job de currencies no las trae → sin conversión.
   **Fix:** lista GLOBAL (unión) calculada de countries.yaml; se corre 1 vez. Ver docs/GENERADORES_Y_CURRENCIES.md.
9. **🟢 `get_currencies_exchange_rates`** creaba el cliente BQ con `bigquery.Client(project=...)` SIN
   honrar `GOOGLE_OAUTH_ACCESS_TOKEN` (a diferencia del loader) → 403 fuera de Cloud Run. **Fix:**
   `_bq_client()` que usa el token si está (igual que `bigquery_loader`). Encontrado en Brasil.

> NOTA estado: bugs 1-6 ya estaban corregidos+pusheados; 7 (root cause real) y 9 corregidos en la
> validación de Brasil. Los "parches runtime" de la sección de arriba ya NO aplican (config.py,
> loader y el token están arreglados en el código; la ETL lee countries.yaml directamente).

## Validación país-por-país — flujo automatizado (`tools/validate_country.sh`)

Script que hace por país (read-prod / write-sandbox, **sin SF-write**): vista sum_costs → país,
staging, get_data, marts, diff vs Talend. La config de país sale de countries.yaml
(`ETL_MODE=sandbox` → ip-trabajo-apeinado); Desglosar ya sale 'SI'/'NO' del staging (fix aplicado).
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
