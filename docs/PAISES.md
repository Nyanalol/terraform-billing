# Países a desplegar — datos de Operaciones

> Fuente: email de Operaciones (recibido 2026-06-08). Datos para rellenar el
> `terraform.tfvars` de cada país cuando se despliegue. Todos en `location = "EU"`.
>
> **SA:** Operaciones confirma la nomenclatura `bigquery-talend@<project_id>.iam.gserviceaccount.com`
> (coincide con el default `service_account_id = "bigquery-talend"` del módulo). Piden que
> les facilitemos la SA de cada país para asignarle permisos y descargar el JSON.
> **PENDIENTE DE DECIDIR con Ops:** si los permisos los pone Terraform (lo que estamos
> construyendo en P2) o los pone Ops a mano. Ver nota al final.

## Estado de despliegue

| País | Estado | Notas |
|---|---|---|
| Hong Kong | Desplegado (prueba) | Estado migrado a `billing/hong-kong`. Ver discrepancias abajo. |
| Italia | Pendiente | |
| Vietnam | Pendiente | |
| USA | Pendiente | |
| México | Pendiente | |
| Colombia | Pendiente | |
| Ecuador | Pendiente | |
| Bélgica | Pendiente | |
| Singapore | Pendiente | |
| India | Pendiente | |

---

## Datos por país (listos para `terraform.tfvars`)

### Italia
```hcl
project_id                     = "swoit-billing-prod"
country                        = "italy"
billing_cloud_platform_dataset = "BILLINGIT_CLOUD_PLATFORM"
location                       = "EU"
payer_billing_accounts = {
  "011588-6DAA41-00B2F2" = "SWO ITALY_EUR"
  "012D46-9BB008-D9D029" = "SWO ITALY_USD"
}
# init: terraform init -backend-config="prefix=billing/italy"
```

### Vietnam
```hcl
project_id                     = "swovn-billing-prod"
country                        = "vietnam"
billing_cloud_platform_dataset = "BILLINGVN_CLOUD_PLATFORM"
location                       = "EU"
payer_billing_accounts = {
  "01979E-D5CB5A-E064DB" = "SWO VIETNAM_USD"
}
# init: terraform init -backend-config="prefix=billing/vietnam"
```

### USA
```hcl
project_id                     = "swous-billing-prod"
country                        = "usa"
billing_cloud_platform_dataset = "BILLINGUS_CLOUD_PLATFORM"
location                       = "EU"
payer_billing_accounts = {
  "014A14-300F5E-58E68F" = "SWO USA_USD"
}
# init: terraform init -backend-config="prefix=billing/usa"
```

### México
```hcl
project_id                     = "swo-billing-prod-484513"
country                        = "mexico"
billing_cloud_platform_dataset = "BILLINGMX_CLOUD_PLATFORM"
location                       = "EU"
payer_billing_accounts = {
  "010CE7-4E8471-6CA88E" = "SWO MEXICO_MXN"
  "01AEA2-F3EE1F-C36BDE" = "SWO MEXICO_USD"
}
# init: terraform init -backend-config="prefix=billing/mexico"
```

### Colombia
```hcl
project_id                     = "swoco-billing-prod"
country                        = "colombia"
billing_cloud_platform_dataset = "BILLINGCO_CLOUD_PLATFORM"
location                       = "EU"
payer_billing_accounts = {
  "012514-E29E2A-7004C7" = "SWO COLOMBIA_USD"
}
# init: terraform init -backend-config="prefix=billing/colombia"
```

### Ecuador
```hcl
project_id                     = "swoec-billing-prod"
country                        = "ecuador"
billing_cloud_platform_dataset = "BILLINGEC_CLOUD_PLATFORM"
location                       = "EU"
payer_billing_accounts = {
  "010EC5-F9AD4D-3F556B" = "SWO ECUADOR_USD"
}
# init: terraform init -backend-config="prefix=billing/ecuador"
```

