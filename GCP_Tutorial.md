

# Terraform Build with GCP following [this guide](https://developer.hashicorp.com/terraform/tutorials/gcp-get-started/infrastructure-as-code)


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

## 4. Plan (syntax verification)

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


### Format and validate the configuration

The 
```bash
terraform fmt
```
command automatically updates configurations in the current directory for readability and consistency.

You can also make sure your configuration is syntactically valid and internally consistent by using the command:

```bash
terraform validate
```

# 5. Apply

## Create infrastructure

Apply the configuration now with the command:

```bash
terraform apply
```

That command will show something like:

```
Terraform will perform the following actions:

  # google_compute_network.vpc_network will be created
  + resource "google_compute_network" "vpc_network" {
      + auto_create_subnetworks                   = true
      + delete_default_routes_on_create           = false
      + gateway_ipv4                              = (known after apply)
      + id                                        = (known after apply)
      + internal_ipv6_range                       = (known after apply)
      + mtu                                       = (known after apply)
      + name                                      = "terraform-network"
      + network_firewall_policy_enforcement_order = "AFTER_CLASSIC_FIREWALL"
      + numeric_id                                = (known after apply)
      + project                                   = (known after apply)
      + routing_mode                              = (known after apply)
      + self_link                                 = (known after apply)
    }

Plan: 1 to add, 0 to change, 0 to destroy.

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value:

```

This output shows the execution plan, describing which actions Terraform will take in order to create infrastructure to match the configuration.

When the value displayed is (known after apply), it means that the value will not be known until the resource is created.

**Understanding the Three Summary Numbers**

The summary always uses the exact format: Plan: X to add, Y to change, Z to destroy.

- 1 to add: Terraform will create 1 new item from scratch.
- 0 to change: Terraform will update 0 existing items in place (such as modifying a setting on a server that already exists).
- 0 to destroy: Terraform will delete 0 items.

Only by entering "yes" the whole plan will execute. feel free to cancel by typing anything else if you see any risky action (e.g. deleting something (-), or modification of an existing thing that is not supposed to be modified )

after hitting yes and waiting until it finishes, you will see in GCP the VPC created

**Important: DO NOT DELETE VIA WEB CONSOLE. If you delete it manually in the browser, Terraform's local state file will get confused and break. You would do that by running "terraform destroy" in the same directory, but that goes later.** 

You can add **labels** to the configuration to identify which components were created using terraform from the web console.

e.g.

    resource "google_compute_network" "vpc_network" {
    name = "terraform-network"

    # THIS ADDS A VISIBLE IDENTIFIER IN THE WEB CONSOLE
    labels = {
        managed_by = "terraform"
        project    = "tutorial"
    }
    }

## Inspect State

When you applied your configuration, Terraform wrote data into a file called "terraform.tfstate". Terraform stores the IDs and properties of the resources it manages in this file, so that it can update or destroy those resources going forward.

**The Terraform state file is the only way Terraform can track which resources it manages, and often contains sensitive information, so you must store your state file securely and distribute it only to trusted team members who need to manage your infrastructure.**


Inspect the current state using 

```bash
terraform show
```

# Terraform Change with GCP following [this guide](https://developer.hashicorp.com/terraform/tutorials/gcp-get-started/google-cloud-platform-change)

After creating an infrastructure, here we learn how to modify it. Terraform helps tracking evolution of infrastructure.

When you update Terraform configurations, Terraform builds an execution plan that only modifies what is necessary to reach your desired state.

When using Terraform in production, we recommend that you use a version control system to manage your configuration files, and store your state in a remote backend

## Create a new resource

You can create new resources by adding them to your Terraform configuration and running "terraform apply" to provision them.

Note that in [main.tf](learn-terraform-gcp\main.tf) we added a new resource which is a VM called "vm_instance" ("google_compute_instance" "vm_instance"), which uses the previously created VPC network which we called "vpc_network". The presence of the "access_config" block, even without any arguments, gives the VM an external IP address, making it accessible over the internet

## Modify Configuration

Terraform can also make changes to existing resources.

in our example we added "tags = ["web", "dev"]" to our "vm_instance" VM resource. After that we hit

```bash
terraform apply
```

## Introduce destructive changes

A destructive change is a change that requires the provider to replace the existing resource rather than updating it. Changing the disk image of your instance is one example of a destructive change.

in this example we changed the image on the VM, then we run again

```bash
terraform apply
```

Now it will generate a ".tfstate.backup" file that is an exact snapshot of your previous, working state file before you made the VM image change. **NOTE: Protect this file with the same security as .tfstate file, as it contains sensitive information**