# Spec aplanado — `mix_and_match` (Talend → SQL)

> Ingeniería inversa del job `mix_and_match_1.0` de Talend para reimplementarlo como **SQL plano**
> sobre BigQuery (consumo ya en BQ + Salesforce en staging + tabla de tipos de cambio).
> Todas las fórmulas están **resueltas a inputs crudos** (aplanadas), para paridad al céntimo.
> Fuente: `mix_and_match_1.0.item`, `CurrencyUtils_0.1.item`, y el doc HTML del job.
>
> **Objetivo del rediseño**: una sola lógica de cálculo compartida + dos marts que solo cambian el
> `GROUP BY` (by_account / by_project). Aplanar las "fórmulas que tiran de fórmulas" y tirar lo muerto.

`getRate(base,target)`: lookup en diccionario con clave `lower(base)+"_"+lower(target)`. Devuelve **1.0**
si `base==target`, si alguna es null, o si la clave no existe (nunca lanza error, solo warning).

---

## 1. DAG resuelto

El cálculo vive en un subjob; antes hay un prejob que carga el config y el diccionario de divisas.

```
SF OpportunityLineItem (67 cols) ──row28──┐
SF Opportunity (171 cols, filtro:        ├─► tMap_9 (JOIN OLI×Opp por Opp.Id)
  Margen_GCP!=null && Margen_GMP!=null)──┘        ├─► OpProduct_por_proyecto ─► tMap_5  (RAMA BY_PROJECT)
                                                  └─► OpProduct_por_billing_account ─► tMap_2 (RAMA BY_ACCOUNT)

consumo by_account (bq_group_billing, CON marketplace) ─row26─┐
SF OLI (4 cols: OppId, Billing_Account_ID, GoogleInvoiceType,├─► tMap_12 (marketplace) ─► tMap_2 (lookup)
  Dominio) ──────────────────────────────────────row15──────┘
consumo by_project (bq_group_project, SIN marketplace) ─row8─► tMap_5 (lookup propio)
```

**RAMA BY_ACCOUNT** (`tMap_2` → split SKU `tMap_1` → `Desglosar=="NO"`):
- `billing_model=="Flexible"` → `tMap_3` → **`Carga_de_lectura__c` INSERT** → *salida flexibles*
- no-flexible → `tAggregateRow_1` (group bill+dom+month) → `tMap_6` → CSV **anuales** + **UPDATE Opportunity** (`Control_lectura_anuales_Consumo__c`)
- flexible desglosado → `tFilterColumns_1` → `Importe>0` → CSV **desglosadas**

**RAMA BY_PROJECT** (`tMap_5` → split SKU `tMap_13` → `Desglosar=="SI"`):
- `tAggregateRow_2` → **`tMap_10` (RECÁLCULO de soporte)** → filtro SKU → CSV **soporte** (+ `Carga_de_lectura__c` INSERT)
- `Importe_factura>0` → `tMap_8` → **`Carga_de_lectura__c` INSERT** (proyecto) y `tMap_7` → CSV proyecto (no oficial)

**Resuelto:** `row28` (el main del cálculo) sale de **`tSalesforceInput_1` (OpportunityLineItem, 67 cols)** — **SÍ se usa**, no muere en el `tLogRow` (es solo logging transparente). Passthrough/muertos: `tReplicate_6` (1 salida), `tFilterRow_10` (vacío), los `tLogRow`, `tFilterColumns_1` (solo recorte).

---

## 2. Inputs y grano

