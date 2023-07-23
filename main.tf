terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.74.0"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
}

locals {
  # The order of the stages is important, and we must preserve the one defined
  # by the user in the input variable. As for_each works with maps, the order
  # is lost. We preserve it here by prepending the stage key with its index in
  # the original list.
  sorted_stages = {
    for idx, val in var.stages : "${idx}_${val.name}" => val
  }
}

# This module ensures that all the necessary GCP APIs are enabled.
module "project_services" {
  source  = "terraform-google-modules/project-factory/google//modules/project_services"
  version = "~> 13.0"

  project_id  = var.gcp_project_id
  enable_apis = var.enable_apis

  activate_apis = [
    "cloudbuild.googleapis.com",
    "clouddeploy.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
  ]
  disable_services_on_destroy = false
}

# The Service Account to be used by the Cloud Build builds of this pipeline.
resource "google_service_account" "cloudbuild" {
  account_id   = "${var.service_name}-cloudbuild"
  display_name = "${var.service_name} pipeline - Service Account for Cloud Build builds"
}

module "cloudbuild_svc_acct_iam_member_roles" {
  source                  = "terraform-google-modules/iam/google//modules/member_iam"
  service_account_address = google_service_account.cloudbuild.email
  project_id              = var.gcp_project_id
  project_roles = [
    # Allows reading/pushing from/to Artifact Registry.
    "roles/artifactregistry.writer",
    # Allows writing logs to Cloud Logging.
    "roles/logging.logWriter",
    # Allows creating releases in Cloud Deploy.
    "roles/clouddeploy.releaser",
    # Allows storing objects and creating buckets in Cloud Storage (needed to
    # trigger Cloud Deploy releases).
    "roles/storage.admin",
    # Allows Cloud Build to use the service account that renders manifests
    # during a Cloud Deploy pipeline run.
    "roles/iam.serviceAccountUser",
  ]
}

# The Service Account to be used by the Cloud Deploy delivery pipeline.
resource "google_service_account" "clouddeploy" {
  account_id   = "${var.service_name}-clouddeploy"
  display_name = "${var.service_name} pipeline - Service Account for Cloud Deploy delivery pipelines"
}

module "clouddeploy_svc_acct_iam_member_roles" {
  source                  = "terraform-google-modules/iam/google//modules/member_iam"
  service_account_address = google_service_account.clouddeploy.email
  project_id              = var.gcp_project_id
  project_roles = [
    # Allows writing logs to Cloud Logging.
    "roles/logging.logWriter",
    # Allows storing objects and creating buckets in Cloud Storage.
    "roles/storage.admin",
    # Allows Cloud Deploy to deploy Cloud Run services.
    "roles/run.developer",
  ]
}

# The trigger of Cloud Build builds. Assumes that source repo is hosted on
# GitHub.
resource "google_cloudbuild_trigger" "main" {
  name            = var.service_name
  service_account = google_service_account.cloudbuild.id

  github {
    owner = var.github_repo_owner
    name  = var.github_repo_name
    push {
      branch = var.branch_filter_regex
    }
  }

  substitutions = {
    _ARTIFACT_REGISTRY_BASE_URL = var.artifact_registry_base_url
    _DELIVERY_PIPELINE_NAME     = var.service_name
    _REGION                     = "${var.gcp_region}"
  }

  filename = "cloudbuild.yaml"
}

resource "google_clouddeploy_target" "target" {
  for_each = local.sorted_stages

  location = var.gcp_region
  name     = "${var.service_name}-${each.value.name}"

  run {
    location = each.value.target_id
  }

  execution_configs {
    usages          = ["RENDER", "DEPLOY"]
    service_account = google_service_account.clouddeploy.email
  }

  require_approval = each.value.requires_approval
}

resource "google_clouddeploy_delivery_pipeline" "main" {
  location = var.gcp_region
  name     = var.service_name

  serial_pipeline {
    dynamic "stages" {
      for_each = local.sorted_stages

      content {
        target_id = "${var.service_name}-${stages.value.name}"
        profiles  = [stages.value.name]
      }
    }
  }
}
