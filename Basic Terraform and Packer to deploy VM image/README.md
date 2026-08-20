Packer vs Ansible in 1 sentence: Packer creates golden image to setup VMs from build, Ansible configures VMs running already, so use packer if you dont mind deleting and recreating instances, and use ansible to fix/patch existing VMs.


# Provision infrastructure with Packer following [this guide](https://developer.hashicorp.com/terraform/tutorials/provision/packer)


Terraform configuration for a compute instance can use a Packer image to provision your instance without manual configuration.

In this tutorial, you will create a Packer image with a user group, a new user with authorized SSH keys, and a Go web app. Then, you will deploy this image using Terraform. Finally, you will access the instance via SSH to deploy the Go web app.


