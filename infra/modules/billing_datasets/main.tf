locals {
  common_labels = {
    country    = var.country
    managed_by = "terraform"
  }
}

# ─── Dataset 1: BILLING_CLOUD_PLATFORM (name is configurable) ────────────────

resource "google_bigquery_dataset" "billing_cloud_platform" {
  project                    = var.project_id
  dataset_id                 = var.billing_cloud_platform_dataset
  friendly_name              = "Billing Cloud Platform"
  description                = "Billing Cloud Platform data for ${var.country}"
  location                   = var.location
  delete_contents_on_destroy = false
  labels                     = local.common_labels
}

# ─── Dataset 2: billing_views ────────────────────────────────────────────────

resource "google_bigquery_dataset" "billing_views" {
  project                    = var.project_id
  dataset_id                 = "billing_views"
  friendly_name              = "Billing Views"
  description                = "Billing views for ${var.country}"
  location                   = var.location
  delete_contents_on_destroy = false
  labels                     = local.common_labels
}

# ─── Dataset 3: looker_views ──────────────────────────────────────────────────

resource "google_bigquery_dataset" "looker_views" {
  project                    = var.project_id
  dataset_id                 = "looker_views"
  friendly_name              = "Looker Views"
  description                = "Looker views for ${var.country}"
  location                   = var.location
  delete_contents_on_destroy = false
  labels                     = local.common_labels
}

# ─── Dataset 4: third_party ────────────────────────────────────────────────────────

resource "google_bigquery_dataset" "third_party" {
  project                    = var.project_id
  dataset_id                 = "third_party"
  friendly_name              = "Third Party"
  description                = "Third-party SKU reference data for ${var.country}"
  location                   = var.location
  delete_contents_on_destroy = false
  labels                     = local.common_labels
}
