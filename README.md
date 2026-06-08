# terraform-billing

Infraestructura **BigQuery de facturación por país** (SoftwareOne) gestionada con Terraform.
Cada país se despliega de forma **independiente** con su propio `tfvars/<país>.tfvars` y su
propio estado remoto (prefix por país en un bucket GCS compartido).

## Qué crea

Por cada país, el módulo `billing_datasets` despliega:

- **4 datasets** BigQuery: el de export (`BILLING_CLOUD_PLATFORM` o el nombre del país),
  `billing_views`, `looker_views`, `third_party`.
- **Tablas base** (export de Google, tablas externas de Sheets, lookups) y **~20 vistas**.
- **3 scheduled queries**: `maps_services`, `workspace_sku_sf`, `sku_third_party_migration_from_spain`.
- **Tablas lookup** `payer_billing_accounts` y `currency_symbols`, sembradas desde `tfvars`
  (sustituyen los `CASE WHEN` hardcodeados que antes había en las vistas).
- **Service account `bigquery-talend`** con sus permisos (propio proyecto + cruzados a España).
- **Bucket de staging** + **clave HMAC** para Talend.
- **APIs** del proyecto habilitadas.

Ver el detalle de dependencias en [docs/DEPENDENCY_DIAGRAM.md](docs/DEPENDENCY_DIAGRAM.md).

## Requisitos

- **Terraform** ≥ 1.5 (probado con 1.13.4).
- **Cuenta GCP:** siempre `@g.softwareone.com` (no mezclar con otras). Proyecto central de
  España: `ip-billing-prod`.
- **Credenciales para Terraform (ADC):** Terraform usa Application Default Credentials, **no**
  las de `gcloud auth login`. Configúralas una vez:
  ```bash
  gcloud auth application-default login --account=<tu_cuenta>@g.softwareone.com
  ```
  > Atajo sin navegador (token temporal, ~1h), útil si el ADC apunta a otra cuenta:
  > `$env:GOOGLE_OAUTH_ACCESS_TOKEN = gcloud auth print-access-token --account=<tu_cuenta>@g.softwareone.com`
- **Bucket de estado** (bootstrap, una sola vez para todo el equipo):
  ```bash
  gcloud storage buckets create gs://ip-billing-terraform-state \
    --project=ip-billing-prod --location=EU \
    --uniform-bucket-level-access --public-access-prevention
  gcloud storage buckets update gs://ip-billing-terraform-state --versioning
  ```

## Desplegar un país

Cada país tiene su fichero en `tfvars/<país>.tfvars` (datos en [docs/PAISES.md](docs/PAISES.md)).

```bash
# 1. Crea el tfvars del país copiando la plantilla
cp tfvars/example.tfvars tfvars/<país>.tfvars   # y rellénalo

# 2. Inicializa el backend con el prefix del país (-reconfigure al cambiar de país)
terraform init -reconfigure -backend-config="prefix=billing/<país>"

# 3. Revisa y aplica
terraform plan  -var-file="tfvars/<país>.tfvars"
terraform apply -var-file="tfvars/<país>.tfvars"

# 4. Recoge los outputs para Ops / Talend
terraform output service_account_email     # pásaselo a Ops para el JSON key
terraform output hmac_access_id
terraform output -raw hmac_secret          # sensible (guardar en C:\billing\<país>)
```

### Aplicar a varios países (en bucle)

```powershell
.\deploy-countries.ps1                              # plan de todos
.\deploy-countries.ps1 -Action apply -Countries hong-kong   # apply de uno
.\deploy-countries.ps1 -Action apply                # apply de todos (¡con cuidado!)
```

Regla de oro: `plan` de todos → revisar → `apply` a uno → verificar → `apply` al resto.

Checklist completo paso a paso: [docs/DEPLOY_CHECKLIST.md](docs/DEPLOY_CHECKLIST.md).

## Qué automatiza Terraform y qué no

Mapeo del procedimiento de despliegue (los 27 pasos) a responsable:

