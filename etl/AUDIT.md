# Auditoría de los jobs de Talend (Fase 0 — migración a Python + BigQuery)

> Ingeniería inversa de `C:\facturacion\swo-product_facturacion-es\FACTURAS\process\*.item`.
> Objetivo: jubilar Talend. **Extracción** (Salesforce + API divisas) → Python; **Transformación**
> (joins/filtros/agregados/cálculos) → **BigQuery SQL** gestionado con Terraform; **carga a
> Salesforce** → Python. Sin código todavía: esto es el mapa para decidir el alcance.

## El pipeline hoy (cómo encaja todo)

```
currencies_exchange_rates ──► currency_exchange.csv ─────────────┐
get_data ──► bq_group_billing.csv, bq_group_project.csv ─────────┤
get_data_workspace ──► bq_workspace_reseller.csv ────────────┐   │
diary_get_billing_accounts ──► bq_billing_accounts(_full).csv─┼─► (CSVs en disco, C:\billing\<pais>\)
                                                              │   │
diary_write_billing_accounts ◄── carga billing_accounts(_full) a BQ
                                                              │   │
mix_and_match  ◄── lee bq_group_*.csv + currency_exchange.csv + Salesforce
   └─► bq_lecturas_anuales.csv, bq_lecturas_flexibles.csv, bq_out_soporte.csv,
       bq_out__desglosadas.csv  + INSERT a Salesforce (Carga_de_lectura__c)
workspace_reseller ◄── lee bq_workspace_reseller.csv + Salesforce
   └─► workspace_pass.csv, workspace_rejected.csv + INSERT a Salesforce (Lectura__c, Carga_de_lectura__c)
write_data ◄── lee TODOS los CSV anteriores y los carga a BQ
   └─► importes_lecturas_anuales/flex/by_project/workspace (las tablas que leen las vistas Looker)
```

Resumen: **5 jobs son E o L triviales** (CSV↔BQ, API), **2 jobs concentran la lógica de negocio**
(`mix_and_match` y, en menor medida, `workspace_reseller`), y **`write_data`/`diary_write`
desaparecen** en el rediseño.

---

## Hallazgos transversales (lo importante)

### 🔴 1. Secretos en claro versionados en el repo de Talend
- `mix_and_match` / `diary_get`: **credenciales Salesforce en claro** (`soporte@intelligencepartner.com`
  + password + security token) en `tSalesforceConnection`. El job además ya declara contexto JWT
  (`sf_issuer_key`, `sf_key_store_*`) que **no se usa** para la conexión real.
- `write_data` / `diary_write`: **HMAC GCS** (`GS_SECRET_KEY`) y **OAuth** (`CLIENT_SECRET`,
  `AUTHORIZATION_CODE`) embebidos/cifrados-reversibles en el `.item`.
- **Acción**: tratar como filtración → **rotar** SF token + HMAC + OAuth, y migrar a **JWT** (ya hay
  config preparada) + Secret Manager. Es lo primero, independientemente de la migración.

### 🔴 2. Nada es idempotente (riesgo de duplicar facturación)
- `write_data`: `ACTION_ON_DATA=APPEND` en las 5 tablas → **reprocesar un mes duplica filas**.
- Salidas a Salesforce: `INSERT` (no UPSERT) en `Carga_de_lectura__c` / `Lectura__c` → **duplica
  registros** al re-correr.
- `currencies`: `APPEND` + `tFileDelete` previo (frágil; si el delete falla, duplica).
- `diary_write`: `TRUNCATE` (esto sí es ~atómico).
- **Acción**: diseño nuevo idempotente → `CREATE OR REPLACE TABLE` / `MERGE` particionado por
  `year/month`; UPSERT a Salesforce con external id (o borrado previo por país+mes).

### 🟠 3. Redundancia masiva con BQ (gran parte del ETL sobra)
- `get_data` / `get_data_workspace` son `SELECT ... WHERE invoice_month` sobre
  `sum_costs_credits_per_month[_by_project]` y `reseller_view`, con columnas derivadas triviales
  (`total_* = IFNULL(GREATEST(coste+credito,0),0)`). Esas derivadas deben vivir en la **vista**
  (Terraform), no recalcularse en cada extracción. Los CSV intermedios son ida y vuelta a disco.
