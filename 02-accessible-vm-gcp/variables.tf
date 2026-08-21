variable "project" {
  description = "Google Cloud project ID."
  type        = string
}

variable "region" {
  description = "Free-tier-eligible Google Cloud region."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Zone in the selected region."
  type        = string
  default     = "us-central1-c"
}

variable "ssh_source_cidr" {
  description = "Current public IPv4 address in CIDR notation, for example 203.0.113.10/32."
  type        = string

  validation {
    condition = (
      can(cidrhost(var.ssh_source_cidr, 0)) &&
      can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/32$", var.ssh_source_cidr))
    )
    error_message = "Use one IPv4 address with /32, for example 203.0.113.10/32."
  }
}