| Paso | Descripción | Responsable |
|---|---|---|
| 1 | Crear proyecto GCP | **OPS** |
| 2 | Dataset donde va el export | OPS define el destino · **Terraform** crea el dataset |
| 3 | Export `reseller_billing_detailed_export_v1` | **OPS** (Terraform crea la tabla shell con `ignore_changes`) |
| 4 | Permisos personales en el proyecto | Manual (DATA) |
| 5 | SA `bigquery-talend` + permisos | ✅ **Terraform** |
| — | Habilitar creación de JSON keys | **OPS** (org policy) |
| — | Descargar el JSON de la SA | **OPS** (tras crearla Terraform) |
| 6 | Rellenar `terraform.tfvars` | DATA (input) |
| 7 | `init` / `plan` / `apply` | DATA |
| 8 | Compartir el Google Sheet con la SA | Manual (DATA) — Terraform no gestiona Sheets |
| 10 | Permisos cruzados Maps desde España | ✅ **Terraform** |
| 11 | Scheduled query `maps_services` | ✅ **Terraform** |
| 12 | Permisos SA desde proyecto España | ✅ **Terraform** |
| — | Guardar el JSON / apuntar el config del país | Manual (DATA) |
| 15 | Bucket GCS de staging | ✅ **Terraform** |
| 16 | Access/secret key (HMAC) | ✅ **Terraform** |
| 17-21 | Config de Talend, contexto `win_xx`, currencies.csv | Manual (DATA) — Talend local |
| 22-25 | Pruebas, compilar y desplegar jobs de Talend | Manual (DATA) — fuera de alcance |
| 26 | Vistas `looker_views` | ✅ **Terraform** |
| 27 | Dashboard | Manual — **Data Studio**, no gestionable con Terraform |

**Frontera:** Terraform cubre toda la capa BigQuery + la SA + el staging/HMAC + las APIs.
Quedan **fuera** (manual): la configuración y compilación de los **jobs de Talend** (pasos 17-25)
y los **dashboards de Data Studio** (paso 27), porque ninguno de los dos es gestionable con
Terraform.

## Estructura del repo

```
main.tf, variables.tf, outputs.tf, versions.tf, backend.tf   # raíz
deploy-countries.ps1                                         # bucle de despliegue multi-país
tfvars/
  example.tfvars           # plantilla por país
  <país>.tfvars            # valores reales (gitignored)
docs/                      # checklist, diagrama, datos de países
modules/billing_datasets/
  apis.tf                  # APIs del proyecto
  service_account.tf       # SA bigquery-talend + IAM (propio + España)
  staging.tf               # bucket de staging + HMAC
  routines.tf              # stored procedure borrar_lecturas_mes
  main.tf                  # los 4 datasets
  tables_*.tf              # tablas y vistas
  scheduled_queries.tf     # las 3 scheduled queries
  seed_data.tf             # carga de las tablas lookup desde tfvars
  sql/                     # el SQL de cada vista / query / rutina
```

## Documentos relacionados

- [docs/DEPLOY_CHECKLIST.md](docs/DEPLOY_CHECKLIST.md) — checklist operativo paso a paso.
- [docs/PAISES.md](docs/PAISES.md) — datos de cada país (nuevos de Ops + inventario de los antiguos).
- [docs/DEPENDENCY_DIAGRAM.md](docs/DEPENDENCY_DIAGRAM.md) — diagrama de dependencias de tablas/vistas.

## Notas importantes

- **Estado por país:** cada país vive en `gs://ip-billing-terraform-state/billing/<país>/`.
  Equivocarse de `prefix` en el `init` = trabajar sobre el estado de otro país. Cuidado.
- **Países ya existentes:** si la SA ya existe (creada a mano), pon `create_service_account = false`.
  Si no quieres que Terraform toque la IAM de España, `manage_spain_iam = false`.
- **Los `tfvars/<país>.tfvars` no se suben al repo** (`.gitignore`): contienen los valores
  reales de cada país. Solo se versiona `tfvars/example.tfvars`.
- **Borrado mensual de lecturas:** stored procedure `billing_views.borrar_lecturas_mes(anyo, mes, dry_run)`.
  Con `dry_run = TRUE`/`NULL` solo muestra los parámetros resueltos (no borra); con `FALSE` borra.
  Si `anyo`/`mes` van `NULL`, usa el mes anterior. Ej: `CALL ...borrar_lecturas_mes(NULL, NULL, TRUE)`.
