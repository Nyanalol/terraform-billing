<#
.SYNOPSIS
  Refresca (dispara ya) las tablas del consolidado global, sin esperar al run diario (05:00).

.DESCRIPTION
  Lanza un run manual de todas las scheduled queries global_union_* en swo-billingglobal-prod.
  Util justo despues de ejecutar Talend en un pais nuevo, para que las tablas Talend-dependientes
  (importes_lecturas, vista_importes_lecturas, importes_lecturas_workspace) aparezcan al momento.
  Las de consumos GCP ya se actualizan solas (vienen del export).

.EXAMPLE
  .\refresh-consolidado.ps1
#>
$ErrorActionPreference = 'Stop'
$env:CLOUDSDK_PYTHON = "C:\Users\miguel.gonzalez-albo\AppData\Local\Google\Cloud SDK\google-cloud-sdk\platform\bundledpython\python.exe"
$env:CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE = "$env:USERPROFILE\gcloud-corp-ca.pem"
$env:CLOUDSDK_CORE_ACCOUNT = "miguel.gonzalez-albo@g.softwareone.com"

$project = "swo-billingglobal-prod"
$now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$configs = bq ls --transfer_config --transfer_location=eu --project_id=$project --format=prettyjson 2>$null | ConvertFrom-Json |
Where-Object { $_.displayName -like "global_union_*" }

Write-Host "Disparando $($configs.Count) scheduled queries del consolidado (run_time $now)..." -ForegroundColor Yellow
foreach ($c in $configs) {
  bq mk --transfer_run --run_time=$now $c.name *> $null
  "  - $($c.displayName)"
}
Write-Host "Hecho. En ~1 min las tablas swo-billingglobal-prod.looker_views_global.* estaran actualizadas." -ForegroundColor Green
