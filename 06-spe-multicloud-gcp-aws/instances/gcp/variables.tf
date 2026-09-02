variable "project_id" {
  description = "Google Cloud project ID."
  type        = string
}

variable "region" {
  description = "GCP region for the SPE network."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone for the SPE VM."
  type        = string
  default     = "us-central1-c"
}

variable "spe_id" {
  description = "Name assigned to this SPE and its cloud resources."
  type        = string
  default     = "spe-demo-006-gcp"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,38}[a-z0-9]$", var.spe_id))
    error_message = "Use 3-40 lowercase letters, numbers, and hyphens, starting with a letter."
  }
}

variable "vm_size" {
  description = "GCP machine type. e2-medium provides 2 vCPUs and 4 GB of memory."
  type        = string
  default     = "e2-medium"
}

variable "disk_size_gb" {
  description = "Final SPE boot-disk capacity in GB."
  type        = number
  default     = 30

  validation {
    condition     = var.disk_size_gb >= 30
    error_message = "The complete SPE needs a boot disk of at least 30 GB."
  }
}

variable "disk_type" {
  description = "GCP boot-disk type, such as pd-standard, pd-balanced, or pd-ssd."
  type        = string
  default     = "pd-standard"
}

variable "image_family" {
  description = "Packer image family selected by Terraform."
  type        = string
  default     = "learn-spe-multicloud"
}

variable "network_cidr" {
  description = "Private IPv4 range for the GCP subnet."
  type        = string
  default     = "10.60.1.0/24"
}

variable "ssh_source_cidr" {
  description = "Administrator public IPv4 address in CIDR notation."
  type        = string

  validation {
    condition = (
      can(cidrhost(var.ssh_source_cidr, 0)) &&
      can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/32$", var.ssh_source_cidr))
    )
    error_message = "Use one public IPv4 address with /32, for example 203.0.113.10/32."
  }
}

variable "rdp_source_cidr" {
  description = "Public IPv4 address of the laptop running Guacamole."
  type        = string

  validation {
    condition = (
      can(cidrhost(var.rdp_source_cidr, 0)) &&
      can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/32$", var.rdp_source_cidr))
    )
    error_message = "Use one public IPv4 address with /32, for example 203.0.113.10/32."
  }
}
