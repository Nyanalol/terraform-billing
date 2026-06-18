#!/usr/bin/env bash
# Valida los marts mix_and_match de un país contra Talend, en el sandbox.
# READ-ONLY sobre prod + escritura SOLO al sandbox ip-trabajo-apeinado. NUNCA escribe en Salesforce.
#
# Uso: bash tools/validate_country.sh <talend_ctx> <project_id> [talend_dataset]
#   ej: bash tools/validate_country.sh win_vn swovn-billing-prod billing_views
#
# Requiere el entorno gcloud+venv+token ya exportado y los parches runtime aplicados (ver VALIDACION_MARTS.md).
set -uo pipefail
CTX=$1; PROJ=$2; TALDS=${3:-billing_views}
SB=ip-trabajo-apeinado; M=202605; ROOT="$(cd "$(dirname "$0")/.." && pwd)"
Q(){ bq --project_id=$SB --location=EU query --use_legacy_sql=false --format=none "$1" 2>&1 | grep -iE 'error' | head -1; }

# NOTA: la ETL lee la config de país de countries.yaml; ETL_MODE=sandbox (default) -> ip-trabajo-apeinado.
export ETL_MODE=sandbox
# 1) vista sum_costs -> país (read prod / la vista vive en sandbox)
Q "CREATE OR REPLACE VIEW \`$SB.billing_views.sum_costs_credits_per_month\` AS SELECT * FROM \`$PROJ.billing_views.sum_costs_credits_per_month\`"
# 2) staging (SF read -> sandbox stg_*). Desglosar_Facturas__c ya sale 'SI'/'NO' (fix en el staging).
( cd "$ROOT/etl" && .venv/Scripts/python.exe -m src.etl.jobs.mix_and_match_staging --country "$CTX" --month 05 --year 2026 >/dev/null 2>&1 )
# 3) get_data (-> sandbox bq_group_*)
( cd "$ROOT/etl" && .venv/Scripts/python.exe -m src.etl.jobs.get_data --country "$CTX" --month 05 --year 2026 >/dev/null 2>&1 )
# 6) marts (SQL -> sandbox)
for m in flexibles by_project soporte; do
  sed -e "s/{project}/$SB/g" -e "s/{transformed_dataset}/billing_views/g" -e "s/{invoice_month}/$M/g" \
      -e "s/{currencies_project}/$SB/g" -e "s/{currencies_dataset}/billing_views/g" -e "s/{currencies_table}/currency_exchange_rates/g" \
    "$ROOT/etl/config/queries/materialize_importes_$m.sql" | bq --project_id=$SB --location=EU query --use_legacy_sql=false --format=none >/dev/null 2>&1
done
# 7) diff vs Talend (flexibles fila a fila por clave+importe redondeado)
bq --project_id=$SB --location=EU query --use_legacy_sql=false --format=csv \
"WITH n AS (SELECT billing_account_id,OpportunityId__c,SAFE_CAST(SKU__c AS FLOAT64) s,ROUND(SAFE_CAST(Importe__c AS FLOAT64),2) i FROM \`$SB.billing_views.flex_new\`),
      t AS (SELECT billing_account_id,OpportunityId__c,SAFE_CAST(SKU__c AS FLOAT64) s,ROUND(SAFE_CAST(Importe__c AS FLOAT64),2) i FROM \`$PROJ.$TALDS.importes_lecturas_temp\` WHERE invoice_month='$M')
 SELECT (SELECT COUNT(*) FROM n) flex_nuevo,(SELECT COUNT(*) FROM t) flex_talend,
   (SELECT COUNT(*) FROM(SELECT*FROM n EXCEPT DISTINCT SELECT*FROM t)) solo_nuevo,
   (SELECT COUNT(*) FROM(SELECT*FROM t EXCEPT DISTINCT SELECT*FROM n)) solo_talend,
   (SELECT COUNT(*) FROM \`$SB.billing_views.project_new\`) by_project,
   (SELECT COUNT(*) FROM \`$SB.billing_views.soporte_new\`) soporte" 2>/dev/null | tail -1 \
   | awk -F, -v c="$CTX" '{printf "  %-10s flex %s/%s (solo_n=%s solo_t=%s) | by_project=%s soporte=%s\n",c,$1,$2,$3,$4,$5,$6}'
