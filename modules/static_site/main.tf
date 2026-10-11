locals {
  bucket_name = "${var.prefix}-${var.environment}-${random_string.suffix.result}"
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "google_storage_bucket" "site" {
  project                     = var.project_id
  name                        = local.bucket_name
  location                    = var.region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  force_destroy               = true
  labels                      = var.labels

  website {
    main_page_suffix = "index.html"
  }
}

# Un sitio estático en Cloud Storage debe ser legible por cualquiera.
resource "google_storage_bucket_iam_member" "public_read" {
  bucket = google_storage_bucket.site.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

resource "google_storage_bucket_object" "index" {
  bucket        = google_storage_bucket.site.name
  name          = "index.html"
  source        = var.index_file
  content_type  = "text/html"
  cache_control = "no-cache"

  depends_on = [google_storage_bucket_iam_member.public_read]
}
