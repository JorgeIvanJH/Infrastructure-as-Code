these five scripts are the recipe of the SPE image. packer starts a temporary VM from a stock ubuntu 24.04 image, uploads the files from [files/](../../files/) to `/tmp`, runs these scripts over SSH in the order below, and then saves the disk as the image. the scripts never land on the VM themselves; they run once, and only what they installed remains.

the same five scripts run for GCP and for AWS. that is the whole idea of the lesson: one recipe, two native images. nothing in them knows which cloud it is on; the two places where that matters (the network interface name, the instance metadata format) are resolved at boot on the deployed VM, not here.

~~~mermaid
flowchart TB
    P["packer build<br>images/build.pkr.hcl"] --> U["upload files/* to /tmp on the build VM"]
    U --> S1["1. setup.sh<br>desktop, accounts, heartbeat"]
    S1 --> S2["2. setup-data-tools.sh<br>python env, jupyterlab, R, rstudio, workspace"]
    S2 --> S3["3. setup-internet-control.sh<br>nftables, spe-internet, metadata policy"]
    S3 --> S4["4. setup-auditing.sh<br>auditd, zeek via zeekcontrol"]
    S4 --> S5["5. cleanup-image.sh<br>drop build keys and caches"]
    S5 --> I["native image<br>GCP image family / AWS AMI"]
~~~

the order matters. accounts come first because later scripts install files owned by `terraform`, `speuser` and `spe-netaudit`; the firewall comes before auditing because the auditing script proves zeek works with a real HTTPS request, and the metadata policy needs the `terraform` account to exist when nft resolves the names.

# what each script installs and what it proves

every script runs with `set -euo pipefail` and ends by checking its own work, so a mistake stops the build instead of shipping in the image. that is the only test suite this repo has.

| script | installs | proves before the image is saved |
|---|---|---|
| `setup.sh` | XFCE and xrdp; the `terraform` admin (ssh key, passwordless sudo) and the locked `speuser` desktop account; the heartbeat agent, its unit, and the `spe-identity` boot step from [files/logging/heartbeat](../../files/logging/heartbeat/) | `systemd-analyze verify` on both units, `bash -n` on the identity script, the agent compiles. the identity step itself is not run: the build VM has no SPE metadata, on purpose |
| `setup-data-tools.sh` | a python environment in `/opt/spe-python` with jupyterlab, R and a pinned RStudio desktop, the example workspace in `speuser`'s home, the two menu entries from [files/desktop](../../files/desktop/) | pandas reads the dataset and asserts its shape, R reads it too, `ldd` finds no missing RStudio libraries |
| `setup-internet-control.sh` | nftables, chrony and `libnss-myhostname`; `spe-internet` and its rule files from [files/internet-control](../../files/internet-control/); the restore unit; on GCP, the guest agent's Cloud Logging switched off | a new HTTPS request fails with the internet off and succeeds with it on, the VM's own name still resolves while sealed, the metadata API answers `root` and `terraform` but refuses `speuser`, and names resolve again with the internet on |
| `setup-auditing.sh` | auditd with our rules, config and TTY auditing from [files/logging/auditd](../../files/logging/auditd/); zeek and zeekcontrol with our node, config and policy from [files/logging/zeek](../../files/logging/zeek/); the `spe-netaudit` account | the rules load and show up in `auditctl -l`, `zeekctl check` accepts the configuration, the node deploys, a real connection ends up as valid JSON in an archived zeek log, and an `execve` record with key `spe_cli` is in `audit.log` |
| `cleanup-image.sh` | nothing. removes packer's temporary SSH keys, apt and pip caches | the image carries no build-time access and is smaller |

# the provisioning contract

every file reaches the VM the same way, and the whole recipe depends on it:

1. a `file` provisioner in [build.pkr.hcl](../../images/build.pkr.hcl) uploads it flat to `/tmp/<name>`.
2. the script installs it to its real place with `install` and an explicit owner, group and mode.
3. the same script deletes the `/tmp` copy.

so adding a file means editing two places: the template, and the script that installs it. the READMEs in each `files/` subfolder list where every file lands.

# before the first build: let packer reach its build VM

packer provisions over SSH from the laptop to a temporary VM with a public address. on GCP that VM sits on the project's `default` network, and whether SSH gets through depends on a firewall rule that a fresh project has (`default-allow-ssh`, open to the world) and a tidied project often does not. without one, the build fails after six minutes with `Timeout waiting for SSH` and nothing in the recipe has run.

the GCP source tags the build VM `packer-build`, so the rule can be narrow: port 22, from the laptop only, to tagged instances only.

~~~powershell
$myIp = (Invoke-RestMethod https://checkip.amazonaws.com).Trim()
gcloud compute firewall-rules create packer-build-allow-ssh --network=default --direction=INGRESS --action=ALLOW --rules=tcp:22 --source-ranges="$myIp/32" --target-tags=packer-build
# later, when the laptop's public address changes:
gcloud compute firewall-rules update packer-build-allow-ssh --source-ranges="$myIp/32"
~~~

AWS needs nothing here: the amazon-ebs builder creates its own temporary security group for the build and removes it afterwards.

# running it

from `images/`, one cloud at a time or both at once:

~~~powershell
packer validate -var-file="variables.pkrvars.hcl" .
packer build -only="spe.googlecompute.gcp" -var-file="variables.pkrvars.hcl" .
& ..\scripts\aws-login\Invoke-WithAwsLogin.ps1 packer build '-only=spe.amazon-ebs.aws' '-var-file=variables.pkrvars.hcl' .
~~~

the AWS build needs the wrapper in [../aws-login](../aws-login/README.md) because packer cannot read an `aws login` session by itself. a build takes fifteen to thirty minutes and creates a billable VM while it runs and a billable image when it finishes; images are not removed by `terraform destroy`.
