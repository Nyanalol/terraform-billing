# ─── Backend remoto de estado (GCS) ──────────────────────────────────────────
# El estado de Terraform (su "inventario" de recursos) se guarda en un bucket de
# GCS compartido, NO en local. Así todo el equipo trabaja sobre el mismo estado y
# Terraform bloquea el fichero mientras alguien aplica (evita applies simultáneos).
#
# El bucket se crea UNA SOLA VEZ a mano (bootstrap), porque Terraform no puede
# gestionar el bucket donde guarda su propio estado. Comando de bootstrap:
#
#   gcloud storage buckets create gs://ip-billing-terraform-state --project=ip-billing-prod --location=EU --uniform-bucket-level-access --public-access-prevention
#   gcloud storage buckets update gs://ip-billing-terraform-state --versioning
#
# El `prefix` se pasa POR PAÍS al inicializar (no se fija aquí), para que el mismo
# código sirva para todos los países sin editar este fichero:
#
#   terraform init -backend-config="prefix=billing/spain"
#   terraform init -backend-config="prefix=billing/mexico"
#   ...

terraform {
  backend "gcs" {
    bucket = "ip-billing-terraform-state"
    # prefix = se pasa con -backend-config en el init (uno por país)
  }
}
