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
    source      = "../files/logging/heartbeat/spe-monitoring-agent.py"
    destination = "/tmp/spe-monitoring-agent.py"
  }

  provisioner "file" {
    source      = "../files/logging/heartbeat/spe-monitoring-agent.service"
    destination = "/tmp/spe-monitoring-agent.service"
  }

  provisioner "file" {
    source      = "../files/logging/heartbeat/spe-monitoring-agent-journald.conf"
    destination = "/tmp/spe-monitoring-agent-journald.conf"
  }

  provisioner "file" {
    source      = "../files/logging/heartbeat/spe-identity"
    destination = "/tmp/spe-identity"
  }

  provisioner "file" {
    source      = "../files/logging/heartbeat/spe-identity.service"
    destination = "/tmp/spe-identity.service"
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
    source      = "../files/desktop/spe-jupyter"
    destination = "/tmp/spe-jupyter"
  }

  provisioner "file" {
    source      = "../files/desktop/spe-jupyter.desktop"
    destination = "/tmp/spe-jupyter.desktop"
  }

  provisioner "file" {
    source      = "../files/desktop/spe-rstudio.desktop"
    destination = "/tmp/spe-rstudio.desktop"
  }

  provisioner "file" {
    source      = "../files/internet-control/spe-internet"
    destination = "/tmp/spe-internet"
  }

  provisioner "file" {
    source      = "../files/internet-control/spe-internet-disabled.nft"
    destination = "/tmp/spe-internet-disabled.nft"
  }

  provisioner "file" {
    source      = "../files/internet-control/spe-internet-allowlist.nft"
    destination = "/tmp/spe-internet-allowlist.nft"
  }

  provisioner "file" {
    source      = "../files/internet-control/spe-internet-restore.service"
    destination = "/tmp/spe-internet-restore.service"
  }

  provisioner "file" {
    source      = "../files/internet-control/spe-metadata.nft"
    destination = "/tmp/spe-metadata.nft"
  }

  provisioner "file" {
    source      = "../files/logging/auditd/50-spe.rules"
    destination = "/tmp/50-spe.rules"
  }

  provisioner "file" {
    source      = "../files/logging/auditd/spe-tty-audit"
    destination = "/tmp/spe-tty-audit"
  }

  provisioner "file" {
    source      = "../files/logging/auditd/auditd.conf"
    destination = "/tmp/auditd.conf"
  }

  provisioner "file" {
    source      = "../files/logging/zeek/local.zeek"
    destination = "/tmp/local.zeek"
  }

  provisioner "file" {
    source      = "../files/logging/zeek/node.cfg"
    destination = "/tmp/node.cfg"
  }

  provisioner "file" {
    source      = "../files/logging/zeek/networks.cfg"
    destination = "/tmp/networks.cfg"
  }

  provisioner "file" {
    source      = "../files/logging/zeek/zeekctl.cfg"
    destination = "/tmp/zeekctl.cfg"
  }

  provisioner "file" {
    source      = "../files/logging/zeek/zeek-set-interface"
    destination = "/tmp/zeek-set-interface"
  }

  provisioner "file" {
    source      = "../files/logging/zeek/zeek.service"
    destination = "/tmp/zeek.service"
  }

  provisioner "file" {
    source      = "../files/logging/zeek/zeek-cron.service"
    destination = "/tmp/zeek-cron.service"
  }

  provisioner "file" {
    source      = "../files/logging/zeek/zeek-cron.timer"
    destination = "/tmp/zeek-cron.timer"
  }

  provisioner "shell" {
    script = "../scripts/image/setup.sh"
  }

  provisioner "shell" {
    script = "../scripts/image/setup-data-tools.sh"
  }

  provisioner "shell" {
    script = "../scripts/image/setup-internet-control.sh"
  }

  provisioner "shell" {
    script = "../scripts/image/setup-auditing.sh"
  }

  provisioner "shell" {
    script = "../scripts/image/cleanup-image.sh"
  }
}
