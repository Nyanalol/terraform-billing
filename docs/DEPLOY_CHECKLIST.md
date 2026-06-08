# Checklist de despliegue — nuevo país

Cada país tiene su propio `terraform.tfvars` y se despliega de forma **independiente**.  
Copia [`terraform.tfvars.example`](terraform.tfvars.example) como `terraform.tfvars`, rellena los valores del país y sigue esta lista antes de ejecutar `terraform apply`.

---

## 1. Proyecto GCP

- [ ] El proyecto GCP existe y está activo.
- [ ] Las APIs las habilita **Terraform** (`apis.tf`: `bigquery`, `bigquerydatatransfer`, `storage`).
      Ya no hace falta activarlas a mano; solo que la cuenta que aplica pueda habilitar servicios
      (`roles/serviceusage.serviceUsageAdmin` o equivalente).
- [ ] Tienes credenciales con permisos suficientes para crear datasets, tablas, Data Transfer
      configs, la service account, su IAM, el bucket de staging y la clave HMAC
      (`roles/owner` sobre el proyecto del país suele ser lo más simple).
- [ ] Si `manage_spain_iam = true`: la cuenta que aplica tiene `setIamPolicy` sobre `ip-billing-prod`.

---

## 2. ⭐ Cuentas pagadoras — lo más importante a configurar

Este es el equivalente a los bloques `CASE WHEN payer_billing_account_id = '...' THEN '...'` que antes estaban hardcodeados en las vistas. Ahora se configura aquí, en [`terraform.tfvars`](terraform.tfvars), y Terraform lo carga en la tabla `payer_billing_accounts` automáticamente al hacer apply.

Todas las vistas de `billing_views` y `looker_views` hacen un `LEFT JOIN` contra esta tabla para resolver el nombre de cuenta. Si un ID no está en el mapa, las vistas mostrarán `Unknown`.

### Cómo encontrar los IDs

Los `payer_billing_account_id` son los IDs de las cuentas de facturación pagadoras de Google.  
Puedes localizarlos en:
- BigQuery → dataset `BILLING_CLOUD_PLATFORM` → tabla `reseller_billing_detailed_export_v1` → columna `payer_billing_account_id`
- Google Cloud Billing console → apartado "Cuentas de facturación" → columna ID (formato `XXXXXX-YYYYYY-ZZZZZZ`)

### Qué rellenar en `terraform.tfvars`

```hcl
# Una línea por cada cuenta pagadora del país.
# Clave   = payer_billing_account_id tal como aparece en los datos de Google
# Valor   = nombre que se mostrará en los cuadros de mando
payer_billing_accounts = {
  "AAAAAA-BBBBBB-CCCCCC" = "Cuenta Principal"
  "DDDDDD-EEEEEE-FFFFFF" = "Cuenta Secundaria"   # añade tantas como haga falta
}
```

- [ ] He buscado todos los `payer_billing_account_id` distintos que tiene este país.
- [ ] He añadido una entrada en `payer_billing_accounts` por cada uno, con un nombre descriptivo.

> **Nota:** El formato del ID es `XXXXXX-YYYYYY-ZZZZZZ`, sin el prefijo `billingAccounts/`.

---

## 3. Resto de campos de `terraform.tfvars`

Toma como referencia [`terraform.tfvars.example`](terraform.tfvars.example).

- [ ] **`project_id`** — ID exacto del proyecto GCP (ej. `my-company-billing-es`).
- [ ] **`country`** — Identificador corto del país (ej. `spain`). Se usa en labels y descripciones.
- [ ] **`billing_cloud_platform_dataset`** — Nombre del dataset de billing. Por defecto `BILLING_CLOUD_PLATFORM`; cámbialo si el país usa un nombre distinto.
- [ ] **`location`** — Región de BigQuery (`EU`, `US`, `europe-west1`…). Debe coincidir con la región donde está configurado el export de Google.
- [ ] **`labels`** — Etiquetas adicionales para todos los recursos.
- [ ] **`scheduled_query_service_account`** — Email del SA para las scheduled queries `workspace_sku_sf` y `maps_services` (ver sección 4).

---

## 4. Cuentas de servicio (las crea Terraform — paso 5 del checklist guarro)

**Ahora Terraform crea la SA `bigquery-talend` y le asigna los permisos** (fichero
`modules/billing_datasets/service_account.tf`). Ya **no** hay que crearla a mano antes del apply.
Quien manda en los permisos es **DATA (Terraform)**; Ops solo descarga el JSON de la SA ya creada.

Roles que asigna Terraform:

| Dónde | Roles |
|---|---|
| Proyecto del país | `roles/owner`, `roles/bigquery.admin`, `roles/bigquery.connectionUser` |
| Proyecto de España (`ip-billing-prod`), cruzado | `roles/bigquery.dataViewer`, `roles/bigquery.jobUser` |

