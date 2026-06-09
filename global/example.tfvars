# Componente global (capa unificada UNION ALL). Copiar como global/terraform.tfvars.
# Despliegue:
#   terraform -chdir=global init -reconfigure -backend-config="prefix=billing/global"
#   terraform -chdir=global apply -var-file="terraform.tfvars"

# SOLO países ya desplegados (con su dataset looker_views). Añade más según despliegues.
countries = {
  "hong-kong" = "swo-billing-prod-hk"
  # "italy"   = "swoit-billing-prod"
  # "mexico"  = "swo-billing-prod-484513"
}

# Opcionales (valores por defecto entre paréntesis):
# global_project_id = "swo-billingglobal-prod"
# global_dataset    = "looker_views_global"
# months_back       = 3
# schedule          = "every day 05:00"
