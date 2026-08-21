# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

packer {
  required_plugins {
    googlecompute = {
      version = "~> 1"
      source  = "github.com/hashicorp/googlecompute"
    }
  }
}

variable "project_id" {
  type    = string
  default = "even-lyceum-505816-g5"
}

variable "zone" {
  type    = string
  default = "us-central1-c"
}

locals {
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")
}

source "googlecompute" "example" {
  project_id              = var.project_id
  zone                    = var.zone
  machine_type            = "e2-micro"
  source_image_family     = "ubuntu-2204-lts"
  source_image_project_id = ["ubuntu-os-cloud"]
  ssh_username            = "ubuntu"

  image_name        = "learn-terraform-packer-${local.timestamp}"
  image_family      = "learn-terraform-packer"
  image_description = "Ubuntu 22.04 image provisioned by Packer"
}

build {
  sources = ["source.googlecompute.example"]

  provisioner "file" {
    source      = "../tf-packer.pub"
    destination = "/tmp/tf-packer.pub"
  }

  provisioner "shell" {
    script = "../scripts/setup.sh"
  }
}
