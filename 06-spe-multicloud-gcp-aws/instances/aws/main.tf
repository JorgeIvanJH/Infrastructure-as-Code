provider "aws" {
  region = var.region
}

data "aws_ami" "spe" {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "name"
    values = ["${var.image_family}-*"]
  }

  filter {
    name   = "tag:ImageFamily"
    values = [var.image_family]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_vpc" "spe" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name      = "${var.spe_id}-vpc"
    ManagedBy = "terraform"
    Purpose   = "learning"
  }
}

resource "aws_internet_gateway" "spe" {
  vpc_id = aws_vpc.spe.id

  tags = {
    Name      = "${var.spe_id}-internet-gateway"
    ManagedBy = "terraform"
  }
}

resource "aws_subnet" "spe" {
  vpc_id                  = aws_vpc.spe.id
  cidr_block              = var.network_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name      = "${var.spe_id}-public-subnet"
    ManagedBy = "terraform"
  }
}

resource "aws_route_table" "spe" {
  vpc_id = aws_vpc.spe.id

  tags = {
    Name      = "${var.spe_id}-public-routes"
    ManagedBy = "terraform"
  }
}

resource "aws_route" "internet" {
  route_table_id         = aws_route_table.spe.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.spe.id
}

resource "aws_route_table_association" "spe" {
  subnet_id      = aws_subnet.spe.id
  route_table_id = aws_route_table.spe.id
}

resource "aws_security_group" "spe" {
  name        = "${var.spe_id}-security-group"
  description = "Restricted SSH and RDP access to the learning SPE"
  vpc_id      = aws_vpc.spe.id

  tags = {
    Name      = "${var.spe_id}-security-group"
    ManagedBy = "terraform"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.spe.id
  description       = "SSH from the administrator"
  cidr_ipv4         = var.ssh_source_cidr
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "rdp" {
  security_group_id = aws_security_group.spe.id
  description       = "RDP from the Guacamole gateway"
  cidr_ipv4         = var.rdp_source_cidr
  from_port         = 3389
  ip_protocol       = "tcp"
  to_port           = 3389
}

resource "aws_vpc_security_group_egress_rule" "internet" {
  security_group_id = aws_security_group.spe.id
  description       = "General outbound access; spe-internet controls it inside the guest"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_instance" "spe" {
  ami                         = data.aws_ami.spe.id
  instance_type               = var.vm_size
  subnet_id                   = aws_subnet.spe.id
  vpc_security_group_ids      = [aws_security_group.spe.id]
  associate_public_ip_address = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    delete_on_termination = true
    encrypted             = true
    volume_size           = var.disk_size_gb
    volume_type           = var.disk_type

    tags = {
      Name      = "${var.spe_id}-root"
      ManagedBy = "terraform"
    }
  }

  tags = {
    Name      = var.spe_id
    Component = "spe"
    ManagedBy = "terraform"
    Purpose   = "learning"
  }

  depends_on = [aws_route.internet, aws_route_table_association.spe]
}
