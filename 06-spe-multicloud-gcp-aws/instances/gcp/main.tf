provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

data "google_compute_image" "spe" {
  project = var.project_id
  family  = var.image_family
}

resource "google_compute_network" "spe" {
  name                    = "${var.spe_id}-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "spe" {
  name          = "${var.spe_id}-subnet"
  ip_cidr_range = var.network_cidr
  network       = google_compute_network.spe.id
  region        = var.region
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "${var.spe_id}-allow-ssh"
  network = google_compute_network.spe.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = [var.ssh_source_cidr]
  target_tags   = ["${var.spe_id}-ssh"]
}

resource "google_compute_firewall" "allow_rdp" {
  name    = "${var.spe_id}-allow-rdp"
  network = google_compute_network.spe.name

  allow {
    protocol = "tcp"
    ports    = ["3389"]
  }

  source_ranges = [var.rdp_source_cidr]
  target_tags   = ["${var.spe_id}-rdp"]
}

resource "google_compute_instance" "spe" {
  name         = var.spe_id
  machine_type = var.vm_size
  zone         = var.zone
  tags         = ["${var.spe_id}-ssh", "${var.spe_id}-rdp"]

  labels = {
    component  = "spe"
    managed_by = "terraform"
    purpose    = "learning"
  }

  boot_disk {
    auto_delete = true

    initialize_params {
      image = data.google_compute_image.spe.self_link
      size  = var.disk_size_gb
      type  = var.disk_type
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.spe.id

    access_config {}
  }

  # This learning image contains the public half of the local tf-packer key.
  # The spe-* keys are read at boot by spe-identity; the image itself carries
  # no SPE identity.
  metadata = {
    enable-oslogin         = "FALSE"
    spe-id                 = var.spe_id
    spe-heartbeat-interval = tostring(var.heartbeat_interval_seconds)
  }
}
