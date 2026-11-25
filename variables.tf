variable "project_id" {
  description = "GCP project ID to deploy into."
  type        = string
}

variable "region" {
  description = "GCP region for all resources."
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = <<-EOT
    Deployment environment. MODIFICATION: this is the core mechanism —
    the Cloud SQL instance below is only provisioned when this is
    "production". In "dev", Terraform plans to create zero SQL instances,
    avoiding the cost of an always-on database for routine testing of the
    rest of the stack. This mirrors the same "gate" pattern used in this
    course's Docker, MLflow, and Airflow labs, expressed here through
    Terraform's `count` instead of a build stage, a registry alias, or a
    DAG branch.
  EOT
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "production"], var.environment)
    error_message = "environment must be either \"dev\" or \"production\"."
  }
}

variable "api_image" {
  description = "Container image for the Cloud Run API service (the 'Site and API' piece)."
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "pipeline_image" {
  description = "Container image for the Cloud Run Job (the 'Pipeline' piece)."
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "db_tier" {
  description = "Cloud SQL machine tier. Only relevant when environment = \"production\"."
  type        = string
  default     = "db-f1-micro"
}

variable "scheduler_cron" {
  description = "Cron schedule for the daily pipeline trigger (default: 02:00 UTC daily, matching Meridian's own daily-loop design)."
  type        = string
  default     = "0 2 * * *"
}