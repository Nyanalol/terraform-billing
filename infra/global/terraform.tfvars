# Valores reales del componente global.
# Solo paises ya desplegados (con su dataset looker_views).
countries = {
  "hong-kong" = "swo-billing-prod-hk"
  "ecuador"   = "swoec-billing-prod"
  "usa"       = "swous-billing-prod"
  "mexico"    = "swo-billing-prod-484513"
  "colombia"  = "swoco-billing-prod"
  "india"     = "swoin-billing-prod"
  "vietnam"   = "swovn-billing-prod"
  "belgium"   = "swobe-billing-prod"
  "singapore" = "swosg-billing-prod"
  "italy"     = "swoit-billing-prod"
  "switzerland" = "swo-billing-prod"
  "france"      = "swofr-billing-prod"
  "uk"          = "swouk-billing-prod"
  "germany"     = "swode-billing-prod"
  "netherlands" = "swonl-billing-prod"
  # Brasil: southamerica-east1 -> copia cross-region a 'br_src' (EU) en el propio proyecto global.
  "brazil"      = "swo-billingglobal-prod"
  "spain"       = "ip-billing-prod"
}

# Países antiguos: leen sus vistas estándar desde 'consolidado_src' (NO se toca su looker_views).
looker_dataset_overrides = {
  "switzerland" = "consolidado_src"
  "france"      = "consolidado_src"
  "uk"          = "consolidado_src"
  "germany"     = "consolidado_src"
  "netherlands" = "consolidado_src"
  "brazil"      = "br_src"
  "spain"       = "consolidado_src"
}

# La 8ª tabla (importes_lecturas_workspace): Brasil desde la copia EU; España la tiene en
# BILLING_CLOUD_PLATFORM, así que se expone también en su consolidado_src.
billing_dataset_overrides = {
  "brazil" = "br_src"
  "spain"  = "consolidado_src"
}
