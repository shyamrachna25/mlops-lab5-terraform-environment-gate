output "api_url" {
  description = "Public URL of the Cloud Run API service."
  value       = google_cloud_run_v2_service.api.uri
}

output "pipeline_job_name" {
  description = "Name of the Cloud Run Job that Scheduler triggers daily."
  value       = google_cloud_run_v2_job.pipeline.name
}

output "scheduler_job_name" {
  description = "Name of the Cloud Scheduler job driving the daily pipeline run."
  value       = google_cloud_scheduler_job.daily_pipeline_trigger.name
}

output "snapshots_bucket" {
  description = "GCS bucket used for snapshots / cache storage."
  value       = google_storage_bucket.snapshots.name
}

output "sql_instance_connection_name" {
  description = "Cloud SQL connection name. Empty string in \"dev\" (count = 0, no instance provisioned)."
  value = var.environment == "production" ? google_sql_database_instance.db[0].connection_name : "(not provisioned in dev, see environment variable)"
}
