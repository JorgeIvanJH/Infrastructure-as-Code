terraform {
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

# A public IP alone is not enough: the VPC firewall must permit SSH traffic.
resource "google_compute_firewall" "allow_ssh" {
  name    = "accessible-vm-allow-ssh"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # Limit SSH exposure to the public IP supplied when Terraform is run.
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

    # An empty access_config requests an ephemeral external IPv4 address.
    access_config {}
  }
}
