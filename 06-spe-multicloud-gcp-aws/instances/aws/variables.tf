variable "region" {
  description = "AWS region for the SPE infrastructure and AMI lookup."
  type        = string
  default     = "us-east-1"
}

variable "availability_zone" {
  description = "Optional AWS availability zone. Null lets AWS select one in the region."
  type        = string
  default     = null
  nullable    = true
}

variable "spe_id" {
  description = "Name assigned to this SPE and its cloud resources."
  type        = string
  default     = "spe-demo-006-aws"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,38}[a-z0-9]$", var.spe_id))
    error_message = "Use 3-40 lowercase letters, numbers, and hyphens, starting with a letter."
  }
}

variable "heartbeat_interval_seconds" {
  description = "Seconds between heartbeat records. Attached to the instance as a tag and read by the SPE at boot."
  type        = number
  default     = 30

  validation {
    condition     = var.heartbeat_interval_seconds >= 5 && var.heartbeat_interval_seconds <= 3600 && floor(var.heartbeat_interval_seconds) == var.heartbeat_interval_seconds
    error_message = "Use a whole number of seconds between 5 and 3600."
  }
}

variable "vm_size" {
  description = "AWS EC2 instance type. c7i-flex.large provides 2 vCPUs and 4 GiB of memory."
  type        = string
  default     = "c7i-flex.large"
}

variable "disk_size_gb" {
  description = "Final SPE boot-volume capacity in GB."
  type        = number
  default     = 30

  validation {
    condition     = var.disk_size_gb >= 30
    error_message = "The complete SPE needs a boot disk of at least 30 GB."
  }
}

variable "disk_type" {
  description = "AWS EBS volume type, such as gp3 or gp2."
  type        = string
  default     = "gp3"
}

variable "image_family" {
  description = "ImageFamily tag used to find the latest Packer AMI."
  type        = string
  default     = "learn-spe-multicloud"
}

variable "vpc_cidr" {
  description = "Private IPv4 range for the AWS VPC."
  type        = string
  default     = "10.61.0.0/16"
}

variable "network_cidr" {
  description = "Private IPv4 range for the AWS public subnet."
  type        = string
  default     = "10.61.1.0/24"
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