- La agregación de consumo que `mix_and_match` lee por CSV es exactamente
  `sum_costs_credits_per_month`. No se reimplementa.

### 🟠 4. `reseller_view` no está inventariada
- `get_data_workspace` y `workspace_reseller` dependen de `<proyecto>.<bq_workspace_dataset>.reseller_view`,
  que **no está en Terraform** y contiene `sku_sf` (mapeo SKU→Salesforce). Probablemente se apoya en
  la Google Sheet `ext_workspace_sku_sf` que ya tenemos declarada. **Hay que localizar y versionar esa
  vista** antes de migrar Workspace.

---

## Jobs uno a uno

### `currencies_exchange_rates` — VIVO, crítico → **Python (API) + tabla BQ**
- **Qué hace**: producto cartesiano de las divisas del país; por cada pareja distinta llama a la API
  REST **Hexarate** (`https://hexarate.paikama.co/api/rates/{base}/{target}/{primer-día-mes-siguiente}`,
  GET XML, sin auth, 5 hilos), parsea `mid` como rate; las parejas iguales → rate `1.0`. Vuelca a
  `currency_exchange.csv`.
- **Crítico**: es la **única** fuente de tipos de cambio (no hay tabla BQ de rates; `currency_symbols`
  es otra cosa). `DIE_ON_ERROR=false` → una divisa que falle deja huecos silenciosos.
- **Rediseño**: `fetch_exchange_rates.py` (requests + retries) → tabla `billing_views.currency_exchange_rates`
  (`base, target, rate, rate_date, fetched_at`), `WRITE_TRUNCATE` por `rate_date`. Pedir solo contra una
  base y derivar inversos/iguales en SQL (4 llamadas en vez de 20). Evaluar proveedor con SLA (ECB).

### `diary_get_billing_accounts` — VIVO → **Python (SOQL) + BQ SQL**
- **Qué hace**: extrae de Salesforce el maestro de billing accounts (Opportunity facturables +
  `Billing_Account__c`), deduplica por `billing_account_id__c` y deja `bq_billing_accounts.csv` y
  `bq_billing_accounts_full.csv`.
- **Lógica → SQL**: `UNION ALL` (facturables ∪ resto) + `GROUP BY billing_account_id, desc` con
  `MAX(...)`. `COALESCE(Fecha_Fin, DATE '9999-12-31')`.
- **Crítico/ineficiencias**: pide **~155 columnas** de Opportunity y usa **6**; SF1 y SF3 son dos
  queries casi iguales (fusionar); `MAX()` sobre strings (`Billing_Model__c`, `StageName`) para
  "elegir uno" es arbitrario → confirmar la regla real. `Empresa_IP__c` por país ya lo tenemos en tfvars.

### `diary_write_billing_accounts` — **SE ELIMINA**
- Cargador puro CSV→GCS→BQ con `TRUNCATE` de `billing_accounts` / `billing_accounts_full`.
- En el rediseño esas tablas se materializan con `CREATE OR REPLACE TABLE` desde el SQL anterior.
- ⚠️ Su `bq_output_dataset` en spain = `BILLING_CLOUD_PLATFORM`, **no `billing_views`** → revisar el
  mapeo de dataset de salida por país.

### `get_data` — trivial, **redundante** → derivadas a la vista, CSV fuera
- Dos `tBigQueryInput` (`sum_costs_credits_per_month` y `..._by_project`, `WHERE invoice_month`) → 2 CSV.
- Sin Salesforce, sin tMap. Las `total_*` van a la vista (Terraform).
- ⚠️ **Posible bug heredado**: `total_customer_cost_thirdparty_marketplace = customer_cost_thirdparty_marketplace
  + credits_thirdparty_marketplace` (mezcla magnitud "customer" con créditos "no-customer"). Y `GREATEST`
  (suelo 0) se aplica a GCP/GMP pero **no** a `thirdparty`/marketplace. Confirmar si es intencional.

### `get_data_workspace` — trivial, condicional → CSV fuera
- Un `SELECT` de `reseller_view` `WHERE invoice_month` → `bq_workspace_reseller.csv`. `tWarn` si el país
  no tiene `reseller_view` (job opcional por país). Toda la lógica está en `reseller_view` (ver hallazgo 4).

