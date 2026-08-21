# Learn Terraform and Packer on Google Cloud

This repository is my learning path for Infrastructure as Code (IaC). I keep
the language simple and use small examples that build on each other.

The shortest explanation is:

- **Terraform creates and manages infrastructure.**
- **Packer creates reusable images for machines.**

Terraform can create a VM from a normal public image. Packer becomes useful
when I want that image to already contain users, tools, files, and an
application.

## Learning path

Follow the folders in this order:

| Lesson | What it teaches |
|---|---|
| [01 - Terraform basics on GCP](01-terraform-basics-gcp/) | Providers, resources, variables, outputs, state, plan, apply, change, and destroy. |
| [02 - Accessible VM on GCP](02-accessible-vm-gcp/) | Public IPs, firewall rules, network tags, and SSH with gcloud. |
| [03 - Packer basics](03-packer-basics/) | Templates, sources, builds, provisioners, variables, parallel builds, and post-processors using Docker locally. |
| [04 - Terraform and Packer on GCP](04-terraform-packer-gcp/) | Build a custom GCP image, deploy it with Terraform, connect with SSH, and run a small Go app. |

Use the [glossary](GLOSSARY.md) when a word is new. Each lesson explains only
the new ideas, so the same definitions do not need to be repeated everywhere.

## Requirements

Install:

- [Terraform CLI](https://developer.hashicorp.com/terraform/install)
- [Packer CLI](https://developer.hashicorp.com/packer/install)
- [Google Cloud CLI](https://cloud.google.com/sdk/docs/install)
- [Docker Desktop](https://docs.docker.com/desktop/) for lesson 3
- Git and an SSH client

You also need a Google Cloud project with billing and the Compute Engine API
enabled. Some resources used here can cost money.

## Authenticate to Google Cloud

Run these once on your local computer:

~~~powershell
gcloud auth login
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
~~~

The two login commands serve different purposes:

- **gcloud auth login** authenticates the gcloud command.
- **gcloud auth application-default login** creates Application Default
  Credentials for tools such as Terraform and Packer.

Do not put credentials in Terraform or Packer files.

## The command pattern

Terraform projects normally follow this loop:

~~~powershell
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
terraform destroy
~~~

Packer projects normally follow this loop:

~~~powershell
packer init .
packer fmt .
packer validate .
packer build .
~~~

Formatting and validation do not create cloud resources. Always read a plan or
build configuration before allowing it to create anything.

## Files that belong in Git

Commit:

- Terraform .tf files
- Packer .pkr.hcl files
- scripts and documentation
- .terraform.lock.hcl files

Do not commit:

- .terraform/
- terraform.tfstate or its backups
- private variable files containing account-specific or sensitive values
- private SSH keys

This repository provides .example variable files. Copy them, remove the
.example suffix, and put your own values in the copy.

The lessons pin provider versions so the same exercises stay repeatable. Use
`terraform init -upgrade` when you intentionally want to test newer allowed
provider versions, and review the resulting lock-file change before committing
it.

## Cost and cleanup

A learning session can create several different billable things:

- a VM
- its persistent disk
- an external IPv4 address
- a custom image created by Packer

**terraform destroy** removes only resources managed by that Terraform state.
It does not remove a Packer image. Every lesson has its own cleanup section.

Useful references:

- [Google Cloud Free Tier](https://cloud.google.com/free/docs/free-cloud-features)
- [Google Cloud disk and image pricing](https://cloud.google.com/compute/disks-image-pricing)
- [Google Cloud external IP pricing](https://cloud.google.com/vpc/network-pricing#ipaddress)

## Main sources

These notes started from the official tutorials and then added my own working
GCP exercises:

- [Terraform get started on GCP](https://developer.hashicorp.com/terraform/tutorials/gcp-get-started)
- [Packer Docker tutorials](https://developer.hashicorp.com/packer/tutorials/docker-get-started)
- [Provision infrastructure with Packer](https://developer.hashicorp.com/terraform/tutorials/provision/packer)
- [Packer documentation](https://developer.hashicorp.com/packer/docs)
