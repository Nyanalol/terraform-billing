-- ─── DDL reference: reseller_billing_detailed_export_v1 ──────────────────────
-- This file is NOT referenced by Terraform (the schema is managed outside it).
-- Run this DDL manually in BigQuery when the real schema is defined.
-- TODO: replace placeholder columns with actual schema.

CREATE OR REPLACE TABLE `@project_id.@dataset.reseller_billing_detailed_export_v1`
(
  -- TODO: define columns
  placeholder STRING OPTIONS(description = 'TODO: define schema')
)
OPTIONS(
  labels = [("managed_by", "terraform")]
);