### `workspace_reseller` — lógica media → **Python (SOQL+carga) + BQ SQL**
- **Qué hace**: une consumo Workspace (CSV) × OpportunityLineItem vigente × Opportunity válida
  (`StageName='Cerrada ganada'`, `Estado='Activado'`, `RecordType='Op Flexible'`,
  `Linea_negocio IN ('Google Cloud Services','Google Apps')`) por `sku_sf + domain_name`. Clasifica
  `pass` / `reject` / `NA` (los `NA` vienen de la lista negra `GwsExcludedBilling__c`). Inserta los `pass`
  en Salesforce (`Lectura__c` **y** `Carga_de_lectura__c`).
- **Regla clave**: Workspace reseller se factura **a coste** (`Importe = google_charge`, sin margen,
  GMP/GCP=0, **sin conversión de divisa**).
- **→ SQL**: el join + concatenaciones (`CONCAT('Usage of ', usage_amount, ' seats, Order:', ...)`,
  `SUBSTR(invoice_month,...)`, `REPLACE(sku,'.0','')`) + clasificación pass/reject/NA con `CASE`.
- **Dudas**: ¿`Lectura__c` y `Carga_de_lectura__c` son ambos vivos o uno es legado? `UNIQUE_MATCH` del
  lookup → en SQL un JOIN puede hacer fan-out: definir clave de desempate. INSERT → debe ser UPSERT.

### `write_data` — **SE ELIMINA**
- Loader CSV→BQ de las 5 salidas (`importes_lecturas_anuales` [param], `_flex` [param],
  `_by_project` [literal, **no autocrea**, debe existir en Terraform], `importes_lecturas_workspace`
  [literal]). Única "lógica": forzar `Total_thirdparty=null` (flex-desglosadas) y `UNION ALL`
  pass+rejected de workspace.
- **APPEND** siempre → duplicados. Encoding `ISO-8859-15` en salida vs UTF-8 en entrada (riesgo acentos).
- ⚠️ **Contrato de columnas**: las vistas Looker dependen de los nombres EXACTOS, **incluidos typos**
  (`Magen_gcp`, `invoce_date`). No renombrar sin verificar dependencias.

### `mix_and_match` — **EL HUESO** → Python (SOQL+carga) + BQ SQL
- **Qué hace**: cruza consumo Google (CSV agregado por billing_account y por project) × Salesforce
  (Opportunity + OpportunityLineItem: márgenes de partner, descuentos, modelo de facturación, soporte),
  calcula **importe a facturar y márgenes** (GCP, GMP/Maps, soporte, third-party/marketplace, Margen SWO),
  con conversión a la divisa de la cuenta y a euros. Produce 4 CSV (anuales/flexibles/soporte/desglosadas)
  e **inserta** `Carga_de_lectura__c` en Salesforce. Dos caminos paralelos: por billing_account y por project.
- **Fórmulas de negocio a replicar al céntimo** (extracto):
  - Márgenes de partner: campo `/100` (GCP, GMP, Soporte, Soporte_Maps). `Margen_SWO = campo/100`.
  - `Redondeo = 1e6` → `ROUND(x, 6)`.
  - `Rate = getRate(currency_origen, CurrencyIsoCode)`, `Rate_to_Euro = getRate(currency,'eur')`.
  - Marketplace (`GoogleInvoiceTypeOpp__c == 'MARKETPLACE'`): usa `*_thirdparty_marketplace`, pone gmp/thirdparty a 0.
  - `ApplySupport = Fecha_Inicio_Contrato_Opp__c <= día 23 del mes`. `TotalSupport = ApplySupport ? GREATEST(SopPorConsumo, minimo) : 0`.
  - `Importe_factura = ROUND( TotalSupport*(1-Desc_sop) + TotalSupport_Maps*(1-Desc_sop_maps) + Total_gmp*(1-Desc_gmp) + Total_gcp*(1-Desc_gcp) + Total_thirdparty - Margen_gmp_swo - Margen_gcp_swo )`.
  - `Cargo_google = ROUND(Total_gmp_eur + Total_gcp_eur + Total_thirdparty_eur + reseller_margin_gmp + reseller_margin_gcp)`.
  - SKU split: GCP `SKU IN (1419,1421)`, GMP `SKU IN (1420,1422)`. Filtro raro `tFilterRow_5`: de GCP solo deja pasar el `1421`.
  - Clamp de negativos diminutos: `valor en (-0.001,0) → 0`.
