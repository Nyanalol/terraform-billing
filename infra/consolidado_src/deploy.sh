#!/usr/bin/env bash
# Despliegue IDEMPOTENTE de consolidado_src (lo que se creó a mano esta sesión, ahora versionado).
#
# Crea, por país antiguo, el dataset `consolidado_src` con las 7 vistas estándar (desde los .sql
# capturados en sql/<país>/), y para Brasil la cadena cross-region completa (materialización en
# southamerica-east1 + copia a swo-billingglobal-prod.br_src + los 2 transfers diarios).
#
# El consolidado (infra/global/) ya lee de estos datasets vía looker_dataset_overrides /
# billing_dataset_overrides en infra/global/terraform.tfvars (generado desde countries.yaml).
#
# Requiere: bq autenticado (cuenta g.softwareone.com) + CA corporativa.
# Uso:  bash infra/consolidado_src/deploy.sh [pais|all]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

# país -> project_id (EU, in-vivo)
declare -A PROJ=(
  [switzerland]=swo-billing-prod [france]=swofr-billing-prod [uk]=swouk-billing-prod
  [germany]=swode-billing-prod [netherlands]=swonl-billing-prod [spain]=ip-billing-prod
)

deploy_eu() {
  local c=$1 p=${PROJ[$1]}
  echo "### $c ($p) ###"
  bq --project_id="$p" --location=EU mk --dataset \
    --description "Vistas estandar para el consolidado global. NO tocar looker_views/billing_views (reporting heredado)." \
    "$p:consolidado_src" 2>/dev/null || true
  for f in "$HERE/sql/$c"/*.sql; do
    [ -s "$f" ] || continue
    # los DDL capturados son CREATE VIEW; -> CREATE OR REPLACE para idempotencia
    sed 's/^CREATE VIEW/CREATE OR REPLACE VIEW/' "$f" \
      | bq --project_id="$p" --location=EU query --use_legacy_sql=false --format=none
    echo "  ok $(basename "$f" .sql)"
  done
}

deploy_brazil() {
  local BR=ipdb-billing-interno G=swo-billingglobal-prod
  local SA_GLOBAL=bq-global-union@swo-billingglobal-prod.iam.gserviceaccount.com
  local SA_TALEND=bigquery-talend@ipdb-billing-interno.iam.gserviceaccount.com
  echo "### brazil (cross-region) ###"
  # 1) dataset BR (southamerica) + materializacion (tablas, ventana 3m)
  bq --project_id="$BR" --location=southamerica-east1 mk --dataset \
    --description "Materializacion 7+1 tablas estandar (3m) para copia cross-region al consolidado EU." \
    "$BR:consolidado_src" 2>/dev/null || true
  bq --project_id="$BR" --location=southamerica-east1 query --use_legacy_sql=false --format=none \
    < "$(dirname "$HERE")/scripts/br_materialize.sql"
  # 2) dataset destino EU en el proyecto global
  bq --project_id="$G" --location=EU mk --dataset \
    --description "Copia cross-region (BR southamerica-east1) de las tablas estandar de Brasil." \
    "$G:br_src" 2>/dev/null || true
  echo "  NOTA: el SA global necesita READER en $BR:consolidado_src; el SA Talend WRITER (ver README)."
  echo "  NOTA: los 2 transfers (materializacion 03:30 BR + copia 04:00 EU) se crean con bq mk --transfer_config (ver README)."
}

target=${1:-all}
if [ "$target" = "all" ]; then
  for c in switzerland france uk germany netherlands spain; do deploy_eu "$c"; done
  deploy_brazil
elif [ "$target" = "brazil" ]; then
  deploy_brazil
else
  deploy_eu "$target"
fi
echo "Hecho. Refresca el consolidado: infra/refresh-consolidado.ps1 (o dispara las scheduled queries)."
