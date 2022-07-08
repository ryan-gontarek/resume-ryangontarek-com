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
    aws = {
      source  = "hashicorp/aws"
      version = "4.21.0"
    }
  }
}

provider "google" {
  credentials = file("~/.gcp/credentials/resume-ryangontarek-com.json")
  project     = "resume-ryangontarek-com"
  region      = "us-central1"
}

provider "aws" {
  profile = "rgontarek"
  region  = "us-east-1"
}

locals {
  name        = "resume-ryangontarek-com"
  project_id  = "resume-ryangontarek-com"
  root_domain = "ryangontarek.com"
  sub_domain  = "resume.ryangontarek.com"
  location    = "us-central1"
  zone        = "us-central1-a"
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


################################################################
################# Cloud Storage Website ########################
################################################################
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
    origin          = ["https://resume.ryangontarek.com"]
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

resource "google_project_service" "resume_ryangontarek_com_iam" {
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

################################################################
##################### Load Balancer ############################
################################################################
data "aws_route53_zone" "ryangontarek_com" {
  name = local.root_domain
}

resource "aws_route53_record" "resume_ryangontarek_com_compute" {
  # checkov:skip=CKV2_AWS_23: this resource should have an attached record
  zone_id = data.aws_route53_zone.ryangontarek_com.zone_id
  name    = local.sub_domain
  type    = "A"
  ttl     = "300"
  records = [google_compute_global_address.resume_ryangontarek_com.address]
}

resource "google_project_service" "resume_ryangontarek_com_compute" {
  project = local.project_id
  service = "compute.googleapis.com"
}

resource "google_project_service" "resume_ryangontarek_com_dns" {
  project = local.project_id
  service = "dns.googleapis.com"
}

resource "google_compute_global_address" "resume_ryangontarek_com" {
  name         = local.name
  address_type = "EXTERNAL"
}

resource "google_compute_global_forwarding_rule" "resume_ryangontarek_com" {
  name                  = local.name
  load_balancing_scheme = "EXTERNAL"
  port_range            = "443"
  ip_address            = google_compute_global_address.resume_ryangontarek_com.id
  target                = google_compute_target_https_proxy.resume_ryangontarek_com.id
}

resource "google_compute_target_https_proxy" "resume_ryangontarek_com" {
  name             = local.name
  ssl_certificates = [google_compute_managed_ssl_certificate.resume_ryangontarek_com.id]
  url_map          = google_compute_url_map.resume_ryangontarek_com.id
}

resource "google_compute_managed_ssl_certificate" "resume_ryangontarek_com" {
  name = local.name
  managed {
    domains = [local.sub_domain]
  }
}

resource "google_compute_url_map" "resume_ryangontarek_com" {
  name            = local.name
  description     = "URL map from ingress to backend website bucket"
  default_service = google_compute_backend_bucket.resume_ryangontarek_com.id
  host_rule {
    hosts        = [local.sub_domain]
    path_matcher = "allpaths"
  }
  path_matcher {
    name            = "allpaths"
    default_service = google_compute_backend_bucket.resume_ryangontarek_com.id

    path_rule {
      paths   = ["/*"]
      service = google_compute_backend_bucket.resume_ryangontarek_com.id
    }
  }
}

resource "google_compute_global_forwarding_rule" "resume_ryangontarek_com_http_redirect" {
  name       = "${local.name}-http-redirect"
  ip_address = google_compute_global_address.resume_ryangontarek_com.address
  target     = google_compute_target_http_proxy.resume_ryangontarek_com_http_redirect.self_link
  port_range = "80"
}

resource "google_compute_target_http_proxy" "resume_ryangontarek_com_http_redirect" {
  name    = "${local.name}-http-redirect"
  url_map = google_compute_url_map.resume_ryangontarek_com_http_redirect.self_link
}

resource "google_compute_url_map" "resume_ryangontarek_com_http_redirect" {
  name = "${local.name}-http-redirect"
  default_url_redirect {
    strip_query    = false
    https_redirect = true
  }
}

resource "google_compute_backend_bucket" "resume_ryangontarek_com" {
  name        = local.name
  description = "Contains a beautiful resume"
  bucket_name = google_storage_bucket.resume_ryangontarek_com.name
  enable_cdn  = true
  cdn_policy {
    cache_mode = "CACHE_ALL_STATIC"
  }
}

################################################################
###################### Cloud Build #############################
################################################################

resource "google_project_service" "resume_ryangontarek_com_cloudbuild" {
  project = local.project_id
  service = "cloudbuild.googleapis.com"
}

resource "google_cloudbuild_trigger" "resume_ryangontarek_com" {
  included_files = ["./code/**"] # anytime a file under ./code changes, trigger cloud build
  service_account = google_service_account.resume_ryangontarek_com_cloudbuild.id
  github {
    name  = local.name
    owner = "ryan-gontarek"
    push {
      branch       = "main"
      invert_regex = false
    }
  }
  build {
    options {
      logging = "CLOUD_LOGGING_ONLY"
    }
    step {
      name = "gcr.io/cloud-builders/gsutil"
      args = ["rsync", "-r", "./code/", "gs://resume-ryangontarek-com/"]
    }
    step {
      name = "gcr.io/cloud-builders/gcloud"
      args = ["compute", "url-maps", "invalidate-cdn-cache", "resume-ryangontarek-com", "--path", "/*", "--async"]
    }
  }
}

resource "google_service_account" "resume_ryangontarek_com_cloudbuild" {
  account_id = "resume-ryangontarek-com"
}

resource "google_project_iam_member" "resume_ryangontarek_com_cloudbuild" {
  project = local.project_id
  role    = google_project_iam_custom_role.resume_ryangontarek_com_cloudbuild.id
  member  = "serviceAccount:${google_service_account.resume_ryangontarek_com_cloudbuild.email}"
}

resource "google_project_iam_custom_role" "resume_ryangontarek_com_cloudbuild" {
  role_id     = "resumeRyanGontarekComCloudBuild"
  title       = "Resume Ryan Gontarek Com Cloud Build"
  description = "Role for cloud build to invalidate load balancer cache and upload files to s3"
  permissions = [
    "logging.logEntries.create",
    "storage.objects.list",
    "storage.objects.get",
    "orgpolicy.policy.get",
    "resourcemanager.projects.get",
    # "resourcemanager.projects.list",
    "storage.multipartUploads.abort",
    "storage.multipartUploads.create",
    "storage.multipartUploads.listParts",
    "storage.objects.create",
    "storage.objects.delete",
    "compute.urlMaps.invalidateCache"
  ]
}
