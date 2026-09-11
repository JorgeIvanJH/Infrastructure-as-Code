# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

A personal Infrastructure as Code learning path: six numbered lesson folders that build on each
other, ending in a multicloud Secure Processing Environment (SPE). Terraform creates
infrastructure; Packer bakes the machine images. There is no application code, no test suite, and
no CI. Validation happens through `fmt`/`validate` plus assertions inside the Packer provisioning
scripts.

The environment is Windows with PowerShell, so all README command blocks are PowerShell.

## Commands

Every lesson is its own working directory. Run commands from inside the lesson folder, never from
the repository root.

Terraform loop (lessons 01, 02, and the `instances/` folder of 04, 05, 06):

~~~powershell
terraform init          # add -upgrade only when intentionally testing newer providers
terraform fmt
terraform validate
terraform plan
terraform apply
terraform destroy
~~~

Packer loop (lesson 03, and the `images/` folder of 04, 05, 06):

~~~powershell
packer init .
packer fmt .
packer validate -var-file="variables.pkrvars.hcl" .
packer build -var-file="variables.pkrvars.hcl" .
~~~

Lesson 06 builds one cloud at a time by build address. The build block is named `spe`:

~~~powershell
packer build -only="spe.googlecompute.gcp" -var-file="variables.pkrvars.hcl" .
& ..\scripts\aws-login\Invoke-WithAwsLogin.ps1 packer build '-only=spe.amazon-ebs.aws' '-var-file=variables.pkrvars.hcl' .
~~~

Guacamole gateway for lessons 05 and 06, from the lesson's `gateway/` folder:

~~~powershell
docker compose up -d
docker compose ps
docker compose down
~~~

### AWS commands need the credential bridge

The Packer Amazon plugin cannot read an `aws login` session. Any `packer` or `terraform` command
that touches AWS must be wrapped:

~~~powershell
& ..\..\scripts\aws-login\Invoke-WithAwsLogin.ps1 terraform plan
~~~

The wrapper starts [aws-login-credential-server.py](06-spe-multicloud-gcp-aws/scripts/aws-login/aws-login-credential-server.py)
on a random loopback port, exports the container-credentials environment variables, runs the
command, then kills the server and restores the previous environment. It never writes credentials
to disk. GCP commands need no wrapper because Application Default Credentials work directly.

## Architecture

### Lesson progression

Each folder is self-contained and teaches only what is new. Definitions live in
[GLOSSARY.md](GLOSSARY.md) and are not repeated per lesson.

| Folder | Adds |
|---|---|
| [01-terraform-basics-gcp](01-terraform-basics-gcp/) | One flat root: providers, resources, variables, outputs, state |
| [02-accessible-vm-gcp](02-accessible-vm-gcp/) | Public IP, firewall rule, network tags |
| [03-packer-basics](03-packer-basics/) | Docker builder locally, parallel sources, post-processors |
| [04-terraform-packer-gcp](04-terraform-packer-gcp/) | The `images/` and `instances/` split, image discovered by family |
| [05-spe-monitoring-agent-gcp](05-spe-monitoring-agent-gcp/) | The full SPE: desktop, data tools, internet control, auditing |
| [06-spe-multicloud-gcp-aws](06-spe-multicloud-gcp-aws/) | One shared recipe, two native images, two Terraform roots |

### The image and instance handoff

From lesson 04 onward, Packer and Terraform are decoupled through an image family name, not a
hardcoded image ID. Packer stamps `image_family` plus a timestamped `image_name`; Terraform reads
the newest member with a data source. Renaming a family breaks the handoff on both sides at once.

| Lesson | Family | Terraform lookup |
|---|---|---|
| 04 | `learn-terraform-packer` | `data.google_compute_image.packer` |
| 05 | `learn-spe-monitoring-agent` | `data.google_compute_image.spe` |
| 06 | `learn-spe-multicloud` | `data.google_compute_image.spe` and `data.aws_ami.spe` |

