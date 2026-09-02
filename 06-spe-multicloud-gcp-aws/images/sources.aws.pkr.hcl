source "amazon-ebs" "aws" {
  region                      = var.aws_region
  instance_type               = var.aws_build_vm_size
  associate_public_ip_address = true
  ssh_username                = "ubuntu"

  # Restrict Packer's temporary SSH rule to the computer running this build.
  temporary_security_group_source_public_ip = true

  source_ami_filter {
    filters = {
      architecture        = "x86_64"
      name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["099720109477"]
  }

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = var.image_disk_size_gb
    volume_type           = var.aws_image_disk_type
    delete_on_termination = true
    encrypted             = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  ami_name        = "${local.image_family}-${local.build_timestamp}"
  ami_description = "Ubuntu 24.04 multicloud learning SPE built natively on AWS"
  imds_support    = "v2.0"

  run_tags = {
    Component = "spe-image-build"
    ManagedBy = "packer"
    Purpose   = "learning"
  }

  tags = {
    Name        = "${local.image_family}-${local.build_timestamp}"
    ImageFamily = local.image_family
    Component   = "spe"
    ManagedBy   = "packer"
    Purpose     = "learning"
  }

  snapshot_tags = {
    Name        = "${local.image_family}-${local.build_timestamp}"
    ImageFamily = local.image_family
    ManagedBy   = "packer"
    Purpose     = "learning"
  }
}
