WITH base_billing AS (
  SELECT 
    *,
    IFNULL(pba.account_name, 'Unknown') AS account
  FROM `${project_id}.${billing_cp_dataset}.reseller_billing_detailed_export_v1` AS export
  LEFT JOIN `${project_id}.${billing_cp_dataset}.payer_billing_accounts` AS pba ON export.payer_billing_account_id = pba.payer_billing_account_id
  WHERE billing_account_id LIKE '%-%-%'
),

extracted_credits AS (
  SELECT
    service.description AS service,
    IFNULL(cost, 0) AS cost,
    invoice.month AS invoice_month,
    account,
    IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) AS c), 0) AS all_creditos,
    IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) AS c WHERE c.type IS NULL OR c.type != 'RESELLER_MARGIN'), 0) AS creditos,
    IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) AS c WHERE c.type = 'RESELLER_MARGIN'), 0) AS creditos_reseller
  FROM base_billing
  WHERE service.description <> 'Invoice'
),

costes AS (
  SELECT
    service,
    invoice_month,
    account,
    IFNULL(SUM(cost), 0) AS cost,
    SUM(creditos) AS creditos,
    SUM(creditos_reseller) AS creditos_reseller,
    SUM(all_creditos) AS all_creditos
  FROM extracted_credits
  GROUP BY 1, 2, 3
),

summary_metrics AS (
  SELECT
    invoice_month,
    account,
    SUM(cost) + SUM(creditos) AS consumo,
    SUM(cost) AS cost,
    SUM(all_creditos) AS all_creditos,
    SUM(creditos) AS creditos,
    SUM(creditos_reseller) AS creditos_reseller,
    (
      SELECT IFNULL(SUM(c_temp.cost), 0)
      FROM costes c_temp
      WHERE c_temp.service IN ('Reseller Program', 'Maps Reseller Program')
        AND costes.invoice_month = c_temp.invoice_month
        AND costes.account = c_temp.account
    ) AS descuento_reseller_old,
    IFNULL(SUM(IFNULL(creditos_reseller, 0)), 0) AS descuento_reseller_new
  FROM costes
  WHERE service NOT IN ('Reseller Program', 'Maps Reseller Program')
  GROUP BY invoice_month, account
)

SELECT 
  *,
  descuento_reseller_old + descuento_reseller_new AS descuento_reseller
FROM summary_metrics
ORDER BY invoice_month DESC;