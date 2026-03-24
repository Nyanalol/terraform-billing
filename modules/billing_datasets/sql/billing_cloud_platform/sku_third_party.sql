-- ─── DDL reference: sku_third_party ──────────────────────────────────────────
-- This file is NOT referenced by Terraform (the schema is managed outside it).
-- Run this DDL manually in BigQuery when the real schema is defined.
-- TODO: replace placeholder columns with actual schema.

CREATE OR REPLACE TABLE `@project_id.@dataset.sku_third_party`
(
  -- TODO: define columns
  placeholder STRING OPTIONS(description = 'TODO: define schema')
)
OPTIONS(
  labels = [("managed_by", "terraform")]
);