| Input | Fuente | Grano | Columnas usadas de verdad |
|---|---|---|---|
| OLI (row28) | SOQL `OpportunityLineItem` | 1×línea | `OpportunityId, Descripci_n_del_producto__c, SKU__c, CurrencyIsoCode, Fecha_Inicio/Fin_Contrato__c, Fecha_Inicio/Fin_Contrato_Opp__c` (de 67, el resto se descarta) |
| Opportunity | SOQL `Opportunity` (filtro `Margen_GCP!=null && Margen_GMP!=null`) | 1×Opp | `Id, billing_account_id__c, billing_account_desc__c, Margen_de_partner_Margen_{GCP,GMP,Soporte,Soporte_Maps}__c, Margen_de_partner_Descuento_{...}__c, Desglosar_Facturas__c, Billing_Model__c, Sop_Tec_Porcent__c, Sop_Tec_Maps_Porcent__c, Sop_Tec_imp_minimo__c, Sop_Tec_Maps_imp_minimo__c, Sop_Tec_imp_fijo__c, Sop_Tec_Maps_Importe_Fijo__c, Control_lectura_anuales_Consumo__c, Margen_SWO__c` |
| OLI marketplace (row15) | SOQL `OpportunityLineItem` (4 cols) | 1×OLI | `OpportunityId, Opportunity.Billing_Account_ID__c, Opportunity.GoogleInvoiceTypeOpp__c, Dominio__c` |
| consumo **by_account** | `sum_costs_credits_per_month` | 1×(month,billing_account) | incluye **marketplace**: `cost/credits/total_thirdparty_marketplace, customer_cost_thirdparty_marketplace, total_customer_cost_thirdparty_marketplace, reseller_margin_thirdparty_marketplace` |
| consumo **by_project** | `sum_costs_credits_per_month_by_project` | 1×(month,billing_account,project) | **SIN marketplace**, **CON `project_id`** |
| rates | tabla currency rates | 1×(base,target) | `base_currency, target_currency, exchange_rate` |

---

## 3. El motor (lógica COMPARTIDA, aplanada)

`tMap_2` (account) ≡ `tMap_5` (project) salvo §4. `c.*` = fila consumo, `o.*` = fila Opportunity. **Redondeo `1e6` ⇒ `ROUND(x,6)`** en todo el motor.

### 3.1 Marketplace (solo by_account, en tMap_12)
`isMarketplace = o.GoogleInvoiceTypeOpp__c == "MARKETPLACE"`. Si lo es, reescribe la fila de consumo:
`gcp ← *_thirdparty_marketplace`, `reseller_margin_gcp ← reseller_margin_thirdparty_marketplace`,
`gmp = thirdparty = 0`, conserva `(total_)customer_cost_thirdparty_marketplace`.

### 3.2 Conversión de divisa
```
Rate                 = (c.currency==null || o.CurrencyIsoCode==null) ? 1.0 : getRate(c.currency, o.CurrencyIsoCode)
Rate_to_Euro         = (c.currency==null) ? 1.0 : getRate(c.currency, 'eur')
Rate_to_Euro_Soporte = (o.CurrencyIsoCode==null) ? 1.0 : getRate(o.CurrencyIsoCode, 'eur')
```

### 3.3 Normalización de márgenes (en tMap_9)
`Margen_partner_X = o.Margen_de_partner_Margen_X__c / 100`; `Margen_SWO = o.Margen_SWO__c/100 (null→0)`;
`Sop_Tec_Porcent = o.Sop_Tec_Porcent__c/100`. **Descuentos: doble `/100` efectivo** (una en tMap_9, otra en el motor `Descuento_X = descuento_X/100`). → **VER duda §7.4** (¿intencional o bug?).

### 3.4 Totales
```
Total_gcp_euros        = ROUND(total_gcp_raw, 6)          -- by_account: si isMarketplace usa total_customer_cost_thirdparty_marketplace
Total_gmp_euros        = ROUND(total_gmp_raw, 6)
Total_thirdparty_euros = ROUND(total_thirdparty_raw, 6)
Total_gcp_currency_ok        = ROUND(total_gcp_usado * Rate, 6)
Total_gmp_currency_ok        = ROUND(total_gmp_raw   * Rate, 6)
Total_thirdparty_currency_ok = ROUND(total_thirdparty_raw * Rate, 6)
reseller_margin_gcp/gmp      = (raw==null ? 0 : raw)
```

### 3.5 Cadena de márgenes — APLANADA (cada uno en términos de inputs, sin anidar)
```
Margen_gcp_euros = ROUND( ( (-reseller_margin_gcp) - (Total_gcp_euros * Descuento_gcp) ) * (1 - Margen_SWO), 6)
Margen_gmp_euros = ROUND( ( (-reseller_margin_gmp) - (Total_gmp_euros * Descuento_gmp) ) * (1 - Margen_SWO), 6)
Margen_gcp_swo   = ROUND( ( (-reseller_margin_gcp) - (Total_gcp_euros * Descuento_gcp) ) *      Margen_SWO , 6)
Margen_gmp_swo   = ROUND( ( (-reseller_margin_gmp) - (Total_gmp_euros * Descuento_gmp) ) *      Margen_SWO , 6)
Margen_gcp       = ROUND( Margen_gcp_euros * Rate, 6)
Margen_gmp       = ROUND( Margen_gmp_euros * Rate, 6)
```
(Las versiones viejas `Total×Margen_partner` están **comentadas** → se tiran.)

