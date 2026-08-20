## Requirements (GCP):

- chocolatey (win)
- [terraform CLI ](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)
- [packer CLI](https://developer.hashicorp.com/packer/tutorials/docker-get-started/get-started-install-cli)
- gcloud CLI
- GCP project with enabled Google Compute Engine API

Here I am compiling my own learning process of Infrastructure as Code (IaC). I created a folder for each learning path, in the following order:

1. [Basic GCP terraform config](<Basic GCP terraform config>) for a VPC and a VM running on it using Google Cloud Platform. It's just me following the [get started tutorial](https://developer.hashicorp.com/terraform/tutorials/gcp-get-started)
2. [My first accessible VM](<My first accessible VM>) my own exercise to create a first VM that i can actually access because it autoconfigures firewall to allow me to.
3. [Basic Packer Image](<Basic Packer Image>) following the [intro tutorial](https://developer.hashicorp.com/packer/tutorials/docker-get-started/docker-get-started-build-image) building my first image. Here we just build a docker container.
4. [Basic Terraform and Packer to deploy VM image](<Basic Terraform and Packer to deploy VM image>) Also follows a [tutorial](https://developer.hashicorp.com/terraform/tutorials/provision/packer), to create a packer image that automatically creates user group, user with ssh keys, and a web app. This tutorial is originally designed for AWS but I implement it for GCP here.