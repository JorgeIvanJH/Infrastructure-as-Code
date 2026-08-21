packer {
  required_plugins {
    docker = {
      version = ">= 1.0.8"
      source  = "github.com/hashicorp/docker"
    }
  }
}

variable "docker_image" {
  description = "Docker image used by the configurable source."
  type        = string
  default     = "ubuntu:24.04"
}

source "docker" "configurable" {
  image  = var.docker_image
  commit = true
}

source "docker" "ubuntu_2404" {
  image  = "ubuntu:24.04"
  commit = true
}

build {
  name = "learn-packer"
  sources = [
    "source.docker.configurable",
    "source.docker.ubuntu_2404",
  ]

  provisioner "shell" {
    inline = [
      "echo 'This file was added by Packer.' > /example.txt",
      "cat /etc/os-release | grep PRETTY_NAME",
    ]
  }

  post-processor "docker-tag" {
    only       = ["docker.configurable"]
    repository = "learn-packer"
    tags       = ["configurable"]
  }

  post-processor "docker-tag" {
    only       = ["docker.ubuntu_2404"]
    repository = "learn-packer"
    tags       = ["ubuntu-24-04"]
  }
}
