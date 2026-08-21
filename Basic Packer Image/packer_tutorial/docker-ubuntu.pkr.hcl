packer {
  required_plugins {
    docker = {
      version = ">= 1.0.8"
      source  = "github.com/hashicorp/docker"
    }
  }
}

variable "docker_image" {
  type    = string
  default = "ubuntu:jammy"
}

source "docker" "ubuntu" { # "builder type" "name"
  image  = var.docker_image
  commit = true
}

source "docker" "ubuntu-focal" {
  image  = "ubuntu:focal"
  commit = true
}


build {
  name = "learn-packer"
  sources = [
    "source.docker.ubuntu",
    "source.docker.ubuntu-focal"
  ]

  provisioner "shell" {
    environment_vars = [
      "FOO=hello world",
    ]
    inline = [
      "echo Adding file to Docker Container",
      "echo \"FOO is $FOO\" > example.txt",
    ]
  }

  provisioner "shell" {
    inline = ["echo Running $(cat /etc/os-release | grep VERSION= | sed 's/\"//g' | sed 's/VERSION=//g') Docker image."]
  }

  post-processor "docker-tag" {
    repository = "learn-packer"
    tags       = ["ubuntu-jammy", "packer-rocks"] # Tag "packer-rocks" first assigned to this image
    only       = ["docker.ubuntu"]
  }

  post-processor "docker-tag" {
    repository = "learn-packer"
    tags       = ["ubuntu-focal", "packer-rocks"] # Tag "packer-rocks" is stolen from the previous image and assigned to this image
    only       = ["docker.ubuntu-focal"]
  }

  post-processors {
    post-processor "docker-tag" {
      repository = "jorgejaramilloherrera98795/packertesting"
      tags       = ["0.7"]
    }
    post-processor "docker-push" {}
  }

}



