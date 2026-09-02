packer {
  required_version = ">= 1.14.0"

  required_plugins {
    amazon = {
      version = "~> 1"
      source  = "github.com/hashicorp/amazon"
    }

    googlecompute = {
      version = "~> 1"
      source  = "github.com/hashicorp/googlecompute"
    }
  }
}
