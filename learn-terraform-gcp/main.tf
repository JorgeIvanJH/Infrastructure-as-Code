terraform {
  required_providers {
    google = {
      source = "registry.terraform.io/hashicorp/google" # path to the provider
      version = "6.8.0" # versioning recommended instead of latest to avoid breaking changes
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
