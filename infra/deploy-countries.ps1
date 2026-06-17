<#
.SYNOPSIS
  Aplica la configuracion de Terraform a uno o varios paises (cada uno con su
  propio estado remoto y su propio tfvars).

.DESCRIPTION
  Recorre los paises haciendo, por cada uno:
    terraform init -reconfigure -backend-config="prefix=billing/<pais>"
    En apply: importa los objetos pre-creados por OPS (dataset y tablas del
    export) y luego terraform apply -var-file. El estado de cada pais esta
    aislado por su prefix en el bucket GCS.

.PARAMETER Action
  'plan' (por defecto, no cambia nada) o 'apply'.

.PARAMETER Countries
  Lista de paises a procesar. Vacio = todos los tfvars/*.tfvars (menos example).

.EXAMPLE
  .\deploy-countries.ps1                                  # plan de todos
  .\deploy-countries.ps1 -Action apply -Countries usa,mexico

.NOTES
  REGLA DE ORO: ejecuta primero 'plan', revisa los diffs, aplica a uno,
  verifica, y solo entonces 'apply' al resto.
#>
param(
  [ValidateSet('plan', 'apply')] [string]$Action = 'plan',
  [string[]]$Countries
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

# Entorno: gcloud tras el proxy + credenciales SWO para Terraform.
$env:CLOUDSDK_PYTHON = "C:\Users\miguel.gonzalez-albo\AppData\Local\Google\Cloud SDK\google-cloud-sdk\platform\bundledpython\python.exe"
$env:CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE = "$env:USERPROFILE\gcloud-corp-ca.pem"
$env:GOOGLE_OAUTH_ACCESS_TOKEN = (gcloud auth print-access-token --account=miguel.gonzalez-albo@g.softwareone.com)

# Lista de paises (de los tfvars, excluyendo el example).
if (-not $Countries) {
  $Countries = Get-ChildItem "$root\tfvars\*.tfvars" |
  Where-Object { $_.BaseName -ne 'example' } |
  ForEach-Object { $_.BaseName }
}

Write-Host "Accion: $Action | Paises: $($Countries -join ', ')" -ForegroundColor Yellow
$results = @()

foreach ($c in $Countries) {
  $vars = "$root\tfvars\$c.tfvars"
  if (-not (Test-Path $vars)) {
    Write-Host "[$c] SALTADO: no existe $vars" -ForegroundColor Red
    $results += [pscustomobject]@{ Pais = $c; Estado = 'SIN TFVARS' }
    continue
  }

  Write-Host "`n=== $c ($Action) ===" -ForegroundColor Cyan
  try {
    terraform -chdir="$root" init -reconfigure -input=false -backend-config="prefix=billing/$c" | Out-Null
    if ($Action -eq 'apply') {
      # Importa los objetos que pre-crea OPS (dataset del export + tablas del export) antes de
      # aplicar, para no chocar con 409 "Already Exists". Tolerante: si ya estan en estado o no
      # existen, el import falla sin parar (apply los crea si procede).
      $proj = (Select-String -Path $vars -Pattern 'project_id\s*=\s*"([^"]+)"').Matches[0].Groups[1].Value
      $dataset = (Select-String -Path $vars -Pattern 'billing_cloud_platform_dataset\s*=\s*"([^"]+)"').Matches[0].Groups[1].Value
      if ($proj -and $dataset) {
        $opsObjects = @(
          @{ addr = "module.billing_datasets.google_bigquery_dataset.billing_cloud_platform"; id = "$proj/$dataset" },
          @{ addr = "module.billing_datasets.google_bigquery_table.reseller_billing_detailed_export_v1"; id = "projects/$proj/datasets/$dataset/tables/reseller_billing_detailed_export_v1" },
          @{ addr = "module.billing_datasets.google_bigquery_table.gcp_billing_accounts_name_id"; id = "projects/$proj/datasets/$dataset/tables/gcp_billing_accounts_name_id" }
        )
        foreach ($o in $opsObjects) {
          # Tolerante: si ya esta en estado o el objeto no existe, ignoramos el fallo.
          # (Sin 2>&1, que en PS 5.1 + ErrorActionPreference=Stop lanzaria excepcion.)
          try { terraform -chdir="$root" import -input=false -var-file="$vars" $o.addr $o.id *> $null } catch {}
        }
      }
      terraform -chdir="$root" apply -auto-approve -input=false -var-file="$vars"
      if ($LASTEXITCODE -ne 0) {
        # Reintento: cubre el lag de propagacion de la SA recien creada (404 en los
        # data_transfer_config que la referencian en el primer apply).
        Write-Host "[$c] reintento de apply (posible propagacion de la SA)..." -ForegroundColor Yellow
        terraform -chdir="$root" apply -auto-approve -input=false -var-file="$vars"
      }
    }
    else {
      terraform -chdir="$root" plan -input=false -var-file="$vars"
    }
    $estado = if ($LASTEXITCODE -eq 0) { 'OK' } else { "ERROR ($LASTEXITCODE)" }
  }
  catch {
    $estado = "EXCEPCION: $($_.Exception.Message)"
  }
  $results += [pscustomobject]@{ Pais = $c; Estado = $estado }
}

Write-Host "`n===== RESUMEN =====" -ForegroundColor Yellow
$results | Format-Table -AutoSize
