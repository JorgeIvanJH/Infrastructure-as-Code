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

# Packer puts every timestamped image in this family. Terraform asks GCP for
# the newest usable image, so no image name needs to be copied by hand.
data "google_compute_image" "packer" {
  project = var.project
  family  = "learn-terraform-packer"
}

resource "google_compute_network" "vpc" {
  name                    = "learn-packer-network"
  auto_create_subnetworks = true
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
    ports    = ["8080"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web"]
}

resource "google_compute_instance" "web" {
  name         = "learn-packer"
  machine_type = "e2-micro"
  tags         = ["ssh", "web"]

  labels = {
    purpose = "learning"
    tool    = "terraform"
  }

  boot_disk {
    initialize_params {
      image = data.google_compute_image.packer.self_link
      size  = 10
      type  = "pd-standard"
    }
  }

  network_interface {
    network = google_compute_network.vpc.name

    # An empty access_config requests an ephemeral public IPv4 address.
    access_config {}
  }

  # This lesson uses the SSH key baked into the image instead of OS Login.
  metadata = {
    enable-oslogin = "FALSE"
  }
}

output "public_ip" {
  description = "Public IPv4 address assigned to the VM."
  value       = google_compute_instance.web.network_interface[0].access_config[0].nat_ip
}

output "ssh_command" {
  description = "Command that connects with the private half of the baked-in key."
  value       = "ssh -i ../tf-packer terraform@${google_compute_instance.web.network_interface[0].access_config[0].nat_ip}"
}

output "app_url" {
  description = "Web address to open after starting the Go application."
  value       = "http://${google_compute_instance.web.network_interface[0].access_config[0].nat_ip}:8080"
}
