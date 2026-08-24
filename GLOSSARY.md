# Simple glossary

This glossary is divided into ideas shared by Terraform and Packer, ideas used
only by Terraform, and ideas used only by Packer.

## Concepts used by both Terraform and Packer

### Infrastructure as Code

Infrastructure as Code, or IaC, means describing infrastructure in text files
instead of creating it manually in a web console.

Think of the code as a recipe. The recipe records what to create, so the same
result can be made again without relying on memory.

### Configuration

A configuration is the group of files that describes what a tool should do.
Terraform reads `.tf` files. Packer reads `.pkr.hcl` files.

The files are like different pages of one instruction book. Their names help
people stay organized, but the tool reads them together.

### HCL

HCL stands for HashiCorp Configuration Language. It is the language used in
the Terraform and Packer files in this repository.

### Variable

An input variable lets a value change without rewriting the main
configuration. Terraform and Packer refer to a variable as `var.name`.

A variable is like a blank space on a form. The form stays the same, but each
person can enter a different project ID, region, or image name.

### Plugin

A plugin adds support for another platform or service. Terraform and Packer do
not need every cloud integration built into their main programs.

Think of a plugin as an adapter. The main tool stays the same, while the
adapter lets it work with GCP, Docker, AWS, or another system.

### Image

An image is a reusable starting disk for new machines. It contains an operating
system and can also contain installed software, users, and files.

An image is like a prepared master copy. Packer prepares the master copy, and
Terraform can ask GCP to create a new VM from it.

### VM

A virtual machine, or VM, is a running computer created from an image.

The image is the prepared master copy; the VM is a working copy that has been
started. Packer uses a temporary VM while building a cloud image. Terraform
creates the final VM that we want to keep and use.

## Concepts used by Terraform

### Desired state

The Terraform configuration describes what I want to exist. Terraform compares
that desired state with its saved state and the real cloud resources, then
proposes the changes needed to make them match.

Think of the configuration as a building plan, the state as Terraform's
notebook, and GCP as the real building. Terraform compares all three before it
suggests any work.

### Provider

A Terraform provider is a plugin that translates Terraform resources into API
calls for a platform such as Google Cloud.

The provider is like an interpreter. Terraform describes what it wants, and
the provider translates that request into the language understood by GCP.

### Resource

A resource block describes one object Terraform should manage, such as a
network, firewall rule, disk, or VM.

Each resource is one item on the infrastructure building plan.

### Data source

A data source reads information that already exists instead of creating a new
object. In lesson 4, Terraform uses a data source to find the newest image in
the Packer image family.

It is like looking up an address in a directory instead of building a new
house.

### State

Terraform state maps resource addresses in the code to real cloud resource IDs.
Local state is useful for learning but should not be committed. Teams normally
use a protected remote backend with state locking.

State is Terraform's notebook. It records which real GCP object belongs to
each resource in the configuration.

### Plan

A Terraform plan is a preview of the changes Terraform proposes. It can show
resources to add, change, replace, or destroy.

A plan is like reviewing a builder's work estimate before giving permission to
start.

### Apply

`terraform apply` performs the approved changes and updates the Terraform
state.

### Destroy

`terraform destroy` removes the resources managed by the current Terraform
configuration and state. It does not remove resources made separately by
Packer or by another Terraform state.

### Output

A Terraform output gives a useful result a clear name, such as a VM public IP,
an SSH command, or an application URL.

### CIDR and /32

CIDR describes an IP range. A value such as `203.0.113.10/32` means exactly one
IPv4 address. The SSH firewall lessons use `/32` so they do not open SSH to the
whole internet.

## Concepts used by Packer

The Packer concepts below fit together like a small assembly line.

### Builder

A builder knows how to start a temporary machine or container and turn it into
an image. Builders are supplied by Packer plugins.

The builder is the main machine on the assembly line. A Docker builder works
with containers; a Google Compute builder works with GCP VMs and images.

### Source

A source block configures one builder. It describes the starting image,
machine size, location, connection user, and final image settings.

The builder is the type of assembly machine. The source contains the settings
for one particular use of that machine.

### Build

A build block selects one or more sources and tells Packer which provisioners
and post-processors to run.

The build is the complete assembly-line instruction: where to start, what work
to perform, and what to do with the finished result.

### Communicator

A communicator is how Packer talks to the temporary build machine. Cloud VM
builders commonly use SSH. The Docker builder uses its Docker communicator.

The communicator is the connection between Packer and the assembly line. It
lets Packer send files and commands to the temporary machine.

### Provisioner

A Packer provisioner changes the temporary machine. It can upload a file, run a
shell script, or call a configuration-management tool. Provisioners run in the
order written.

Provisioners are the workers on the assembly line. Each one performs a task,
such as installing Go, creating a user, or copying an SSH public key.

### Post-processor

A post-processor handles the completed artifact. For example, it can tag a
Docker image or push it to a registry.

It is like the final packaging station that labels or sends away the finished
product.

### Artifact

An artifact is the result of a Packer build. In lesson 3 it is a local Docker
image. In lesson 4 it is a custom Compute Engine image stored in GCP.

The artifact is the finished product that leaves the assembly line.
