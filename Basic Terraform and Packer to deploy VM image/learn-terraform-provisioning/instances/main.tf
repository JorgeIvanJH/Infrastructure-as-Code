# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "6.8.0"
    }
  }

  required_version = ">= 1.0.0"
}

provider "google" {
  project = var.project
  region  = var.region
  zone    = var.zone
}

# Packer puts each timestamped image into this family. The data source selects
# the newest non-deprecated image, so no image ID needs to be copied by hand.
data "google_compute_image" "packer" {
  project = var.project
  family  = "learn-terraform-packer"
}

resource "google_compute_network" "vpc" {
  name = "learn-packer-network"
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "learn-packer-allow-ssh"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = [var.ssh_source_cidr]
  target_tags   = ["ssh"]
}

resource "google_compute_firewall" "allow_web" {
  name    = "learn-packer-allow-web"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80", "8080"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web"]
}

resource "google_compute_instance" "web" {
  name         = "learn-packer"
  machine_type = "e2-micro"
  tags         = ["ssh", "web"]

  boot_disk {
    initialize_params {
      image = data.google_compute_image.packer.self_link
      type  = "pd-standard"
      size  = 30
    }
  }

  network_interface {
    network = google_compute_network.vpc.name

    # Request an ephemeral external IPv4 address for direct SSH access.
    access_config {}
  }
}

output "public_ip" {
  description = "Public IPv4 address assigned to the VM."
  value       = google_compute_instance.web.network_interface[0].access_config[0].nat_ip
}

output "ssh_command" {
  description = "Command for connecting with the private key paired with the public key baked into the image."
  value       = "ssh -i ../tf-packer terraform@${google_compute_instance.web.network_interface[0].access_config[0].nat_ip}"
}
