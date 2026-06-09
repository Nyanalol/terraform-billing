# ─── Backend remoto de estado (GCS) ──────────────────────────────────────────
# Mismo bucket que el resto, prefix propio para el componente global.
# Inicializar con:
#   terraform -chdir=global init -reconfigure -backend-config="prefix=billing/global"

terraform {
  backend "gcs" {
    bucket = "ip-billing-terraform-state"
    # prefix = billing/global  (se pasa con -backend-config en el init)
  }
}
