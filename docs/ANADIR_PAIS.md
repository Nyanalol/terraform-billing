# Añadir un país nuevo — guía

Procedimiento real para dar de alta un país en este Terraform, con los gotchas que
aprendimos en el rollout. Para el detalle del módulo ver [DEPLOY_CHECKLIST.md](DEPLOY_CHECKLIST.md);
para migrar un país **antiguo** (ya desplegado a mano) ver [MIGRACION_PAISES_ANTIGUOS.md](MIGRACION_PAISES_ANTIGUOS.md).

## Prerrequisitos (una vez para todo el equipo, ya hechos)

- Bucket de estado `ip-billing-terraform-state` creado (proyecto `ip-billing-prod`).
- Repo clonado; `terraform` + `gcloud` (cuenta `@g.softwareone.com`) configurados; ADC/token SWO.
- Quien aplica tiene `projectIamAdmin` sobre `ip-billing-prod` (para el IAM cruzado a España).

---

## 1. Lo que pides a OPS

| # | OPS hace | Por qué |
|---|---|---|
| 1 | Crear el **proyecto GCP** | — |
| 2 | Crear el **dataset del export** (`BILLINGxx_CLOUD_PLATFORM`, multiregion EU) | El módulo lo **importa**, no lo crea |
| 3 | Crear el **export** `reseller_billing_detailed_export_v1` | Fuente de todo |
| 4 | Darte **acceso al proyecto**: Editor **+ Project IAM Admin** (o Owner) | Crear SA, IAM, buckets, keys |
| 5 | **Desactivar la org policy** `iam.disableServiceAccountKeyCreation` en ese proyecto (Manage policy → Override parent → Enforcement **Off**) | Desbloquea **JSON key Y HMAC** (es la misma constraint para ambas) |

**Datos que te tienen que dar (para el tfvars):**

- `project_id`
- Nombre **exacto** del dataset del export → ⚠️ **verifícalo en BigQuery**, a veces difiere de lo
  que dicen (ej. `BILLING_VN_CLOUD_PLATFORM` con guion bajo, o el typo `BIILING_CLOUD_PLATFORM` de Suiza).
- `location` (normalmente EU).
- Las **cuentas pagadoras**: `payer_billing_account_id` (formato `XXXXXX-YYYYYY-ZZZZZZ`) + nombre de cada una.

---

## 2. Lo que haces tú (DATA)

### a) Crear el tfvars
Copia `tfvars/example.tfvars` → `tfvars/<pais>.tfvars` y rellena:
```hcl
project_id                     = "swoxx-billing-prod"
country                        = "<pais>"
billing_cloud_platform_dataset = "BILLINGXX_CLOUD_PLATFORM"   # el EXACTO, verificado
location                       = "EU"
payer_billing_accounts = { "XXXXXX-YYYYYY-ZZZZZZ" = "SWO ... _EUR", ... }
scheduled_query_service_account = "bigquery-talend@swoxx-billing-prod.iam.gserviceaccount.com"
staging_bucket_name             = "gcp-billing-process-staging-xx"
create_hmac_key                 = true
```

### b) Desplegar
El script importa solo los objetos pre-creados por OPS (dataset + tablas del export) y
reintenta por el lag de propagación de la SA:
```powershell
.\deploy-countries.ps1 -Action plan  -Countries <pais>   # revisar el diff
.\deploy-countries.ps1 -Action apply -Countries <pais>
```

### c) JSON key de la SA
```powershell
gcloud iam service-accounts keys create `
  "C:\facturacion\swo-product_facturacion-es\config\<project_id>.json" `
  --iam-account="bigquery-talend@<project_id>.iam.gserviceaccount.com" `
  --account="miguel.gonzalez-albo@g.softwareone.com"
```

### d) Sacar la HMAC y montar el config de Talend
```powershell
terraform -chdir="." init -reconfigure -backend-config="prefix=billing/<pais>"
terraform -chdir="." output -raw hmac_access_id    # -> cs_access_key
terraform -chdir="." output -raw hmac_secret       # -> cs_secret_key
```
Crea `C:\billing\<pais>\config_billing_<codigo>.txt` con el formato estándar (proyecto, ruta del
JSON, `bq_*` datasets/tablas, `cs_output_bucket|gcp-billing-process-staging-<codigo>`,
`cs_access_key`/`cs_secret_key`, `sf_user/pass/token` constantes, `month`/`year`).

### e) Añadir al consolidado (Data Studio único)
- Añade el país al mapa `countries` de `global/terraform.tfvars`.
- `terraform -chdir=global init -reconfigure -backend-config="prefix=billing/global"`
- `terraform -chdir=global apply -var-file="terraform.tfvars"`
- Dispara las scheduled queries `global_union_*` (o espera al run diario de las 05:00).

### f) Talend (manual, pasos 17-25 del checklist)
Carpeta config, contexto `win_xx`, compilar y desplegar jobs. Esto llena `importes_lecturas*`
(hasta entonces esas tablas — y su parte del consolidado — salen vacías).

### g) Data Studio
Ya sale en el dashboard único (filtro `country`) en cuanto esté en el consolidado (paso e).

---

## Gotchas / troubleshooting

- **409 "Already Exists"** al aplicar → OPS pre-creó el dataset/tablas; el `deploy-countries.ps1`
  los importa solo. Si aplicas a mano, importa antes: el dataset, `reseller_billing_detailed_export_v1`
  y `gcp_billing_accounts_name_id`.
- **404 "service account not found"** en una scheduled query → lag de propagación de la SA recién
  creada; el script reintenta el apply (o reaplica tú).
- **"Key creation is not allowed" / Error 412 en HMAC** → la org policy del paso 5 sigue activa en
  ese proyecto; que OPS la deje en Enforcement Off.
- **"Error acquiring the state lock"** (tras un apply que murió) → lock colgado:
  `terraform -chdir="." force-unlock -force <LOCK_ID>` (el ID sale en el propio error).
- **Dataset del export con nombre raro** → verifícalo siempre en BigQuery antes de poner
  `billing_cloud_platform_dataset`.
