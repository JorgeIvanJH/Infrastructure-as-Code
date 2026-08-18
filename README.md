

# Terraform with GCP following [this guide](https://developer.hashicorp.com/terraform/tutorials/gcp-get-started/infrastructure-as-code)


## Requirements (GCP):

- chocolatey (win)
- terraform CLI 
- gcloud CLI
- GCP project with enabled Google Compute Engine API

## To deploy infrastructure with Terraform:

1. Scope - Identify the infrastructure for your project.
2. Author - Write the configuration for your infrastructure.
3. Initialize - Install the plugins Terraform needs to manage the infrastructure.
4. Plan - Preview the changes Terraform will make to match your configuration.
5. Apply - Make the planned changes.

**Terraform keeps track of your real infrastructure in a state file, which acts as a source of truth for your environment. Terraform uses the state file to determine the changes to make to your infrastructure so that it will match your configuration.**


## 1. Scope

Choosing Cloud Provider and services needed. Here GCP with Google Compute Engines.

## 2. Author (writing the configuration)

The set of files used to describe infrastructure in Terraform is known as a Terraform configuration.

**What is a configuration?** A configuration represents a single project or a single deployment boundary. Whenever you want a set of infrastructure components to be built, updated, and managed together as one unit, you put them into the same folder. That folder is your configuration. A single configuration can have multiple providers (Azure, GCP, AWS, etc), but in this example we have only GCP.

Each Terraform configuration must be in its own working directory. Create a directory for your configuration.

see [this](learn-terraform-gcp/main.tf)


## 3. Initialize


### Terraform block (provider)

The terraform {} block contains Terraform settings, including the required **providers** Terraform will use to provision your infrastructure.

Terraform installs **providers** from the Terraform Registry by default.

source defines the online path to the **provider** to be used; when you write a **provider** source, Terraform looks for a specific three-part format: [hostname]/[namespace]/[type]. "hashicorp/google" is short for registry.terraform.io/hashicorp/google


### Providers (configure the provider)

The provider block configures the specified provider

### Resource (The actual components)

Use resource blocks to define components of your infrastructure, either servers or apps.

Resource blocks have two strings before the block: the resource type and the resource name.

resource type: equivalent to the variable type in variables (e.g. int, string, bool, etc) but here it define the type of component that one would like to build. Find a list of possible resources in [terraform registry](https://registry.terraform.io/) -> Cloud provider (e.g. Google) -> Documentation -> Use the left-hand sidebar to browse categories (Compute, Storage, Networking, etc.)
    e.g:
        google_compute_instance: to create a Virtual Machine (VM)
        google_compute_network: to create Virtual Network (VPC)
        google_storage_bucket: to create  a Cloud Storage Bucket
        google_compute_firewall: to create a Firewall Rule


resource name: a name assigned to the type of component being created, just like one gives a name to a variable (e.g. int count_loops, bool flag_done, string person_name).
    e.g:
        "google_compute_network" "vpc_network": to name a VPC "vpc_network"

Resource blocks contain arguments which you use to configure the resource. Arguments can include things like machine sizes, disk image names, or VPC IDs. The Terraform Registry GCP documentation page documents the required and optional arguments for each GCP resource.

### Authenticate to Google Cloud

Terraform must authenticate to Google Cloud to create infrastructure.

```bash
gcloud auth application-default login
```

### Initialize the directory

For any new configuration you need to initialize the directory with terraform init. This step downloads the providers defined in the configuration.

run 
```bash
terraform init
```
at the level of the configutaion (inside the folder of the configuration where the .tf files are)

- Terraform downloads the google provider and installs it in a hidden subdirectory of your current working directory, named .terraform

- Terraform also creates a lock file named .terraform.lock.hcl, which specifies the exact provider versions used to ensure that every Terraform run is consistent.

e.g:

    Before "terraform init", i had only 1 file:
        - learn-terraform-gcp\main.tf
    
    After that command now i have:
        - learn-terraform-gcp\.terraform.lock.hcl
        - learn-terraform-gcp\.terraform\providers\registry.terraform.io\hashicorp\google\6.8.0\windows_amd64. 