### 3.6 Soporte (motor; efectivo solo en by_account)
```
ApplySupport            = Fecha_Inicio_Contrato_Opp__c <= date(year-month-23)
SoporteTecnicoPorConsumo      = Total_gcp_currency_ok * Sop_Tec_Porcent        -- SIN fijo
SoporteTecnicoPorConsumo_Maps = Total_gmp_currency_ok * Sop_Tec_Maps_Porcent
TotalSupport      = ApplySupport ? max(SoporteTecnicoPorConsumo,      Sop_Tec_imp_minimo)      : 0
TotalSupport_Maps = ApplySupport ? max(SoporteTecnicoPorConsumo_Maps, Sop_Tec_Maps_imp_minimo) : 0
```
> En `tMap_5` (project) `TotalSupport = 0` — el soporte de project se recalcula en `tMap_10` (§6.3).

### 3.7 Importe a facturar
```
Importe_factura = ROUND(
    TotalSupport      * (1 - Descuento_soporte)
  + TotalSupport_Maps * (1 - Descuento_soporte_maps)
  + Total_gmp_currency_ok * (1 - Descuento_gmp)
  + Total_gcp_currency_ok * (1 - Descuento_gcp)
  + Total_thirdparty_currency_ok
  - Margen_gmp_swo - Margen_gcp_swo , 6)

Importe_factura_gcp = ROUND( TotalSupport*(1-Descuento_soporte) + Total_gcp_currency_ok*(1-Descuento_gcp) + Total_thirdparty_currency_ok - Margen_gcp_swo , 6)
Importe_factura_gmp = ROUND( TotalSupport_Maps*(1-Descuento_soporte_maps) + Total_gmp_currency_ok*(1-Descuento_gmp) - Margen_gmp_swo , 6)
```

### 3.8 Cargo Google (con clamp de negativos diminutos)
```
Cargo_google     = ROUND( Total_gmp_euros + Total_gcp_euros + Total_thirdparty_euros + reseller_margin_gmp + reseller_margin_gcp , 6)
Cargo_Google_GCP = (v in (-0.001, 0)) ? 0 : v,  con v = ROUND(Total_gcp_euros + reseller_margin_gcp + Total_thirdparty_currency_ok, 6)
Cargo_Google_GMP = (v in (-0.001, 0)) ? 0 : v,  con v = ROUND(Total_gmp_euros + reseller_margin_gmp, 6)
```

### 3.9 Margen %
```
Margen       = TotalSupport*(1-Descuento_soporte)/Rate + Margen_gcp_euros + Margen_gmp_euros
Margen_total = ROUND( Importe_factura>0 ? (Margen*100 / (Importe_factura/Rate)) : 0 , 6)   -- es un %
```
Salidas en euros: `Margen_gcp_euros_out = Margen_gcp_euros * Rate_to_Euro`, idem gmp; `Margen_soporte_euros = (TotalSupport*porcentajeMargenSoporte) * Rate_to_Euro_Soporte`.

### 3.10 Split por SKU (tMap_1 account / tMap_13 project)
`SKU_is_GCP = SKU∈{1419,1421}`, `SKU_is_GMP = SKU∈{1420,1422}`. Si `SKU_is_GMP` pone a 0 todos los campos GCP (y `reseller_margin_gcp=0`); si `SKU_is_GCP` pone a 0 los GMP. Consolida:
`Cargo_google = SKU_is_GCP ? Cargo_Google_GCP : SKU_is_GMP ? Cargo_Google_GMP : Cargo_google`;
`Importe_factura = SKU_is_GCP ? Importe_factura_gcp : SKU_is_GMP ? Importe_factura_gmp : Importe_factura`.

### 3.11 Redondeos a preservar
Motor (tMap_2/5): **ROUND 6**. `tMap_10` (soporte project): **ROUND 2** (`*100/100.0`). Cuidado con la mezcla.

---

## 4. Diferencias entre marts

