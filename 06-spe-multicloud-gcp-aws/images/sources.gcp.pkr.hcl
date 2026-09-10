source "googlecompute" "gcp" {
  project_id              = var.gcp_project_id
  zone                    = var.gcp_zone
  machine_type            = var.gcp_build_vm_size
  disk_size               = var.image_disk_size_gb
  disk_type               = var.gcp_image_disk_type
  source_image_family     = "ubuntu-2404-lts-amd64"
  source_image_project_id = ["ubuntu-os-cloud"]
  ssh_username            = "ubuntu"

  # The temporary build VM carries this tag so a firewall rule can admit SSH from
  # the build laptop only. See scripts/image/README.md, "before the first build".
  tags = ["packer-build"]

  image_name        = "${local.image_family}-${local.build_timestamp}"
  image_family      = local.image_family
  image_description = "Ubuntu 24.04 multicloud learning SPE built natively on GCP"
  image_labels = {
    component  = "spe"
    managed_by = "packer"
    purpose    = "learning"
  }
}
