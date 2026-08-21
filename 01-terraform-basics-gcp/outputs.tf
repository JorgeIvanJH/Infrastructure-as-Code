output "private_ip" {
  description = "Private IPv4 address inside the VPC."
  value       = google_compute_instance.vm_instance.network_interface[0].network_ip
}

output "public_ip" {
  description = "Ephemeral public IPv4 address. No SSH firewall exists in this lesson."
  value       = google_compute_instance.vm_instance.network_interface[0].access_config[0].nat_ip
}
