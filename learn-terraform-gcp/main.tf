terraform {
  required_providers {
    google = {
      source  = "registry.terraform.io/hashicorp/google" # path to the provider
      version = "6.8.0"                                  # versioning recommended instead of latest to avoid breaking changes
    }
  }
}

provider "google" {
  project = "even-lyceum-505816-g5" # TODO: get from a variable
  region  = "us-central1"
  zone    = "us-central1-c"
}

resource "google_compute_network" "vpc_network" {
  name = "terraform-network"
}

resource "google_compute_instance" "vm_instance" {
  name         = "terraform-instance"
  machine_type = "e2-micro"
  tags         = ["web", "dev"]

  boot_disk {
    initialize_params {
      image = "cos-cloud/cos-stable"
      type  = "pd-standard"
      size  = 10
    }
  }

  network_interface {
    network = google_compute_network.vpc_network.name
    access_config {
    }
  }
}
