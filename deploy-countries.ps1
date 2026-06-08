<#
.SYNOPSIS
  Aplica la configuración de Terraform a uno o varios países (cada uno con su
  propio estado remoto y su propio tfvars).

.DESCRIPTION
  Recorre los países haciendo, por cada uno:
    terraform init -reconfigure -backend-config="prefix=billing/<país>"
    terraform <plan|apply> -var-file="tfvars/<país>.tfvars"
  El estado de cada país está aislado por su prefix en el bucket GCS.

.PARAMETER Action
  'plan' (por defecto, no cambia nada) o 'apply'.

.PARAMETER Countries
  Lista de países a procesar. Vacío = todos los tfvars/*.tfvars (menos example).

.EXAMPLE
  .\deploy-countries.ps1                          # plan de todos
  .\deploy-countries.ps1 -Action apply -Countries hong-kong
  .\deploy-countries.ps1 -Action apply            # apply de todos (¡cuidado!)

.NOTES
  REGLA DE ORO: ejecuta primero 'plan' sobre todos, revisa los diffs, aplica a
  uno, verifica, y solo entonces 'apply' al resto.
#>
param(
  [ValidateSet('plan', 'apply')] [string]$Action = 'plan',
  [string[]]$Countries
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

# ─── Entorno (gcloud tras el proxy + credenciales SWO para Terraform) ─────────
$env:CLOUDSDK_PYTHON = "C:\Users\miguel.gonzalez-albo\AppData\Local\Google\Cloud SDK\google-cloud-sdk\platform\bundledpython\python.exe"
$env:CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE = "$env:USERPROFILE\gcloud-corp-ca.pem"
$env:GOOGLE_OAUTH_ACCESS_TOKEN = (gcloud auth print-access-token --account=miguel.gonzalez-albo@g.softwareone.com)

# ─── Lista de países (de los tfvars, excluyendo el example) ──────────────────
if (-not $Countries) {
  $Countries = Get-ChildItem "$root\tfvars\*.tfvars" |
    Where-Object { $_.BaseName -ne 'example' } |
    ForEach-Object { $_.BaseName }
}

Write-Host "Acción: $Action | Países: $($Countries -join ', ')" -ForegroundColor Yellow
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
      terraform -chdir="$root" apply -auto-approve -input=false -var-file="$vars"
    }
    else {
      terraform -chdir="$root" plan -input=false -var-file="$vars"
    }
    $estado = if ($LASTEXITCODE -eq 0) { 'OK' } else { "ERROR ($LASTEXITCODE)" }
  }
  catch {
    $estado = "EXCEPCIÓN: $($_.Exception.Message)"
  }
  $results += [pscustomobject]@{ Pais = $c; Estado = $estado }
}

Write-Host "`n===== RESUMEN =====" -ForegroundColor Yellow
$results | Format-Table -AutoSize