- [ ] Si la SA **ya existe** en el proyecto (creada a mano antes), poner `create_service_account = false`
      en el `terraform.tfvars` (o hacer `terraform import`), para que el apply no choque.
- [ ] Quien hace `apply` tiene `setIamPolicy` sobre `ip-billing-prod` (para los bindings cruzados).
      Si no, poner `manage_spain_iam = false` y dar esos permisos a mano.
- [ ] Tras el apply, **pasar la SA a Ops** para que descarguen el JSON key.

### `sku_third_party_migration_service_account` _(solo si el país recibe migración de terceros)_
Usada por la query **sku\_third\_party\_migration\_from\_spain**.

| Recurso | Rol necesario |
|---|---|
| Dataset `third_party` (proyecto destino) | `roles/bigquery.dataEditor` |
| Dataset `BILLING_CLOUD_PLATFORM` (proyecto origen) | `roles/bigquery.dataViewer` |
| Proyecto destino | `roles/bigquery.jobUser` |
| Proyecto origen | `roles/bigquery.jobUser` |

- [ ] SA creado (o dejado vacío `""` si el país no recibe esta migración).
- [ ] `sku_third_party_source_project` apunta al proyecto origen correcto (o `""` si no aplica).

---

## 5. Export de billing de Google

Terraform crea las tablas con schema vacío y `lifecycle { ignore_changes = [schema] }` para no interferir con los exports.

- [ ] El export de **Detailed Usage Cost** está configurado apuntando a `BILLING_CLOUD_PLATFORM` → tabla `reseller_billing_detailed_export_v1`.
- [ ] El feed de **Workspace SKU** está siendo ingestado en → tabla `ext_workspace_sku_sf`.

> Si los exports aún no están activos, el apply funciona igualmente: Terraform crea las tablas vacías y Google rellenará el schema cuando empiece a escribir.

---

## 6. Inicializar el backend remoto (estado en GCS)

El estado de Terraform vive en un bucket de GCS compartido (`ip-billing-terraform-state`,
proyecto `ip-billing-prod`), **no en local**. Cada país tiene su propio "espacio" de estado
mediante un `prefix` distinto. Hay que pasar el prefix del país al inicializar:

```bash
terraform init -backend-config="prefix=billing/spain"   # cambiar 'spain' por el país
```

- [ ] He inicializado con el `prefix` correcto del país (`billing/<país>`).
- [ ] No me he equivocado de país en el prefix (un prefix erróneo trabajaría sobre el estado de otro país).

> El bucket de estado se crea **una sola vez** para todo el equipo (bootstrap manual):
> ```bash
> gcloud storage buckets create gs://ip-billing-terraform-state \
>   --project=ip-billing-prod --location=EU \
>   --uniform-bucket-level-access --public-access-prevention
> gcloud storage buckets update gs://ip-billing-terraform-state --versioning
> ```

---

## 7. Revisar el plan antes de aplicar

```bash
terraform plan -out=plan.tfplan
```

Comprueba en el plan:

- [ ] Se crean los 4 datasets: `BILLING_CLOUD_PLATFORM` (o el nombre configurado), `billing_views`, `looker_views`, `third_party`.
- [ ] Se crean las ~20 tablas y vistas esperadas.
- [ ] Se crean las 3 `google_bigquery_data_transfer_config` (scheduled queries).
- [ ] Se crea 1 `google_bigquery_job` para la carga inicial de `payer_billing_accounts`.
- [ ] No aparece ningún `destroy` inesperado.

---

## 8. Después del apply

- [ ] Verificar en BigQuery console que los 4 datasets existen con las tablas y vistas correctas.
- [ ] Abrir una vista (ej. `billing_gcp`) y hacer un `SELECT * … LIMIT 10` — no debe dar error de referencia.
- [ ] Comprobar en **BigQuery → Data Transfer** que las 3 scheduled queries aparecen con estado activo.
- [ ] Ejecutar manualmente la scheduled query `workspace_sku_sf` una vez para validar permisos del SA.
- [ ] Verificar la tabla `payer_billing_accounts`: debe tener tantas filas como entradas configuradas en el mapa.

---

## Actualizar las cuentas pagadoras en un país ya desplegado

Si en el futuro cambian las cuentas pagadoras (nuevo ID, cambio de nombre…):

1. Edita `payer_billing_accounts` en [`terraform.tfvars`](terraform.tfvars) — añade, modifica o elimina entradas.
2. Ejecuta `terraform apply`.
3. Terraform detecta que el mapa cambió (el hash en el `job_id` cambia) y lanza automáticamente un nuevo `google_bigquery_job` que hace `CREATE OR REPLACE TABLE payer_billing_accounts` con los datos actualizados.