AWS has no image families, so lesson 06 writes an `ImageFamily` tag and the AWS data source filters
on that tag plus the name prefix.

### Lesson 06 multicloud boundary

Packer loads every `.pkr.hcl` in [images/](06-spe-multicloud-gcp-aws/images/) as one template, split
by role: plugins, variables, GCP source, AWS source, build. The two sources share one provisioner
list, so the operating system design is written once and built natively twice.

Terraform stays split into [instances/gcp](06-spe-multicloud-gcp-aws/instances/gcp/) and
[instances/aws](06-spe-multicloud-gcp-aws/instances/aws/) because resource types are
provider-specific and cannot be selected with a variable. The two roots deliberately expose the
same variable names (`spe_id`, `vm_size`, `disk_size_gb`, `disk_type`, `ssh_source_cidr`,
`rdp_source_cidr`, `heartbeat_interval_seconds`) and the same outputs (`cloud_provider`, `spe_id`, `image_id`, `public_ip`,
`private_ip`, `ssh_command`, `rdp_address`). Preserve that parity when editing either root. State is
never copied between them.

### Shared image recipe is duplicated, not linked

Lessons 05 and 06 each hold their own copy of `data/`, `environments/`, `examples/`, `files/`, and
`scripts/`. A change to a shared SPE component must be made in the lesson being worked on, and
lesson 06 changes should be tested against both cloud images.

Three files in lesson 06 intentionally diverge from lesson 05 because they were made cloud-neutral:
the disabled-mode nftables rules, the internet restore unit, and the network audit launcher. Do not
resync them to the lesson 05 wording.

In lesson 06, everything that produces telemetry lives under
[files/logging/](06-spe-multicloud-gcp-aws/files/logging/), split by producer: `auditd/` (rules and
PAM include), `zeek/` (ZeekControl `node.cfg`, `zeekctl.cfg`, `networks.cfg`, site policy, interface script, units and timer), and `heartbeat/` (agent,
unit, identity script and unit, and a journald drop-in raising `LineMax` so a long document is not cut in two). Each producer folder has a README on how its stream is produced, stored, and read, and
`README.md` at the top of the folder is a one-table index of those subfolders. The rest of `files/` is split the same way: `internet-control/` (the `spe-internet` toggle, its nftables rule files, the metadata access table, and the restore unit) and `desktop/` (the JupyterLab launcher and the two XFCE menu entries). Formerly described as desktop,
launchers, and internet control. The build template's upload `source` paths point into these
subfolders, so a moved file needs a matching edit there.

### Provisioning contract

Every artifact reaches the build VM the same way, and this convention is load-bearing:

1. A file provisioner in the build template uploads to a flat `/tmp/<name>` path.
2. A shell script installs it to its real location with `install` and explicit owner, group, and
   mode.
3. The same script deletes the temporary copy.

Shell provisioners run in order and the order matters:
[setup.sh](06-spe-multicloud-gcp-aws/scripts/image/setup.sh) for desktop, users, and heartbeat, then
[setup-data-tools.sh](06-spe-multicloud-gcp-aws/scripts/image/setup-data-tools.sh) for JupyterLab, R,
RStudio, and the workspace, then
[setup-internet-control.sh](06-spe-multicloud-gcp-aws/scripts/image/setup-internet-control.sh) for
nftables, then [setup-auditing.sh](06-spe-multicloud-gcp-aws/scripts/image/setup-auditing.sh) for auditd
and Zeek, and finally
[cleanup-image.sh](06-spe-multicloud-gcp-aws/scripts/image/cleanup-image.sh) to drop build SSH keys and
caches. Adding a file means editing both the build template and the installing script.

### Scripts fail the build, not the VM

Every setup script runs `set -euo pipefail` and ends by proving its own work, so a misconfiguration
stops the Packer build instead of shipping in the image. Existing examples: `systemd-analyze verify`
on each unit, a `visudo` check, `nft --check`, `augenrules --check` followed by a grep of the loaded
rules, a pandas assertion on the dataset shape, an `ldd` scan for missing RStudio
libraries, and a live HTTPS request that must fail with internet off and succeed with it on. Keep
this pattern when adding a component.

