# Checklist de despliegue — nuevo país

Cada país tiene su propio `terraform.tfvars` y se despliega de forma **independiente**.  
Copia [`terraform.tfvars.example`](terraform.tfvars.example) como `terraform.tfvars`, rellena los valores del país y sigue esta lista antes de ejecutar `terraform apply`.

---

## 1. Proyecto GCP

- [ ] El proyecto GCP existe y está activo.
- [ ] Las APIs necesarias están habilitadas en el proyecto:
  - `bigquery.googleapis.com`
  - `bigquerydatatransfer.googleapis.com` ← necesaria para las scheduled queries
- [ ] Tienes credenciales con permisos suficientes para crear datasets, tablas y Data Transfer configs  
  (`roles/bigquery.admin` + `roles/bigquerydatatransfer.admin` o equivalente).

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

## 4. Cuentas de servicio (crear antes del apply)

Las scheduled queries necesitan service accounts existentes en GCP. Créalos antes de referenciarlos en tfvars.

### `scheduled_query_service_account`
Usada por **workspace\_sku\_sf** y **maps\_services**.

| Recurso | Rol necesario |
|---|---|
| Dataset `BILLING_CLOUD_PLATFORM` | `roles/bigquery.dataEditor` |
| Proyecto | `roles/bigquery.jobUser` |

- [ ] SA creado y email anotado en `terraform.tfvars`.

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

## 6. Revisar el plan antes de aplicar

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

## 7. Después del apply

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
