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

source "googlecompute" "spe" {
  project_id              = var.project_id
  zone                    = var.zone
  machine_type            = "e2-medium"
  disk_size               = 30
  disk_type               = "pd-standard"
  source_image_family     = "ubuntu-2404-lts-amd64"
  source_image_project_id = ["ubuntu-os-cloud"]
  ssh_username            = "ubuntu"

  image_name        = "learn-spe-monitoring-agent-${local.timestamp}"
  image_family      = "learn-spe-monitoring-agent"
  image_description = "Ubuntu 24.04 SPE image with monitoring, XFCE, JupyterLab, R, and RStudio"
  image_labels = {
    component = "spe"
    purpose   = "learning"
    tool      = "packer"
  }
}

build {
  sources = ["source.googlecompute.spe"]

  provisioner "file" {
    source      = "../tf-packer.pub"
    destination = "/tmp/tf-packer.pub"
  }

  provisioner "file" {
    source      = "../files/spe-monitoring-agent.py"
    destination = "/tmp/spe-monitoring-agent.py"
  }

  provisioner "file" {
    source      = "../files/spe-monitoring-agent.service"
    destination = "/tmp/spe-monitoring-agent.service"
  }

  provisioner "file" {
    source      = "../environments/python/requirements.txt"
    destination = "/tmp/python-requirements.txt"
  }

  provisioner "file" {
    source      = "../environments/r/requirements.R"
    destination = "/tmp/r-requirements.R"
  }

  provisioner "file" {
    source      = "../data/hepatitis.csv"
    destination = "/tmp/hepatitis.csv"
  }

  provisioner "file" {
    source      = "../examples/python/read-hepatitis.ipynb"
    destination = "/tmp/read-hepatitis.ipynb"
  }

  provisioner "file" {
    source      = "../examples/r/read-hepatitis.R"
    destination = "/tmp/read-hepatitis.R"
  }

  provisioner "file" {
    source      = "../examples/r/spe-data-lab.Rproj"
    destination = "/tmp/spe-data-lab.Rproj"
  }

  provisioner "file" {
    source      = "../files/spe-jupyter"
    destination = "/tmp/spe-jupyter"
  }

  provisioner "file" {
    source      = "../files/spe-jupyter.desktop"
    destination = "/tmp/spe-jupyter.desktop"
  }

  provisioner "file" {
    source      = "../files/spe-rstudio.desktop"
    destination = "/tmp/spe-rstudio.desktop"
  }

  provisioner "shell" {
    script = "../scripts/setup.sh"
  }

  provisioner "shell" {
    script = "../scripts/setup-data-tools.sh"
  }
}
