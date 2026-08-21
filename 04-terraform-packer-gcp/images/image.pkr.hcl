packer {
  required_plugins {
    googlecompute = {
      version = "~> 1"
      source  = "github.com/hashicorp/googlecompute"
    }
  }
}

variable "project_id" {
  description = "GCP project where Packer builds and stores the image."
  type        = string
}

variable "zone" {
  description = "GCP zone for Packer's temporary build VM."
  type        = string
  default     = "us-central1-c"
}

locals {
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")
}

source "googlecompute" "webapp" {
  project_id              = var.project_id
  zone                    = var.zone
  machine_type            = "e2-micro"
  disk_size               = 10
  disk_type               = "pd-standard"
  source_image_family     = "ubuntu-2404-lts-amd64"
  source_image_project_id = ["ubuntu-os-cloud"]
  ssh_username            = "ubuntu"

  image_name        = "learn-terraform-packer-${local.timestamp}"
  image_family      = "learn-terraform-packer"
  image_description = "Ubuntu 24.04 image prepared for the Terraform lesson"
  image_labels = {
    purpose = "learning"
    tool    = "packer"
  }
}

build {
  sources = ["source.googlecompute.webapp"]

  provisioner "file" {
    source      = "../tf-packer.pub"
    destination = "/tmp/tf-packer.pub"
  }

  provisioner "shell" {
    script = "../scripts/setup.sh"
  }
}