- **Dudas críticas** (bloquean la paridad — ver abajo).

---

## Preguntas abiertas (a confirmar antes de tocar `mix_and_match`/`workspace_reseller`)

1. **`mix_and_match` — qué SOQL alimenta el cálculo**: hay un `tSalesforceInput_1` (OpportunityLineItem,
   ~70 campos) que parece morir en un `tLogRow`. ¿`row28` (el main del cálculo) sale de ahí o de otra réplica?
2. **`Carga_de_lectura__c`**: hoy es `INSERT` con Upsert Key declarada pero no usada. ¿Debe ser **UPSERT**
   (idempotente) o INSERT puro? (define cómo evitamos duplicados al reprocesar un mes).
3. **Acumulado anual** (`Control_lectura_anuales_Consumo__c` → Opportunity): hoy está **desconectado**
   (sin destino). ¿Debe seguir escribiéndose en Salesforce o es lógica muerta?
4. **Doble cálculo de soporte** (tMap_2 vs tMap_10 sobre el agregado, con redondeos distintos): ¿cuál es
   la cifra que va a producción?
5. **`getRate`/`CurrencyUtils`**: necesito el código de la rutina (`FACTURAS/code/routines/CurrencyUtils...`)
   para replicar exactamente dirección de conversión, precisión y qué hace si no encuentra la pareja.
6. **`Lectura__c` vs `Carga_de_lectura__c`** (Workspace): ¿ambos vivos o uno legado?
7. **`reseller_view`**: ¿dónde está definida y se apoya en la Google Sheet `ext_workspace_sku_sf`?
8. **Dataset de salida por país**: spain escribe a `BILLING_CLOUD_PLATFORM`, no a `billing_views`. ¿Mapeo correcto?
9. **Bug de `total_customer_cost_thirdparty_marketplace`** y la asimetría de `GREATEST`: ¿intencional o se corrige?

---

## Arquitectura objetivo propuesta

```
┌─ Python (E) ─────────────────────────────────────────────┐
│  sf_extract.py (JWT, simple-salesforce):                 │
│    Opportunity, OpportunityLineItem, Billing_Account__c, │
│    GwsExcludedBilling__c  ──►  billing_views.stg_* (BQ)  │
│  fetch_exchange_rates.py (Hexarate) ──► currency_exchange_rates (BQ) │
└──────────────────────────────────────────────────────────┘
                          │
┌─ BigQuery SQL (T) — Terraform (scheduled queries / vistas) ┐
│  billing_accounts / billing_accounts_full   (← diary)      │
│  total_* en sum_costs_credits_per_month[_by_project]       │
│  motor de márgenes/importe  ──► importes_lecturas_anuales, │
│     _flexibles, _by_project, _soporte        (← mix_and_match) │
│  workspace pass/reject/NA  ──► importes_lecturas_workspace (← workspace_reseller) │
└────────────────────────────────────────────────────────────┘
                          │
┌─ Python (L) ───────────────────────────────────────────────┐
│  sf_load.py: lee las tablas calculadas y hace UPSERT        │
│    a Carga_de_lectura__c / Lectura__c (idempotente)         │
└─────────────────────────────────────────────────────────────┘

Orquestación: Cloud Run + Cloud Scheduler (gestionado en Terraform).
Desaparecen: TODOS los CSV intermedios, get_data, get_data_workspace, write_data, diary_write.
```

## Orden de migración propuesto (riesgo ascendente, valor primero)

1. **`currencies_exchange_rates`** → Python + tabla BQ. Aislado, sin Salesforce, valida el patrón E→BQ.
2. **`diary` (billing_accounts)** → SF extract (Python) + BQ SQL. Fundacional (todo hace join contra billing_accounts).
3. **`get_data` / `get_data_workspace`** → mover `total_*` a las vistas, eliminar CSVs (en parte ya hecho en Terraform).
4. **`workspace_reseller`** → SF extract + clasificación BQ + UPSERT a SF.
5. **`mix_and_match`** → el grande, al final, con **ejecución en paralelo y diff de tablas** hasta cuadrar al céntimo.
6. **`write_data`** → se evapora a medida que los anteriores escriben directo a BQ.

Cada paso: correr Python+SQL **en paralelo** con Talend un ciclo, **diffear las tablas BQ** resultantes,
y solo entonces jubilar ese job.
