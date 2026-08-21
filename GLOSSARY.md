# Simple glossary

## Infrastructure as Code

Infrastructure as Code, or IaC, means describing infrastructure in text files
instead of creating it manually in a web console.

## Desired state

The configuration describes what I want to exist. Terraform compares that
desired state with its saved state and the real cloud resources, then proposes
the changes needed to make them match.

## Provider

A Terraform provider is a plugin that translates Terraform resources into API
calls for a platform such as Google Cloud.

## Resource

A resource block describes one object Terraform should manage, such as a
network, firewall rule, disk, or VM.

## State

Terraform state maps resource addresses in the code to real cloud resource IDs.
Local state is useful for learning but should not be committed. Teams normally
use a protected remote backend with state locking.

## Variable

An input variable lets a value change without rewriting the main
configuration. Terraform and Packer refer to one as **var.name**.

## Output

A Terraform output gives a useful value a clear name, such as a VM public IP or
an SSH command.

## Image

An image is a reusable starting disk for new machines. It contains an operating
system and can also contain installed software and files.

## VM

A virtual machine, or VM, is a running computer created from an image.

## Packer plugin and builder

A Packer plugin adds support for a platform. A builder inside that plugin knows
how to start a temporary machine or container and turn it into an image.

## Packer source

A source block configures one builder: the base image, machine size, location,
connection user, and final image settings.

## Packer build

A build block selects one or more sources and runs provisioners and
post-processors against them.

## Communicator

A communicator is how Packer talks to the temporary build machine. Cloud VM
builders commonly use SSH. The Docker builder uses its Docker communicator.

## Provisioner

A Packer provisioner changes the temporary machine. It can upload a file, run a
shell script, or call a configuration-management tool. Provisioners run in the
order written.

## Post-processor

A post-processor handles the completed artifact. For example, it can tag a
Docker image or push it to a registry.

## Artifact

An artifact is the result of a Packer build. In lesson 3 it is a local Docker
image. In lesson 4 it is a custom Compute Engine image stored in GCP.

## CIDR and /32

CIDR describes an IP range. A value such as 203.0.113.10/32 means exactly one
IPv4 address. The SSH firewall lessons use /32 so they do not open SSH to the
whole internet.
