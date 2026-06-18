# GENERADO por tools/gen_tfvars.py desde countries.yaml — NO editar a mano.
# PAÍS ANTIGUO / ESQUELETO — NO desplegar tal cual. Ver docs/MIGRACION_PAISES_ANTIGUOS.md.

project_id                     = "swode-billing-prod"
country                        = "germany"
billing_cloud_platform_dataset = "BILLINGDE_CLOUD_PLATFORM"
location                       = "EU"

payer_billing_accounts = {}

currency_symbols = {
  "EUR" = "€"
  "USD" = "$"
  "GBP" = "£"
  "HKD" = "HK$"
  "INR" = "₹"
  "VND" = "₫"
  "MXN" = "MX$"
  "COP" = "COL$"
  "SGD" = "S$"
  "CHF" = "Fr"
  "BRL" = "R$"
}

create_service_account = false   # la SA ya existe (creada a mano antes de Terraform)
create_hmac_key     = false

# Cláusula Empresa_IP__c de Salesforce (config Talend). Ver generate-config-billing.ps1.
sf_empresa_ip = "Empresa_IP__c='001IV00000gVL84'"
