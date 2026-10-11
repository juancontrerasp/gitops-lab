terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Las credenciales llegan por Workload Identity Federation (las deja listas
# la acción google-github-actions/auth). No hay claves en el código.
provider "google" {
  project = var.project_id
  region  = var.region
}

variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "owner" {
  type = string
}

variable "prefix" {
  type    = string
  default = "lab6"
}

module "sitio" {
  source      = "../../modules/static_site"
  project_id  = var.project_id
  region      = var.region
  prefix      = var.prefix
  environment = "prod"
  index_file  = "${path.root}/../../site/index.html"

  labels = {
    environment = "prod"
    owner       = lower(var.owner)
    course      = "pemu-2026"
  }
}

output "site_url" {
  value = module.sitio.site_url
}
