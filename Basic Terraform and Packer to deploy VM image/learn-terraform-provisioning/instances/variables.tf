# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

variable "project" {
  description = "Google Cloud project ID."
  type        = string
  default     = "even-lyceum-505816-g5"
}

variable "region" {
  description = "Google Cloud region in which Terraform deploys the instance."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Google Cloud zone used by both Packer and Terraform."
  type        = string
  default     = "us-central1-c"
}

variable "ssh_source_cidr" {
  description = "Your current public IPv4 address in CIDR notation, for example 203.0.113.10/32."
  type        = string

  validation {
    condition = (
      can(cidrhost(var.ssh_source_cidr, 0)) &&
      can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/32$", var.ssh_source_cidr))
    )
    error_message = "Use one public IPv4 address with a /32 prefix, for example 203.0.113.10/32."
  }
}

