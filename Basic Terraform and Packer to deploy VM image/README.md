Packer vs Ansible in 1 sentence: Packer creates golden image to setup VMs from build, Ansible configures VMs running already, so use packer if you dont mind deleting and recreating instances, and use ansible to fix/patch existing VMs.


# Provision infrastructure with Packer following [this guide](https://developer.hashicorp.com/terraform/tutorials/provision/packer)


Terraform configuration for a compute instance can use a Packer image to provision your instance without manual configuration.

In this tutorial, you will create a Packer image with a user group, a new user with authorized SSH keys, and a Go web app. Then, you will deploy this image using Terraform. Finally, you will access the instance via SSH to deploy the Go web app.


cloned: git clone -b packer https://github.com/hashicorp-education/learn-terraform-provisioning

From this directory, create the local SSH key in the cloned
`learn-terraform-provisioning` repository:

```powershell
ssh-keygen -t rsa -b 4096 -f ".\learn-terraform-provisioning\tf-packer"
```

This creates the following files on your Windows host:

- `learn-terraform-provisioning\tf-packer` — the private key; keep it local and
  never commit it to Git.
- `learn-terraform-provisioning\tf-packer.pub` — the public key Packer copies
  into the image.

The public key should not be in a local `tmp` directory. During the build, the
file provisioner in `images\image.pkr.hcl` copies the host file
`tf-packer.pub` to `/tmp/tf-packer.pub` inside Packer's temporary Linux build
instance. The `scripts\setup.sh` script then installs it as
`/home/terraform/.ssh/authorized_keys`.
