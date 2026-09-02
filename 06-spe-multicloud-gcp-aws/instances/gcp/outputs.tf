output "cloud_provider" {
  description = "Cloud selected by this Terraform root."
  value       = "gcp"
}

output "spe_id" {
  description = "Name of the deployed SPE."
  value       = google_compute_instance.spe.name
}

output "image_id" {
  description = "Exact Packer image selected from the image family."
  value       = data.google_compute_image.spe.name
}

output "public_ip" {
  description = "Public IPv4 address assigned to the GCP SPE."
  value       = google_compute_instance.spe.network_interface[0].access_config[0].nat_ip
}

output "private_ip" {
  description = "Private IPv4 address assigned to the GCP SPE."
  value       = google_compute_instance.spe.network_interface[0].network_ip
}

output "ssh_command" {
  description = "Command to administer the GCP SPE from this directory."
  value       = "ssh -i ../../tf-packer terraform@${google_compute_instance.spe.network_interface[0].access_config[0].nat_ip}"
}

output "rdp_address" {
  description = "Address and port to place in the Guacamole connection."
  value       = "${google_compute_instance.spe.network_interface[0].access_config[0].nat_ip}:3389"
}
