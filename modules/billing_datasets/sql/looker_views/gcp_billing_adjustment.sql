SELECT
  invoice.month AS invoice_month,
  sku.description AS sku,
  cost,
  cost_type,
  adjustment_info.adjustment_description AS adjustment_description,
  adjustment_info.adjustment_type AS adjustment_type,
  IFNULL(pba.account_name, 'Unknown') AS account
FROM `${project_id}.${billing_cp_dataset}.reseller_billing_detailed_export_v1` AS export
LEFT JOIN `${project_id}.${billing_cp_dataset}.payer_billing_accounts` AS pba ON export.payer_billing_account_id = pba.payer_billing_account_id
WHERE cost_type = 'adjustment'
