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

# Find the newest image created by this lesson's Packer build.
data "google_compute_image" "packer" {
  project = var.project
  family  = "learn-spe-monitoring-agent"
}

resource "google_compute_network" "vpc" {
  name                    = "spe-monitoring-agent-network"
  auto_create_subnetworks = true
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "spe-monitoring-agent-allow-ssh"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = [var.ssh_source_cidr]
  target_tags   = ["ssh"]
}

resource "google_compute_firewall" "allow_rdp_from_gateway" {
  name    = "spe-allow-rdp-from-gateway"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["3389"]
  }

  source_ranges = [var.rdp_source_cidr]
  target_tags   = ["rdp"]
}

resource "google_compute_instance" "spe" {
  name         = "spe-demo-001"
  machine_type = "e2-medium"
  tags         = ["ssh", "rdp"]

  labels = {
    component  = "spe"
    managed_by = "terraform"
    purpose    = "learning"
  }

  boot_disk {
    initialize_params {
      image = data.google_compute_image.packer.self_link
      size  = 30
      type  = "pd-standard"
    }
  }

  network_interface {
    network = google_compute_network.vpc.name
    access_config {}
  }

  # This lesson uses the SSH key baked into the image instead of OS Login.
  metadata = {
    enable-oslogin = "FALSE"
  }
}

output "public_ip" {
  description = "Public IPv4 address assigned to the VM."
  value       = google_compute_instance.spe.network_interface[0].access_config[0].nat_ip
}

output "ssh_command" {
  description = "Command that connects with the private half of the baked-in key."
  value       = "ssh -i ../tf-packer terraform@${google_compute_instance.spe.network_interface[0].access_config[0].nat_ip}"
}
