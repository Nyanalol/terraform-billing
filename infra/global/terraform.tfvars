# GENERADO por tools/gen_global_tfvars.py desde countries.yaml — NO editar a mano.
# Fuente única de la config de países: countries.yaml.

countries = {
  "belgium"     = "swobe-billing-prod"
  "brazil"      = "swo-billingglobal-prod"
  "colombia"    = "swoco-billing-prod"
  "ecuador"     = "swoec-billing-prod"
  "france"      = "swofr-billing-prod"
  "germany"     = "swode-billing-prod"
  "hong-kong"   = "swo-billing-prod-hk"
  "india"       = "swoin-billing-prod"
  "italy"       = "swoit-billing-prod"
  "mexico"      = "swo-billing-prod-484513"
  "netherlands" = "swonl-billing-prod"
  "singapore"   = "swosg-billing-prod"
  "spain"       = "ip-billing-prod"
  "switzerland" = "swo-billing-prod"
  "uk"          = "swouk-billing-prod"
  "usa"         = "swous-billing-prod"
  "vietnam"     = "swovn-billing-prod"
}

# Países antiguos: el consolidado lee sus vistas estándar de 'consolidado_src' (looker_views intacto).
looker_dataset_overrides = {
  "brazil"      = "br_src"
  "france"      = "consolidado_src"
  "germany"     = "consolidado_src"
  "netherlands" = "consolidado_src"
  "spain"       = "consolidado_src"
  "switzerland" = "consolidado_src"
  "uk"          = "consolidado_src"
}

# La 8ª tabla (importes_lecturas_workspace) donde no está en billing_views.
billing_dataset_overrides = {
  "brazil" = "br_src"
  "spain"  = "consolidado_src"
}
