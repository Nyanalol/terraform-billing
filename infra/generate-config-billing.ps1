<#
.SYNOPSIS
  Genera el config_billing_<codigo>.txt de un pais para Talend.

.DESCRIPTION
  Usa un config que YA funciona como plantilla (por defecto Colombia) y solo sobrescribe lo
  pais-especifico: proyecto, rutas, dataset workspace, bucket, HMAC y la clausula Empresa_IP.
  Todo lo demas (credenciales SF, JWT, lista de SKUs, etc.) se copia de la plantilla TAL CUAL,
  asi que los SECRETOS no van en este script ni en el repo: viven solo en C:\billing.

  La clausula Empresa_IP se saca del tfvars del pais (variable sf_empresa_ip), que puede ser
  una sola o varias con OR. El resto de la linea sf_opp_query_condition se conserva de la plantilla.

.EXAMPLE
  .\generate-config-billing.ps1 -Country usa
  .\generate-config-billing.ps1 -Country mexico -Month 06 -Year 2026
#>
param(
  [Parameter(Mandatory)][string]$Country,
  [string]$Month = (Get-Date).ToString("MM"),
  [string]$Year = (Get-Date).ToString("yyyy"),
  [string]$TemplateConfig = "C:\billing\colombia\config_billing_co.txt"
)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$env:CLOUDSDK_PYTHON = "C:\Users\miguel.gonzalez-albo\AppData\Local\Google\Cloud SDK\google-cloud-sdk\platform\bundledpython\python.exe"
$env:CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE = "$env:USERPROFILE\gcloud-corp-ca.pem"
$env:GOOGLE_OAUTH_ACCESS_TOKEN = (gcloud auth print-access-token --account=miguel.gonzalez-albo@g.softwareone.com)

# Pais -> codigo (para nombre de fichero y bucket).
$codes = @{ "hong-kong" = "hk"; "ecuador" = "ec"; "usa" = "us"; "mexico" = "mx"; "colombia" = "co"; "india" = "in"; "vietnam" = "vn"; "belgium" = "be"; "singapore" = "sg" }
$code = $codes[$Country]
if (-not $code) { throw "No conozco el codigo del pais '$Country'. Anadelo al mapa codes en el script." }
if (-not (Test-Path $TemplateConfig)) { throw "No existe la plantilla: $TemplateConfig" }

# Datos del tfvars del pais.
$tf = "$root\tfvars\$Country.tfvars"
$proj = (Select-String -Path $tf -Pattern 'project_id\s*=\s*"([^"]+)"').Matches[0].Groups[1].Value
$empM = Select-String -Path $tf -Pattern 'sf_empresa_ip\s*=\s*"(.+)"'
$empresa = if ($empM) { $empM.Matches[0].Groups[1].Value } else { "" }
if (-not $empresa) { Write-Warning "sf_empresa_ip vacio en $tf -> sf_opp_query_condition saldra sin la clausula de empresa." }

# HMAC desde los outputs de Terraform.
terraform -chdir="$root" init -reconfigure -input=false -backend-config="prefix=billing/$Country" *> $null
$aid = terraform -chdir="$root" output -raw hmac_access_id 2>$null
$sec = terraform -chdir="$root" output -raw hmac_secret 2>$null

# Ruta del JSON de la SA (puede llevar sufijo de key-id; lo localizamos por glob).
$jsonDir = "C:\facturacion\swo-product_facturacion-es\config"
$jsonFile = Get-ChildItem "$jsonDir\$proj*.json" -ErrorAction SilentlyContinue | Select-Object -First 1
$jsonPath = if ($jsonFile) { $jsonFile.FullName } else { "$jsonDir\$proj.json" }

$dir = "C:\billing\$Country"
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
$cfg = "$dir\config_billing_$code.txt"

# Plantilla (preserva orden y todas las lineas, incluidos secretos y JWT).
$tmpl = Get-Content $TemplateConfig

# Reconstruir sf_opp_query_condition: <clausula empresa del pais> + el sufijo fijo de la plantilla.
$suffix = ""
$refLine = $tmpl | Where-Object { $_ -like 'sf_opp_query_condition|*' } | Select-Object -First 1
if ($refLine) {
  $val = $refLine.Substring($refLine.IndexOf('|') + 1)
  $idx = $val.IndexOf(' and billing_account_id__c')
  if ($idx -ge 0) { $suffix = $val.Substring($idx) }
}
$newSfopp = "$empresa$suffix"

# Campos que se sobrescriben por pais (el resto se copia de la plantilla).
$ov = @{
  "config"                 = $cfg
  "proyecto"               = $proj
  "month"                  = $Month
  "year"                   = $Year
  "accountServiceFilePath" = $jsonPath
  "ruta_entrada"           = "$dir\"
  "cs_output_bucket"       = "gcp-billing-process-staging-$code"
  "cs_access_key"          = $aid
  "cs_secret_key"          = $sec
  "sf_opp_query_condition" = $newSfopp
}

$out = foreach ($line in $tmpl) {
  if ($line -notmatch '\|') { $line; continue }
  $key = $line.Substring(0, $line.IndexOf('|'))
  if ($ov.ContainsKey($key)) { "$key|$($ov[$key])" } else { $line }
}
[System.IO.File]::WriteAllLines($cfg, [string[]]$out, (New-Object System.Text.ASCIIEncoding))
Write-Host "OK -> $cfg" -ForegroundColor Green
Write-Host "  Empresa_IP: $empresa" -ForegroundColor DarkGray
Write-Host "  mes/anio:   $Month/$Year   (cambialo con -Month/-Year si toca)" -ForegroundColor DarkGray