| | by_account (tMap_2) | by_project (tMap_5) |
|---|---|---|
| Consumo | con marketplace resuelto | sin marketplace |
| Grano | (billing_account, OppId, SKU) | + **project_id** |
| `project_id` | `""` | `null/vacío → "No project name"`; en tMap_7 `vacío → "Google Adjustments"` |
| Soporte | inline (sin fijo) | `0` en motor; recalculado en tMap_10 (con fijo, ROUND 2) |
| Acumulado anual | presente (→ UPDATE Opportunity) | ausente |
| Filtro rama | `Desglosar=="NO"` | `Desglosar=="SI"` |

---

## 5. Las 4 salidas (contrato exacto)

Todas escriben CSV con `APPEND=false` (**truncate**), luego un job carga a BQ. Las SF outputs son `Carga_de_lectura__c` **INSERT** (+ `Opportunity` **UPDATE** para el anual).

- **anuales** (rama account, no-flexible, `tAggregateRow_1` group `[billing_account_id, Dominio__c, invoice_month]`): 24 cols `billing_account_id, Dominio__c, OpportunityId__c, SKU__c, CurrencyIsoCode__c, TotalSupport, Margen__c, Total_gcp, Magen_gcp⚠, Total_gmp, Margen_gmp, Margen_total, Cargo_Google__c, Importe__c, invoice_month, invoce_date⚠, cambio_aplicado, project_id, descripcion, Margen_gcp_euros, Margen_gmp_euros, Margen_soporte_euros, Margen_soporte_maps_euros, Total_thirdparty`. **+ UPDATE Opportunity** `Control_lectura_anuales_Consumo__c += Importe__c`.
- **flexibles** (rama account, `billing_model=="Flexible" && Importe!=0`) → SF INSERT (20 cols). *No hay CSV con ese nombre conectado.* → **duda §7.7**.
- **soporte** (rama project, `tMap_10` recálculo, filtro `Importe>0 && SKU!=null && ((SKU!=1419&&SKU!=1421)||SKU==1421)` → **de GCP solo pasa 1421**): 25 cols, `Cargo_Google__c=0`, `descripcion="Soporte técnico"`, márgenes gcp/gmp=0.
- **desglosadas** (rama account, `billing_model=="Flexible" && Importe>0`): 28 cols = anuales + `billing_model, Margen_SWO, Total_thirdparty, Cargo_Google_GCP, Cargo_Google_GMP`.

⚠ **Typos a preservar** (las vistas dependen): `Magen_gcp` (sin 'r'), `invoce_date` (sin 'i', en anuales/desglosadas; soporte usa `invoice_date` correcto).

---

## 6. Lo que se TIRA

1. CSV `tMap_7→tFileOutputDelimited_2` (proyecto desglosado): redundante, no es salida oficial.
2. `Margen_base_GCP=0.12` / `Margen_base_GMP=0.2` hardcodeados: solo en `Cargo_google` **comentado** → muertos.
3. Todas las **fórmulas comentadas/legacy** (versiones viejas de márgenes, `Cargo_google`, `Margen`, `Margen_anterior`).
4. Var `Margen_anterior` (calculada, nunca mapeada).
5. Passthrough: `tReplicate_6`, `tFilterRow_10`, `tLogRow_1/2/3`, `tFilterColumns_1` → colapsar.
6. CSVs intermedios (mecanismo Talend→BQ): desaparecen, todo en BQ.
7. Referencia cruzada en tMap_5 a `OpProduct_..._billing_account.Margen_SWO` (copy-paste): limpiar al alias correcto.

---

## 7. Decisiones (respondidas por Ángel)

0. **Salida ANUALES → FUERA DEL ALCANCE**: ningún país tiene actualmente cuentas anuales, así que
   la rama de anuales del job (tAggregateRow_1 → tMap_6 → `bq_lecturas_anuales` + UPDATE Opportunity)
   **no se replica**. Las salidas a migrar son: **flexibles, by_project/desglosadas y soporte**.
   La salida **desglosadas se valida con España** (tiene cuentas con Desglosar=SI; ~400 filas/mes).

1. **Soporte "oficial"** → **se mantiene la SEPARACIÓN** (ver §7.1): dos reglas de soporte según
   `Desglosar_Facturas`. NO desglosadas → soporte dentro de factura, sin importe fijo, ROUND 6.
   Desglosadas → línea de soporte aparte, con importe fijo, ROUND 2. El motor lleva **ambas**.
