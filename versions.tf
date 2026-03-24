terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  # Credentials are read from the GOOGLE_APPLICATION_CREDENTIALS env var
  # or from Application Default Credentials (gcloud auth application-default login).
  # No default project is set here; each resource declares its own project_id.
}
