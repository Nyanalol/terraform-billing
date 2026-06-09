# Migración de países antiguos a Terraform — análisis

> Análisis (solo lectura) del estado real de los países ya desplegados a mano, para
> planificar su importación a Terraform. Hecho el 2026-06-09. **Nada de esto está aplicado.**

## Inventario real (objetos por dataset)

| País | Proyecto | export dataset | billing_views | looker_views | third_party | SA |
|---|---|---|---|---|---|---|
| España | ip-billing-prod | BILLING_CLOUD_PLATFORM (35t/30v) | 2t/14v | ❌ no existe | ❌ no existe | ✅ |
| Brasil | ipdb-billing-interno | BILLING_CLOUD_PLATFORMBRL | 13t/20v | ❌ no existe | 3t | ✅ |
| Francia | swofr-billing-prod | BILLINGFR_CLOUD_PLATFORM | 7t/7v | 2t/8v | 3t | ✅ |
| Holanda | swonl-billing-prod | **billing_export** | 7t/6v | 1t/7v | 2t | ✅ |
| Alemania | swode-billing-prod | BILLINGDE_CLOUD_PLATFORM | 7t/6v | 1t/7v | 2t | ✅ |
| UK | swouk-billing-prod | BILLINGUK_CLOUD_PLATFORM | 8t/6v | 1t/7v | 2t | ✅ |
| Italia | swoit-billing-prod | BILLINGIT_CLOUD_PLATFORM | 6t/6v | 1t/6v | 2t | ✅ |
| Suiza | swo-billing-prod | **BIILING**_CLOUD_PLATFORM (typo) | 7t/7v | 1t/7v | ❌ no existe | ✅ |

(Los países tipo Francia/Alemania/UK/Italia tienen además un dataset extra
`..._CLOUD_PLATFORM_VIEWS` que **el módulo no gestiona** → se deja en paz.)

## Diferencia vs países nuevos

Los nuevos solo tenían 3 objetos de OPS que importar. Estos antiguos **ya tienen casi todo
creado** (4 datasets, ~40 tablas/vistas, la SA y scheduled queries propias). Traerlos a
Terraform es un **import masivo** (~40 objetos/país), no un apply fresco.

**Set de import por país (lo que gestiona el módulo):**
- Los 4 datasets (export + billing_views + looker_views + third_party).
- Las ~10 tablas del export que declara el módulo (reseller_billing_detailed_export_v1,
  gcp_billing_accounts_name_id, maps_services, gcp_billing_maps_sku, ext_*, workspace_sku_sf,
  sku_third_party, currency_symbols, payer_billing_accounts). El resto de tablas del export
  no las toca el módulo.
- Las tablas/vistas de billing_views, looker_views y third_party.
- La SA (`create_service_account = false`) y sus scheduled queries.

## ⚠️ Riesgo principal (común a todos): el SQL de las vistas

El import es mecánico. El peligro está en el `apply` posterior: al importar una vista,
Terraform la gestiona, y el `apply` **sobreescribe su SQL con el del módulo**. Las vistas
viejas tienen SQL distinto (España: CASE WHEN hardcodeado, `ip-billing-prod` fijo, etc.).
→ Antes de aplicar hay que **reconciliar vista por vista**. Ese es el trabajo real, no el
import. (Las tablas Talend con `ignore_changes=[schema]` no se pelean; el problema son las vistas.)

## Clasificación por dificultad

**🟢 Grupo A — estructura compatible (Francia, Holanda, Alemania, UK, Italia):**
Tienen los 4 datasets que espera el módulo. Mejores candidatos. Ajustes menores:
- Holanda: export = `billing_export` → `billing_cloud_platform_dataset = "billing_export"`.
- Italia: ya iniciada (3 recursos de APIs en su estado tras un apply parcial).

**🔴 Grupo B — divergentes (requieren decisiones / cambios):**
- **España** (ip-billing-prod): el más complejo y arriesgado. No tiene looker_views ni
  third_party; reporting en `tableau_views` + billing_views (14 vistas). Es el proyecto
  central (state bucket, origen de migración sku_third_party, lo lee el union) y tiene 30
  vistas en el export y muchos datasets extra. **Recomendado: dejar fuera de Terraform** o módulo a medida.
- **Brasil**: sin looker_views (reporting en billing_views, 20 vistas), ThirdParty Reseller
  Active = FALSE → `sku_third_party_migration_service_account = ""`.
- **Suiza**: sin third_party (el módulo lo crearía), export con typo `BIILING_CLOUD_PLATFORM`.

## Orden recomendado

1. Grupo A primero, con **Italia** como piloto del flujo "import masivo → reconciliar vistas → apply".
2. Grupo B (Brasil, Suiza) tras decidir cómo encajar sus datasets ausentes.
3. España la última o nunca por Terraform.

Pendiente: preparar la lista exacta de comandos `terraform import` por país (variante de
"import masivo" en `deploy-countries.ps1`, distinta del import ligero de países nuevos).
