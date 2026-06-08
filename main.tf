module "billing_datasets" {
  source = "./modules/billing_datasets"

  project_id                                = var.project_id
  country                                   = var.country
  billing_cloud_platform_dataset            = var.billing_cloud_platform_dataset
  location                                  = var.location
  scheduled_query_service_account           = var.scheduled_query_service_account
  payer_billing_accounts                    = var.payer_billing_accounts
  currency_symbols                          = var.currency_symbols
  ext_maps_services_sheet_url               = var.ext_maps_services_sheet_url
  ext_workspace_sku_sf_sheet_url            = var.ext_workspace_sku_sf_sheet_url
  sku_third_party_migration_service_account = var.sku_third_party_migration_service_account

  service_account_id     = var.service_account_id
  create_service_account = var.create_service_account
  spain_project_id       = var.spain_project_id
  manage_spain_iam       = var.manage_spain_iam

  staging_bucket_name = var.staging_bucket_name
  create_hmac_key     = var.create_hmac_key
}