### Hong Kong  *(ya desplegado)*
```hcl
project_id                     = "swo-billing-prod-hk"
country                        = "hong-kong"   # OJO: el desplegado tiene typo "honk-kong"
billing_cloud_platform_dataset = "BILLING_HK_CLOUD_PLATFORM"  # email dice BILLINGHK (sin _); el desplegado es BILLING_HK
location                       = "EU"
create_service_account         = false         # la SA ya existe (creada a mano)
payer_billing_accounts = {
  "012026-D15FE4-ACC5D6" = "SWO HONG KONG_USD"   # único cargado hoy
  "01351C-58F6C0-88AC96" = "SWO HONG KONG_HKD"   # FALTA en el tfvars desplegado — añadir
}
# init: terraform init -backend-config="prefix=billing/hong-kong"
```

### Bélgica
```hcl
project_id                     = "swobe-billing-prod"
country                        = "belgium"
billing_cloud_platform_dataset = "BILLINGBE_CLOUD_PLATFORM"
location                       = "EU"
payer_billing_accounts = {
  "01F127-DED7D3-5138B6" = "SWO BELGIUM_EUR"
  "018972-66E343-DEF21E" = "SWO BELGIUM_USD"
}
# init: terraform init -backend-config="prefix=billing/belgium"
```

### Singapore
```hcl
project_id                     = "swo-sg-billing-prod"
country                        = "singapore"
billing_cloud_platform_dataset = "BILLINGSG_CLOUD_PLATFORM"
location                       = "EU"
payer_billing_accounts = {
  "016521-E5DD08-72768E" = "SWO SINGAPORE_SGD"
  "01C5C9-AD6259-5D2D50" = "SWO SINGAPORE_USD"
}
# init: terraform init -backend-config="prefix=billing/singapore"
```

### India
```hcl
project_id                     = "swoin-billing-prod"
country                        = "india"
billing_cloud_platform_dataset = "BILLING_IN_CLOUD_PLATFORM"   # OJO: lleva _ (distinto al resto)
location                       = "EU"
payer_billing_accounts = {
  "01AD72-412BCE-A0F562" = "SWO INDIA_INR"
}
# init: terraform init -backend-config="prefix=billing/india"
```

---

## Notas / cosas a vigilar

- **Divisas:** asegúrate de que `currency_symbols` cubre EUR, USD, HKD, MXN, SGD, INR, VND, COP.
  El bloque por defecto de `terraform.tfvars.example` ya las trae casi todas.
- **Nomenclatura de datasets inconsistente** en el email: la mayoría es `BILLINGXX_CLOUD_PLATFORM`
  (sin `_`), pero India es `BILLING_IN_CLOUD_PLATFORM` y el HK desplegado es `BILLING_HK_CLOUD_PLATFORM`.
  Usa el valor exacto del dataset donde Ops haya creado el export (paso 3), no asumas el patrón.
- **Hong Kong:** el email lista 2 cuentas (HKD + USD) pero el tfvars desplegado solo tiene la USD.
  Si se quiere completar, añadir la HKD y `terraform apply` (re-lanza el seed de payer_billing_accounts).
- **Permisos / JSON — DECIDIDO:** manda **DATA (Terraform)**. Terraform crea la SA y le asigna
  TODOS los permisos (P2: owner + bigquery.admin + bigquery.connectionUser en el proyecto, y
  dataViewer + jobUser cruzados en España). **Ops solo descarga el JSON** de la SA ya creada.
  No se desactiva la gestión IAM (`manage_spain_iam = true`).

---

## Países ya existentes — migrar a Terraform en el futuro

> Inventario de los países que ya están en producción (montados a mano / con la versión
> antigua). El plan es aplicarles este Terraform también, más adelante. **Aquí manda DATA.**
> OJO: esta tabla **no trae los `payer_billing_account_id`** (solo el nombre de la cuenta);
> habrá que sacar los IDs de cada export en BigQuery antes de rellenar `payer_billing_accounts`.

