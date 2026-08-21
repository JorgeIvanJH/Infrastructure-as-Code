terraform {
  required_version = ">= 1.0.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "6.8.0"
    }
  }
}

provider "google" {
  project = var.project
  region  = var.region
  zone    = var.zone
}

resource "google_compute_network" "vpc_network" {
  name = "accessible-vm-network"
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "accessible-vm-allow-ssh"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = [var.ssh_source_cidr]
  target_tags   = ["ssh"]
}

resource "google_compute_instance" "vm_instance" {
  name         = "accessible-vm"
  machine_type = "e2-micro"
  tags         = ["ssh"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      type  = "pd-standard"
      size  = 10
    }
  }

  network_interface {
    network = google_compute_network.vpc_network.name
    access_config {}
  }

  labels = {
    managed_by = "terraform"
    lesson     = "02"
  }
}