### SPE runtime model

[HOW-THE-SPE-WORKS.md](06-spe-multicloud-gcp-aws/HOW-THE-SPE-WORKS.md) is the plain-words version of
this section with diagrams; keep the two in step. Two accounts, split on purpose. The `terraform` account is the SSH administrator with passwordless
sudo and the baked-in public key. The `speuser` account owns the XFCE desktop, is created locked,
and gets its password set manually over SSH after apply. No reusable password exists in the image,
in Terraform files, or in Terraform state. A third account, `spe-netaudit`, is a no-login system
user that runs Zeek and owns `/var/log/spe-audit`. The image carries no SPE identity: at boot,
`spe-identity` reads `spe-id` and `spe-heartbeat-interval` from instance metadata into
`/etc/spe/identity.env`, which the heartbeat unit requires and loads. An always-loaded nftables
table `spe_metadata` limits new connections (the SYN only) to the metadata API (tcp/80) to root and
`terraform`.

Access path: browser to Guacamole in Docker on the laptop, then RDP on 3389, then xrdp, then XFCE.
The cloud firewall admits SSH and RDP from a single `/32`. Inside the VM,
[spe-internet](06-spe-multicloud-gcp-aws/files/internet-control/spe-internet) toggles an nftables table named
`spe_egress`, persists the choice under `/var/lib/spe-internet`, and a systemd unit replays it on
boot. Audit output is two local files: raw auditd records in `/var/log/audit/audit.log`, several
lines per event, and Zeek connection metadata as JSON Lines in `/var/log/spe-audit`. Laurel, which
used to aggregate the auditd records into JSON, was removed on 2026-09-10 so the two tools can be
studied on their own; it may return as a design change.
Since 2026-09-11 the heartbeat agent reads both files itself every interval and prints one JSON
document with `spe_id`, `boot_id`, `sequence`, `timestamp`, `internet`, an `os` array (auditd
events shaped to `command`, `session`, `tty`) and a `net` array (ten renamed Zeek fields). It reads
auditd through `ausearch --checkpoint` and Zeek through an inode-and-offset cursor, keeps its
bookmarks in `/var/lib/spe-monitoring-agent` (systemd `StateDirectory=`), moves them only after
printing, and supports `--once` for a no-side-effect document, which the build uses as its proof.
To make that possible without sudo, `auditd.conf` sets `log_group = terraform` and `terraform` is
in the `spe-netaudit` group. The document shape and the field-by-field rationale live in
[README.md](06-spe-multicloud-gcp-aws/files/logging/README.md), which is also the one-table index
of the producer folders; each producer README explains how its records are produced, stored,
rotated, and read. Sending the document to a collector over HTTPS is the next step; the rules it
must follow (fixed IP in the egress allowlist, TLS, bookmarks move only on 2xx, nothing dropped)
are written in that README.

## Conventions

- **Never commit local values.** The ignore file covers `terraform.tfvars`,
  `variables.pkrvars.hcl`, `user-mapping.xml`, the local SSH key pair, provider downloads, and
  state. Each is provided as an example file to copy and fill in. Add a matching example file when
  introducing a new input file.
- **Provider versions are pinned** and lock files are committed, so the exercises stay repeatable.
  Review a lock-file change before committing it.
- **Docs use `~~~` fences**, not backticks. READMEs are written in the first person as working
  notes, use numbered step headings, and end with a security scope section plus links to official
  documentation. Match that voice when editing them.
- **A new concept goes in the glossary once**, then lessons reference it.
- **Cleanup is manual and per lesson.** Destroying infrastructure never removes a Packer image. GCP
  images are deleted by exact name. An AWS AMI needs deregistering and then a separate delete of its
  backing EBS snapshot.
- These lessons create billable resources in GCP and AWS. Do not run an apply or an image build
  without being asked.
