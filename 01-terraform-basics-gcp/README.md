# 01 - Terraform basics on GCP

## Goal

This first lesson creates:

1. A VPC network.
2. A small Compute Engine VM connected to that network.

The VM receives a public IP, but this lesson does not create an SSH firewall
rule. It teaches Terraform's basic workflow before adding remote access in
lesson 2.

Based on the official
[Terraform GCP get-started tutorials](https://developer.hashicorp.com/terraform/tutorials/gcp-get-started).

## Files

- [main.tf](main.tf) declares the provider, network, and VM.
- [variables.tf](variables.tf) declares changeable inputs.
- [terraform.tfvars.example](terraform.tfvars.example) shows environment values.
- [outputs.tf](outputs.tf) selects useful results.
- **.terraform.lock.hcl** records the exact provider version selected by
  **terraform init**.

Terraform loads all .tf files in this directory as one configuration. File
names help people organize the code; they do not change Terraform behaviour.

## The main blocks

### terraform

The terraform block says which provider plugin this configuration needs.

~~~hcl
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "6.8.0"
    }
  }
}
~~~

The source is short for registry.terraform.io/hashicorp/google.

### provider

The Google provider block says which project, region, and zone receive the API
calls. Values come from variables.

### resource

A resource block has a provider resource type and a local name:

~~~hcl
resource "google_compute_network" "vpc_network" {
  name = "terraform-network"
}
~~~

- **google_compute_network** is the type understood by the Google provider.
- **vpc_network** is the name used inside Terraform.

The VM refers to the network with
**google_compute_network.vpc_network.name**. This also tells Terraform that the
network must exist before the VM.

## Prepare variables

Copy the example:

~~~powershell
Copy-Item terraform.tfvars.example terraform.tfvars
~~~

Edit terraform.tfvars and replace YOUR_PROJECT_ID. Terraform automatically
loads a file named terraform.tfvars.

## Authenticate

~~~powershell
gcloud auth application-default login
~~~

Terraform uses these Application Default Credentials to call Google Cloud.

## Initialize, format, and validate

Run commands from this directory:

~~~powershell
terraform init
terraform fmt
terraform validate
~~~

**terraform init** downloads the provider into .terraform/ and creates or
updates .terraform.lock.hcl.

## Plan and apply

~~~powershell
terraform plan
terraform apply
~~~

A plan summary looks like:

~~~text
Plan: X to add, Y to change, Z to destroy.
~~~

- add means create
- change means update in place
- destroy means delete
- known after apply means the cloud chooses the value during creation

Read the plan before entering yes.

## Configuration, state, and real infrastructure

These are three related things:

- The configuration is what I want.
- The state maps Terraform addresses to real cloud resource IDs.
- GCP contains what actually exists.

Inspect the state with:

~~~powershell
terraform show
terraform state list
terraform output
~~~

The local state may contain sensitive data. Do not commit it. In a team, use a
protected remote backend.

For this lesson, make changes through Terraform. Manual console changes create
drift. Terraform normally detects drift and proposes a way to make the real
infrastructure match the configuration again.

## Try a change

Change the VM tags or machine image, then run:

~~~powershell
terraform plan
~~~

Some changes happen in place. Other changes replace a resource. A plan shows
replacement as destroy and create, so read it carefully.

## Clean up

~~~powershell
terraform destroy
~~~

Terraform removes only resources recorded in this configuration's state.

## What to remember

- A configuration is one working directory.
- Providers translate Terraform into cloud API calls.
- Resources describe managed objects.
- References create relationships and ordering.
- Variables provide inputs.
- Outputs select useful results.
- State connects code to real resource IDs.

Further reading:

- [Build GCP infrastructure](https://developer.hashicorp.com/terraform/tutorials/gcp-get-started/infrastructure-as-code)
- [Change infrastructure](https://developer.hashicorp.com/terraform/tutorials/gcp-get-started/google-cloud-platform-change)
- [Destroy infrastructure](https://developer.hashicorp.com/terraform/tutorials/gcp-get-started/google-cloud-platform-destroy)
- [Input variables](https://developer.hashicorp.com/terraform/tutorials/gcp-get-started/google-cloud-platform-variables)
- [Terraform state](https://developer.hashicorp.com/terraform/language/state/purpose)
- [Google provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
