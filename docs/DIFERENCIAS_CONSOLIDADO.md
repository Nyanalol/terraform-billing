# Diferencias entre las "queries nuevas" (consolidado) y las viejas — países antiguos

> Documenta, por país adaptado al consolidado global, qué transforma cada vista nueva
> (`consolidado_src` / copia EU) respecto a la vista vieja del país. Hecho el 2026-06-15.
>
> **Principio**: ninguna transformación cambia importes. Lo viejo de cada país (`looker_views`
> de los EU, `billing_views` de Brasil) **no se toca**; el consolidado lee de un dataset aparte.

## La ÚNICA diferencia de lógica real: `consumos_por_account`

Es la única vista con cálculo nuevo. La versión nueva **añade 4 columnas derivadas** que antes
se calculaban **en Data Studio**, bajadas ahora al SQL de la vista (mismas fórmulas):

| Columna nueva | Fórmula |
|---|---|
| `total_gcp_gmp` | `ROUND(total_gcp + total_gmp + total_thirdparty + total_thirdparty_marketplace, 2)` |
| `importe_margen` | `total_gmp*0.2 + total_gcp*0.1` |
| `total_net_cost` | `total_gcp_gmp + reseller_margin_gmp + reseller_margin_gcp + reseller_margin_thirdparty_marketplace` |
| `old_importe_factura_google` | `total_gcp + total_gmp - importe_margen` |

Las **19 columnas base son idénticas** a la vista vieja (verificado `EXCEPT DISTINCT` **0/0** en
Francia; en el resto el esquema base coincide y se reconstruye desde `billing_views.sum_costs_credits_per_month`).
La query nueva = la vieja + esas 4 columnas precalculadas.

Nota: `cargo_google` (= `total_gcp*0.9 + total_gmp*0.8`) **ya estaba** en la vista vieja (era la
columna 19), no es nueva.

## El resto = mismo dato, solo forma (para que la unión posicional cuadre)

La unión del consolidado es `SELECT *` posicional: exige mismo nº/orden/tipo de columnas en todos
los países. Estas transformaciones solo alinean forma, no tocan importes:

| Transformación | Qué hace | Países |
|---|---|---|
| Renombrar `consumos_support_plex` → `consumos_support_flex` | typo (plex→flex), mismo dato | FR, UK, DE, NL, BR |
| Renombrar `gcp_billing_adjustments` → `gcp_billing_adjustment` | plural→singular | FR, DE, NL, BR |
| Renombrar `consumos_google_reseller_facturas` → `...factura` | plural typo | DE |
| Reordenar `consumos_google_reseller_factura` (`account` a posición estándar 2) | mismo dato, otro orden | UK, DE, NL, BR |
| Cast a NUMERIC en `consumos_google_reseller_factura` | era FLOAT64 → NUMERIC (evita imprecisión float en dinero) | BR |
| Inyectar `0` en columnas ausentes | `ThirdParty_original`, `Margen_soporte_euros`, `Margen_soporte_maps_euros`, `reseller_margin_thirdparty_marketplace` (conceptos que no aplican / sin dato) | BR |

## Resumen por país

| País | Proyecto | consumos_por_account | Otras 6 vistas |
|---|---|---|---|
| Switzerland | `swo-billing-prod` | rebuild (+4 col); la vieja era `consumos_por account` (con espacio), 19 col | 6 wrappers idénticos |
| France | `swofr-billing-prod` | rebuild (+4 col), base 0/0 verificado | rename plex/plural + 4 wrappers |
| UK | `swouk-billing-prod` | rebuild (+4 col); la vieja tenía `currency` extra + orden distinto | rename plex + reorder factura + 3 wrappers |
| Germany | `swode-billing-prod` | rebuild (+4 col) | rename plex/plural/facturas + reorder + 3 wrappers |
| Netherlands | `swonl-billing-prod` | rebuild (+4 col) | rename plex/plural + reorder + 3 wrappers |
| Brazil | `ipdb-billing-interno` | rebuild (+4 col, `reseller_margin_tp_mkt`=0) | rename + reorder + cast NUMERIC + inyectar 0s + 8ª tabla `importes_lecturas_workspace` |

## Arquitectura por país

- **EU (CH, FR, UK, DE, NL)**: dataset `consolidado_src` en el propio proyecto del país, con las 7
  vistas estándar (la `consumos_por_account` calculada sobre `billing_views`; las demás wrappers/
  reorder sobre las vistas existentes). El consolidado lo lee en vivo. `looker_views` **intacto**.
- **Brasil (cross-region, southamerica-east1)**: no se puede unir en vivo cross-region. Cadena diaria:
  - `03:30 BR` scheduled query materializa las 8 tablas en `consolidado_src` (SA `bigquery-talend@ipdb-billing-interno`).
  - `04:00 EU` cross-region copy → `swo-billingglobal-prod.br_src` (SA `bq-global-union`).
  - `05:00 EU` la unión del consolidado lee `br_src` como un país más.
  - SQL de materialización: `scripts/br_materialize.sql`.

## Diferencias que NO son de las queries (son de tiles del dashboard)

Al comparar consolidado vs dashboard viejo de cada país, las únicas diferencias que aparecen son
de **configuración del informe**, no de datos:

- **Taxes %**: parámetro del panel (ej. Suiza IVA 8.1, no 20).
- **Total soporte**: el tile debe apuntar a `vista_importes_lecturas.TotalSupport` del consolidado,
  no a una fuente per-país heredada.
- **Importe total consumos (base vs no-base third-party)**: el consolidado usa `total_thirdparty`
  (no-base, = "Consumo Cliente v2" viejo). Solo difiere en **Brasil** (markup de marketplace,
  ~5.107,83); el resto de países tienen base = no-base. Decisión tomada: se queda la versión no-base/v2.
