output "dataset_ids" {
  description = "BigQuery dataset IDs created by this deployment."
  value       = module.billing_datasets.dataset_ids
}
