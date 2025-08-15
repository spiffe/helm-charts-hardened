# Cloud SQL Proxy with GCP IAM Authentication

Use SPIRE Server with Google Cloud SQL using IAM authentication instead of passwords.

## Setup

### 1. Create Infrastructure

**Prerequisites:**
- GKE cluster with Workload Identity enabled
- Terraform configured with GCP provider

Use Terraform to create the database, service account, and Workload Identity:

```bash
# Edit main.tf and replace placeholders:
# - YOUR_PROJECT_ID with your GCP project ID
# - YOUR_REGION with your preferred region (e.g., us-central1)

terraform init
terraform apply
```

**Note:** This creates:
- Service account with Cloud SQL Client and Instance User roles
- Cloud SQL instance with IAM authentication enabled
- Kubernetes service account with Workload Identity annotation
- IAM binding for Workload Identity

### 2. Deploy

Edit `values.yaml` with your project details, then:

```bash
helm upgrade --install -n spire spire spire \
    --repo https://spiffe.github.io/helm-charts-hardened/ \
    -f values.yaml
```

## How It Works

1. Cloud SQL Proxy runs as an init container with `restartPolicy: Always`
2. Proxy connects to your database using IAM authentication
3. SPIRE connects to `127.0.0.1:3306` through the proxy
4. No passwords needed - everything uses IAM authentication 