| País | Proyecto GCP | Export Dataset | Dataset Talend Views | Dataset Looker Views | 3rd-Party Reseller | Cuentas (nombres) |
|---|---|---|---|---|---|---|
| España | `ip-billing-prod` | `BILLING_CLOUD_PLATFORM` | `BILLING_CLOUD_PLATFORM` | `billing_views` | TRUE | SWO SPAIN_EUR - OCRE, SWO SPAIN_EUR, SWO SPAIN_GBP, SWO SPAIN_USD |
| Brasil | `ipdb-billing-interno` | `BILLING_CLOUD_PLATFORMBRL` | `billing_views` | `billing_views` | FALSE | SWO BRAZIL_BRL_GCP, SWO BRAZIL_BRL_MAPS |
| Francia | `swofr-billing-prod` | `BILLINGFR_CLOUD_PLATFORM` | `billing_views` | `looker_views` | TRUE | SWO FRANCE_EUR, SWO FRANCE_USD |
| Holanda | `swonl-billing-prod` | `billing_export` | `billing_views` | `looker_views` | TRUE | SWO NETHERLANDS_EUR, SWO NL_EUR - OCRE |
| Alemania | `swode-billing-prod` | `BILLINGDE_CLOUD_PLATFORM` | `billing_views` | **MISSING** | TRUE | SWO GERMANY_EUR - OCRE, SWO GERMANY_EUR, SWO GERMANY_USD |
| Reino Unido | `swouk-billing-prod` | `BILLINGUK_CLOUD_PLATFORM` | `billing_views` | `looker_views` | TRUE | SWO UK_GBP, SWO UK_GBP - OCRE |
| Italia | `swoit-billing-prod` | `BILLINGIT_CLOUD_PLATFORM` | **NEED TO BE UPDATED** | **NEED TO BE UPDATED** | — | (sin datos) |
| Suiza | `swo-billing-prod` | `BIILING_CLOUD_PLATFORM` ⚠️ typo | `billing_views` | `looker_views` | TRUE | SWO SWITZERLAND_USD/EUR/CHF (varias, OCRE y Google Cloud) |

### Pegas a vigilar al migrar países antiguos

- **Los datasets de vistas NO son uniformes.** Este módulo asume `billing_views` (Talend) y
  `looker_views` (Looker), pero:
  - España y Brasil tienen las vistas Looker en `billing_views` (no en `looker_views`).
  - Alemania no tiene dataset de Looker views (**MISSING**).
  - Italia está **NEED TO BE UPDATED** (sin montar del todo).
  Aplicar el módulo tal cual a esos países crearía datasets nuevos (`looker_views`) en vez de
  usar los existentes → revisar caso por caso antes de `apply`.
- **Nombres de export dataset inconsistentes:** Holanda usa `billing_export` (minúsculas),
  Brasil `BILLING_CLOUD_PLATFORMBRL`, Suiza `BIILING_CLOUD_PLATFORM` (con doble I, **typo**).
  Usar el valor exacto en `billing_cloud_platform_dataset`, no asumir patrón.
- **3rd-Party Reseller Active = FALSE (Brasil):** no aplica la migración de `sku_third_party`
  desde España → dejar `sku_third_party_migration_service_account = ""` (y `manage_spain_iam`
  según corresponda). Los TRUE sí la necesitan.
- **Suiza comparte project_id `swo-billing-prod`** — verificar que no choca con otros recursos.
- **Faltan los `payer_billing_account_id`** de todos estos países (la tabla solo da nombres);
  sacarlos de `reseller_billing_detailed_export_v1` antes de rellenar el tfvars.
- **Informes Looker Studio:** las URLs de cada dashboard están en el email original; quedan
  fuera de Terraform (Looker Studio no se gestiona con TF), son solo referencia.
