terraform {
  backend "gcs" {
    credentials = "~/.gcp/credentials/resume-ryangontarek-com.json"
    bucket      = "resume-ryangontarek-com-terraform"
    prefix      = "terraform/state"
  }
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.27.0"
    }
  }
}

locals {
  name       = "resume-ryangontarek-com"
  project_id = "resume-ryangontarek-com"
  location   = "us-central1"
  zone       = "us-central1-a"
}

provider "google" {
  credentials = file("~/.gcp/credentials/resume-ryangontarek-com.json")
  project     = "resume-ryangontarek-com"
  region      = "us-central1"
}

resource "google_storage_bucket" "backend" {
  # checkov:skip=CKV_GCP_62: I don't want this bucket to log acccess
  project       = local.project_id
  name          = "${local.name}-terraform"
  location      = local.location
  force_destroy = true
  versioning {
    enabled = true
  }
  lifecycle {
    prevent_destroy = true
  }
  uniform_bucket_level_access = true
}

resource "google_storage_bucket" "resume_ryangontarek_com" {
  # checkov:skip=CKV_GCP_62: I don't want this bucket to log acccess
  project       = local.project_id
  name          = local.name
  location      = local.location
  force_destroy = false
  website {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }
  cors {
    origin          = ["*"] # ["http://image-store.com"]
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
  versioning {
    enabled = true
  }
  # disables ACL bucket access and forces all bucket access through IAM
  uniform_bucket_level_access = true
}

resource "google_project_service" "resume_ryangontarek_com" {
  project = local.project_id
  service = "iam.googleapis.com"
}

resource "google_project_iam_custom_role" "resume_ryangontarek_com" {
  role_id     = "resumeRyanGontarekCom"
  title       = "Resume Ryan Gontarek Com"
  description = "Role for public access to resume-ryangontarek-com cloud storage bucket"
  permissions = [
    "storage.objects.get",
    "storage.objects.list"
  ]
}

resource "google_storage_bucket_iam_member" "resume_ryangontarek_com" {
  # checkov:skip=CKV_GCP_28: I want bucket to be anonymously accessible
  bucket = google_storage_bucket.resume_ryangontarek_com.name
  role   = google_project_iam_custom_role.resume_ryangontarek_com.id
  member = "allUsers"
}
