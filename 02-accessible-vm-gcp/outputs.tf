output "public_ip" {
  description = "Public IPv4 address assigned to the VM."
  value       = google_compute_instance.vm_instance.network_interface[0].access_config[0].nat_ip
}

output "ssh_command" {
  description = "gcloud command that connects to the VM."
  value       = "gcloud compute ssh ${google_compute_instance.vm_instance.name} --zone=${var.zone} --project=${var.project}"
}
