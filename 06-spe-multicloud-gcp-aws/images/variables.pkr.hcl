variable "gcp_project_id" {
  description = "GCP project where Packer builds and stores the GCP image."
  type        = string
}

variable "gcp_zone" {
  description = "GCP zone for the temporary GCP build VM."
  type        = string
  default     = "us-central1-c"
}

variable "aws_region" {
  description = "AWS region where Packer builds and stores the AMI."
  type        = string
  default     = "us-east-1"
}

variable "gcp_build_vm_size" {
  description = "GCP machine type used only while building the image."
  type        = string
  default     = "e2-medium"
}

variable "aws_build_vm_size" {
  description = "AWS instance type used only while building the AMI."
  type        = string
  default     = "c7i-flex.large"
}

variable "image_disk_size_gb" {
  description = "Boot-disk size used while building both native images."
  type        = number
  default     = 30

  validation {
    condition     = var.image_disk_size_gb >= 30
    error_message = "The complete SPE image needs at least 30 GB."
  }
}

variable "gcp_image_disk_type" {
  description = "GCP disk type used by Packer's temporary VM."
  type        = string
  default     = "pd-standard"
}

variable "aws_image_disk_type" {
  description = "AWS EBS volume type used by Packer's temporary VM."
  type        = string
  default     = "gp3"
}

locals {
  build_timestamp = regex_replace(timestamp(), "[- TZ:]", "")
  image_family    = "learn-spe-multicloud"
}
