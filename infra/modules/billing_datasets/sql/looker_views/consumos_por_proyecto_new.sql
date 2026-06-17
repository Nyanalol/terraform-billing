SELECT
  account.billing_account_desc__c AS billing_account_desc,
  IF(project.project_id IS NULL, '<<<Google Adjustments>>>', project.project_id) AS project_id,
  account.billing_model__c AS billing_model,
  project.invoice_month,
  project.cost_gcp,
  project.credits_gcp,
  project.cost_gmp,
  project.credits_gmp,
  project.reseller_margin_gmp,
  project.reseller_margin_gcp
FROM `${project_id}.${billing_views_dataset}.sum_costs_credits_per_month_by_project` project
LEFT JOIN `${project_id}.${billing_views_dataset}.billing_accounts` account
  ON project.billing_account_id = account.billing_account_id__c