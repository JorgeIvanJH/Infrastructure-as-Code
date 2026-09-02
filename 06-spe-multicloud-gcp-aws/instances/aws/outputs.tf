output "cloud_provider" {
  description = "Cloud selected by this Terraform root."
  value       = "aws"
}

output "spe_id" {
  description = "Name assigned to the deployed SPE."
  value       = aws_instance.spe.tags["Name"]
}

output "image_id" {
  description = "Exact Packer AMI selected by Terraform."
  value       = data.aws_ami.spe.id
}

output "public_ip" {
  description = "Public IPv4 address assigned to the AWS SPE."
  value       = aws_instance.spe.public_ip
}

output "private_ip" {
  description = "Private IPv4 address assigned to the AWS SPE."
  value       = aws_instance.spe.private_ip
}

output "ssh_command" {
  description = "Command to administer the AWS SPE from this directory."
  value       = "ssh -i ../../tf-packer terraform@${aws_instance.spe.public_ip}"
}

output "rdp_address" {
  description = "Address and port to place in the Guacamole connection."
  value       = "${aws_instance.spe.public_ip}:3389"
}
