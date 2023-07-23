variable "gcp_project_id" {
  type        = string
  description = "The ID of the GCP project where this template is to be deployed."
}

variable "gcp_region" {
  type        = string
  description = "The GCP region where this template is to be deployed."
}

variable "enable_apis" {
  type        = bool
  description = "Whether to automatically enable the necessary GCP APIs."
  default     = true
}

variable "service_name" {
  type        = string
  description = "The name of the service deployed by this pipeline."
}

variable "runtime" {
  type        = string
  description = "The runtime of this service (GKE or Cloud Run). Only Cloud Run is supported at this time, so this variable is in fact ignored."

  validation {
    condition     = contains(["gke", "run"], var.runtime)
    error_message = "`runtime` must be one of (`gke`, `run`)."
  }
}

variable "github_repo_owner" {
  type        = string
  description = "The owner of the GitHub repository containing the service source code. E.g., in https://github.com/foo/bar, the owner is 'foo'."
}

variable "github_repo_name" {
  type        = string
  description = "The name of the GitHub repository containing the service source code. E.g., in https://github.com/foo/bar, the repo name is 'bar'."
}

variable "branch_filter_regex" {
  type        = string
  description = "The regular expression to use when filtering repo branches. The build will run only if the branch matches this filter."
  default     = ".*"
}

variable "artifact_registry_base_url" {
  type        = string
  description = "The base URL to the Artifact Registry repository (e.g., https://REGION-docker.pkg.dev/PROJECT/REPO_NAME/)"
}

variable "stages" {
  type = list(object({
    name              = string,
    target_id         = string,
    requires_approval = bool,
  }))
  description = "The sequence of stages that the pipeline will follow. These must be defined in your desired order."
}
