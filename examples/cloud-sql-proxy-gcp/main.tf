# Create service account for SPIRE
resource "google_service_account" "spire" {
  account_id   = "sa-spire"
  display_name = "SPIRE Server Service Account"
  project      = "YOUR_PROJECT_ID"
}

# Grant Cloud SQL Client role
resource "google_project_iam_member" "cloudsql_client" {
  project = "YOUR_PROJECT_ID"
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.spire.email}"
}

# Grant Cloud SQL Instance User role for IAM authentication
resource "google_project_iam_member" "cloudsql_instance_user" {
  project = "YOUR_PROJECT_ID"
  role    = "roles/cloudsql.instanceUser"
  member  = "serviceAccount:${google_service_account.spire.email}"
}

# Create Cloud SQL database instance
resource "google_sql_database_instance" "instance" {
  name             = "spire-db"
  region           = "YOUR_REGION"
  database_version = "MYSQL_8_0"
  project          = "YOUR_PROJECT_ID"
  
  settings {
    tier = "db-f1-micro"
    database_flags {
      name  = "cloudsql_iam_authentication"
      value = "on"
    }
  }

  deletion_protection = true
}

# Create database
resource "google_sql_database" "database" {
  name     = "spire"
  instance = google_sql_database_instance.instance.name
  project  = "YOUR_PROJECT_ID"
}

# Create IAM user for the service account
resource "google_sql_user" "iam_service_account_user" {
  name     = google_service_account.spire.email
  instance = google_sql_database_instance.instance.name
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
  project  = "YOUR_PROJECT_ID"
}

# Create Kubernetes service account
resource "kubernetes_service_account" "spire" {
  metadata {
    name      = "sa-spire"
    namespace = "spire"
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.spire.email
    }
  }
}

# Set up Workload Identity binding
resource "google_service_account_iam_member" "workload_identity_user" {
  service_account_id = google_service_account.spire.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:YOUR_PROJECT_ID.svc.id.goog[spire/sa-spire]"
} 