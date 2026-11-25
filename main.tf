# main.tf
#
# MODIFICATION: the original lab provisioned a single generic VM and a
# single GCS bucket with a hardcoded, globally-unique bucket name (a real
# bug — GCS bucket names must be unique across ALL of GCP, so
# "terraform-lab-bucket-unique-12345" would almost certainly already be
# taken, causing `terraform apply` to fail for anyone else who ran it).
#
# This file replaces that generic demo with infrastructure shaped after
# this course's own final project (Meridian), whose own architecture docs
# specify exactly this stack:
#   - Pipeline      -> Cloud Run Jobs
#   - Site and API  -> Cloud Run
#   - Database      -> Cloud SQL (the only always-on piece)
#   - Snapshots     -> GCS
#   - Schedule      -> Cloud Scheduler

# ---------------------------------------------------------------------------
# Enable the APIs this stack needs. The original lab assumed these were
# already enabled manually; declaring them here means `terraform apply`
# works on a completely fresh project with no manual console clicking.
# ---------------------------------------------------------------------------
locals {
  required_apis = [
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "cloudscheduler.googleapis.com",
    "storage.googleapis.com",
    "iam.googleapis.com",
  ]
}

resource "google_project_service" "apis" {
  for_each = toset(local.required_apis)
  project  = var.project_id
  service  = each.value

  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# GCS bucket — "Snapshots, LLM cache" in Meridian's architecture doc.
# MODIFICATION (bug fix): random_id suffix instead of a hardcoded name,
# since GCS bucket names must be globally unique.
# ---------------------------------------------------------------------------
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "google_storage_bucket" "snapshots" {
  name                        = "mlops-lab5-snapshots-${random_id.bucket_suffix.hex}"
  location                    = var.region
  force_destroy               = true
  uniform_bucket_level_access = true

  labels = {
    environment = var.environment
    purpose     = "meridian-snapshots"
  }

  depends_on = [google_project_service.apis]
}

# ---------------------------------------------------------------------------
# Service account the Scheduler uses to authenticate when invoking the
# Cloud Run Job. Least-privilege: only the run.invoker role, only on the
# specific job below.
# ---------------------------------------------------------------------------
resource "google_service_account" "scheduler_invoker" {
  account_id   = "lab5-scheduler-invoker"
  display_name = "Cloud Scheduler invoker for the Meridian-shaped pipeline job"
}

# ---------------------------------------------------------------------------
# Cloud Run — "Site and API" in Meridian's architecture doc.
# ---------------------------------------------------------------------------
resource "google_cloud_run_v2_service" "api" {
  name     = "lab5-api"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    containers {
      image = var.api_image
    }
  }

  depends_on = [google_project_service.apis]
}

# Allow unauthenticated access to the API service, same as the original
# lab's publicly-reachable VM.
resource "google_cloud_run_v2_service_iam_member" "api_public" {
  project  = var.project_id
  location = google_cloud_run_v2_service.api.location
  name     = google_cloud_run_v2_service.api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# ---------------------------------------------------------------------------
# Cloud Run Job — "Pipeline" in Meridian's architecture doc. This is what
# Cloud Scheduler triggers daily, mirroring Meridian's own "02:00 UTC:
# collect -> ... -> publish the run" daily loop.
# ---------------------------------------------------------------------------
resource "google_cloud_run_v2_job" "pipeline" {
  name     = "lab5-pipeline"
  location = var.region

  template {
    template {
      containers {
        image = var.pipeline_image
      }
    }
  }

  depends_on = [google_project_service.apis]
}

resource "google_cloud_run_v2_job_iam_member" "scheduler_can_run" {
  project  = var.project_id
  location = google_cloud_run_v2_job.pipeline.location
  name     = google_cloud_run_v2_job.pipeline.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.scheduler_invoker.email}"
}

# ---------------------------------------------------------------------------
# Cloud Scheduler — triggers the pipeline job on the configured cron
# schedule, authenticating as the dedicated invoker service account via
# OIDC (no shared secrets, no API keys).
# ---------------------------------------------------------------------------
resource "google_cloud_scheduler_job" "daily_pipeline_trigger" {
  name      = "lab5-daily-pipeline-trigger"
  region    = var.region
  schedule  = var.scheduler_cron
  time_zone = "UTC"

  http_target {
    http_method = "POST"
    uri         = "https://${var.region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.project_id}/jobs/${google_cloud_run_v2_job.pipeline.name}:run"

    oauth_token {
      service_account_email = google_service_account.scheduler_invoker.email
    }
  }

  depends_on = [
    google_project_service.apis,
    google_cloud_run_v2_job_iam_member.scheduler_can_run,
  ]
}

# ---------------------------------------------------------------------------
# Cloud SQL — "Database, the only always-on piece" in Meridian's doc.
#
# MODIFICATION (core mechanism): gated by environment via `count`. In
# "dev", count = 0, so Terraform plans to create NO SQL instance at all —
# avoiding real, ongoing cost for routine testing of the rest of the
# stack. In "production", count = 1, and the instance (plus database and
# a randomly-generated user password) is created for real.
# ---------------------------------------------------------------------------
resource "google_sql_database_instance" "db" {
  count            = var.environment == "production" ? 1 : 0
  name             = "lab5-db-${random_id.bucket_suffix.hex}"
  database_version = "POSTGRES_15"
  region           = var.region

  settings {
    tier = var.db_tier
  }

  deletion_protection = false

  depends_on = [google_project_service.apis]
}

resource "google_sql_database" "app_db" {
  count    = var.environment == "production" ? 1 : 0
  name     = "lab5_app"
  instance = google_sql_database_instance.db[0].name
}

resource "random_password" "db_password" {
  count   = var.environment == "production" ? 1 : 0
  length  = 24
  special = true
}

resource "google_sql_user" "app_user" {
  count    = var.environment == "production" ? 1 : 0
  name     = "lab5_app_user"
  instance = google_sql_database_instance.db[0].name
  password = random_password.db_password[0].result
}