2. **`Carga_de_lectura__c`** → **INSERT** (se mantiene como hoy). Nota: reprocesar un mes duplicará
   registros en SF; si en el futuro molesta, se revisa external id.
3. **Acumulado anual a Salesforce** → **NO hace falta**. Se elimina el `UPDATE Opportunity`
   (`Control_lectura_anuales_Consumo__c`). La salida `anuales` sigue yendo a BQ; no se escribe en SF.
4. **Doble `/100` en descuentos** → **RESUELTO EMPÍRICAMENTE: es UN solo /100** (el "doble" era una
   mala lectura del XML). Probado con España 202605, que tiene descuentos reales (2.66/3/3.5/7 %):
   con /100 simple el diff es 0/0 en 399 filas; con doble /100 fallaban 85. No hay bug que revisar.
5. **Filtro SKU de soporte** (de GCP solo 1421, descarta 1419) → **intencional**. Se mantiene.
6. **Salidas de la rama project** → **directo a BigQuery (+ Salesforce)**. NADA de CSV intermedios
   (eran una limitación de Talend que se resolvía con fichero; no hacen falta).
7. **Salida "flexibles"** → **igual**: va a BigQuery y Salesforce, sin CSV intermedio.

> **Implicación transversal (6 y 7)**: en el rediseño desaparecen TODOS los CSV. Cada salida se
> materializa como **tabla BigQuery** (la escribe el SQL) y, las que aplican, se empujan a
> **Salesforce** (`Carga_de_lectura__c`, INSERT) vía la reverse-ETL en Python.

### 7.1 Única duda abierta — el doble cálculo de soporte (reformulada)

El "soporte técnico" se calcula con **dos fórmulas distintas** según el modo de facturación de la cuenta:

- **Cuentas NO desglosadas** (`Desglosar_Facturas="NO"`, rama account): el soporte va **dentro** del
  importe de factura, y se calcula como `consumo_gcp × %soporte` con mínimo, **SIN sumar el importe
  fijo** (`Sop_Tec_imp_fijo`), redondeo **6** decimales.
- **Cuentas desglosadas** (`Desglosar_Facturas="SI"`, rama project): el soporte es una **línea aparte**
  ("Soporte técnico"), y se calcula como `(consumo_gcp + thirdparty) × %soporte + importe_fijo`, con
  mínimo, redondeo **2** decimales.

**Pregunta para Ángel**: ¿es **a propósito** que el soporte se calcule distinto según `Desglosar`
(las no-desglosadas omiten el importe fijo y redondean a 6; las desglosadas suman el fijo y redondean
a 2)? ¿O las dos deberían usar la **misma fórmula** (y una está obsoleta)? — Esto decide si el motor
lleva una sola regla de soporte o dos ramas.

---

## 8. Rediseño propuesto (SQL plano, sin dbt)

Capas (ficheros en `config/queries/`, ejecutados por el loader Python). La fórmula vive **una vez**:

```
staging (Python → BQ):  stg_opportunities, stg_line_items, stg_oli_marketplace
ya en BQ:               sum_costs_credits_per_month, sum_costs_credits_per_month_by_project
                        currency_exchange_rates

int_opportunity_economics   ← §3.3/3.5/3.6 aplanado por (billing_account/Opp): márgenes, descuentos,
                              params de soporte, Margen_SWO, billing_model, flag marketplace.

motor (1 SELECT reusable, §3.4-3.10) aplicado a:
  fct_facturacion_by_account  = motor(consumo_account ⋈ economics ⋈ marketplace ⋈ rates), GROUP BY billing_account
  fct_facturacion_by_project  = motor(consumo_project ⋈ economics ⋈ rates),               GROUP BY billing_account, project

outputs (proyecciones/filtros de los fct, sin recalcular):
  importes_lecturas_anuales, _flexibles, _soporte, _by_project (+ desglosadas)

reverse-ETL (Python, idempotente, aparte): Carga_de_lectura__c, UPDATE Opportunity anual.
```

**Validación**: cada salida se compara fila a fila contra la tabla del Talend (diff 0/0), como se hizo
con `billing_accounts`. Nada se da por bueno sin eso.
