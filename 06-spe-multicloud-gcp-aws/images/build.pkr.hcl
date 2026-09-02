build {
  name = "spe"

  # These sources produce two native cloud images from one provisioning recipe.
  # Use Packer's -only option when I want to build just one cloud.
  sources = [
    "source.amazon-ebs.aws",
    "source.googlecompute.gcp"
  ]

  provisioner "file" {
    source      = "../tf-packer.pub"
    destination = "/tmp/tf-packer.pub"
  }

  provisioner "file" {
    source      = "../files/spe-monitoring-agent.py"
    destination = "/tmp/spe-monitoring-agent.py"
  }

  provisioner "file" {
    source      = "../files/spe-monitoring-agent.service"
    destination = "/tmp/spe-monitoring-agent.service"
  }

  provisioner "file" {
    source      = "../environments/python/requirements.txt"
    destination = "/tmp/python-requirements.txt"
  }

  provisioner "file" {
    source      = "../environments/r/requirements.R"
    destination = "/tmp/r-requirements.R"
  }

  provisioner "file" {
    source      = "../data/hepatitis.csv"
    destination = "/tmp/hepatitis.csv"
  }

  provisioner "file" {
    source      = "../examples/python/read-hepatitis.ipynb"
    destination = "/tmp/read-hepatitis.ipynb"
  }

  provisioner "file" {
    source      = "../examples/r/read-hepatitis.R"
    destination = "/tmp/read-hepatitis.R"
  }

  provisioner "file" {
    source      = "../examples/r/spe-data-lab.Rproj"
    destination = "/tmp/spe-data-lab.Rproj"
  }

  provisioner "file" {
    source      = "../files/spe-jupyter"
    destination = "/tmp/spe-jupyter"
  }

  provisioner "file" {
    source      = "../files/spe-jupyter.desktop"
    destination = "/tmp/spe-jupyter.desktop"
  }

  provisioner "file" {
    source      = "../files/spe-rstudio.desktop"
    destination = "/tmp/spe-rstudio.desktop"
  }

  provisioner "file" {
    source      = "../files/spe-internet"
    destination = "/tmp/spe-internet"
  }

  provisioner "file" {
    source      = "../files/spe-internet-disabled.nft"
    destination = "/tmp/spe-internet-disabled.nft"
  }

  provisioner "file" {
    source      = "../files/spe-internet-allowlist.nft"
    destination = "/tmp/spe-internet-allowlist.nft"
  }

  provisioner "file" {
    source      = "../files/spe-internet-restore.service"
    destination = "/tmp/spe-internet-restore.service"
  }

  provisioner "file" {
    source      = "../files/spe-audit.rules"
    destination = "/tmp/spe-audit.rules"
  }

  provisioner "file" {
    source      = "../files/spe-pam-tty-audit"
    destination = "/tmp/spe-pam-tty-audit"
  }

  provisioner "file" {
    source      = "../files/spe-laurel.toml"
    destination = "/tmp/spe-laurel.toml"
  }

  provisioner "file" {
    source      = "../files/spe-network-audit.zeek"
    destination = "/tmp/spe-network-audit.zeek"
  }

  provisioner "file" {
    source      = "../files/spe-network-audit"
    destination = "/tmp/spe-network-audit"
  }

  provisioner "file" {
    source      = "../files/spe-network-audit.service"
    destination = "/tmp/spe-network-audit.service"
  }

  provisioner "file" {
    source      = "../files/spe-audit-logrotate"
    destination = "/tmp/spe-audit-logrotate"
  }

  provisioner "shell" {
    script = "../scripts/setup.sh"
  }

  provisioner "shell" {
    script = "../scripts/setup-data-tools.sh"
  }

  provisioner "shell" {
    script = "../scripts/setup-internet-control.sh"
  }

  provisioner "shell" {
    script = "../scripts/setup-auditing.sh"
  }

  provisioner "shell" {
    script = "../scripts/cleanup-image.sh"
  }
}
