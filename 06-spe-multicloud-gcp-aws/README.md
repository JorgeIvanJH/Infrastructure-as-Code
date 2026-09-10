# Lesson 6: Deploy the same SPE on GCP or AWS

Lesson 5 created a complete Secure Processing Environment on GCP. This lesson
keeps the same Linux SPE and adds a second cloud.

The new goal is:

> Use one shared Packer recipe to create native GCP and AWS images, then use a
> small cloud-specific Terraform root to deploy either one with the same main
> variables and outputs.

This lesson does not repeat how XFCE, Guacamole, JupyterLab, RStudio, the
heartbeat, internet control, or auditing work. Lesson 5 explains those
components. Here I focus on the multicloud boundary.

~~~text
                         shared files and setup scripts
                                      |
                    +-----------------+-----------------+
                    |                                   |
          Packer googlecompute                    Packer amazon-ebs
                    |                                   |
          native GCP image family                  native AWS AMI
                    |                                   |
          Terraform instances/gcp                Terraform instances/aws
                    |                                   |
                 GCP SPE                              AWS SPE
~~~

Cloud agnostic does not mean that a GCP resource becomes an AWS resource. It
means the common operating-system design is shared and the cloud-specific code
is kept at the edge.

## What is shared

Both images contain the complete Lesson 5 SPE:

- Ubuntu 24.04 on AMD64.
- The `terraform` SSH administrator and locked `speuser` desktop account.
- XFCE, xrdp, JupyterLab, RStudio, and the hepatitis data examples.
- The Python heartbeat systemd service.
- The `spe-internet` outbound-control command.
- auditd, `pam_tty_audit`, Zeek, and local log rotation.

The contents of `data`, `environments`, `examples`, `files`, and `scripts` are
the shared image recipe. I should change a shared component once and test both
cloud images after that change.

## What remains cloud specific

| Concern | GCP | AWS |
|---|---|---|
| Packer source | `googlecompute.gcp` | `amazon-ebs.aws` |
| Image artifact | Compute Engine image | EC2 AMI plus EBS snapshot |
| Terraform provider | `google` | `aws` |
| VM size example | `e2-medium` | `c7i-flex.large` |
| Disk type example | `pd-standard` | `gp3` |
| Private network | VPC network and subnet | VPC and subnet |
| Inbound rules | GCP firewall rules | AWS security-group rules |

The two native images are equivalent recipes, not the same binary image file.

## Files introduced by this lesson

~~~text
06-spe-multicloud-gcp-aws/
|-- images/
|   |-- plugins.pkr.hcl
|   |-- variables.pkr.hcl
|   |-- sources.gcp.pkr.hcl
|   |-- sources.aws.pkr.hcl
|   |-- build.pkr.hcl
|   `-- variables.pkrvars.hcl.example
|-- instances/
|   |-- gcp/
|   |   |-- versions.tf
|   |   |-- variables.tf
|   |   |-- main.tf
|   |   |-- outputs.tf
|   |   `-- terraform.tfvars.example
|   `-- aws/
|       |-- versions.tf
|       |-- variables.tf
|       |-- main.tf
|       |-- outputs.tf
|       `-- terraform.tfvars.example
|-- gateway/
|   |-- compose.yaml
|   `-- user-mapping.xml.example
|-- scripts/
|   |-- Invoke-WithAwsLogin.ps1       # gives Packer or Terraform renewable AWS login credentials
|   |-- aws-login-credential-server.py
|   |-- cleanup-image.sh              # removes temporary build users' SSH access and caches
|   `-- setup*.sh                     # shared SPE installation scripts
|-- data/, environments/, examples/, files/
|-- tf-packer       # local private key; ignored by Git
`-- tf-packer.pub   # public key placed in both images; ignored by Git
~~~

Packer loads every `.pkr.hcl` file in `images` as one template. Splitting the
template makes the shared build and the two cloud sources easy to identify.

Terraform uses two root directories and two state files. Terraform resource
types are provider-specific and cannot be selected dynamically with a normal
string variable. Separate roots also let me plan or destroy one cloud without
placing the other cloud at risk.

## 1. Check authentication and cost

I need the Lesson 5 tools plus the AWS CLI and an AWS account with billing.
Both Packer builders create a temporary VM, and both clouds charge for stored
custom images. The final VMs, disks, and public IPv4 addresses can also cost
money.

Check GCP:

~~~powershell
gcloud auth list
gcloud auth application-default login
gcloud config get-value project
~~~

Check AWS in a newly opened PowerShell window:

~~~powershell
aws --version
aws sts get-caller-identity
aws configure get region
~~~

If `aws` is not recognized immediately after an all-users installation, close
PowerShell and open it again so it receives the new `PATH` value.

The identity returned by `aws sts get-caller-identity` should be an
administrative IAM Identity Center user or assumed role. It should not normally
end with `:root`. AWS recommends protecting the root user with MFA, not creating
root access keys, and not using root for everyday work.

Do not place GCP credentials, AWS access keys, private SSH keys, or passwords in
Packer and Terraform files.

### Let Packer and Terraform use an `aws login` session

The AWS CLI can use the newer `aws login` session directly. The current Packer
Amazon plugin cannot read that login format by itself. This lesson includes a
small PowerShell bridge. While one command runs, it exposes refreshable
short-lived credentials through an authenticated, localhost-only endpoint that
the AWS SDK understands. The endpoint stops when the command ends.

Refresh the CLI login before a long image build:

~~~powershell
aws login --profile default
aws sts get-caller-identity --profile default
~~~

The later AWS commands use `scripts\Invoke-WithAwsLogin.ps1`. The helper can
refresh credentials during a long Packer build, does not print them, and does
not write them to a file. Only processes on my laptop that know a random
temporary token can call its loopback endpoint. If I already use a normal AWS
profile based on an IAM role or IAM Identity Center, I may instead use that
profile through my usual organization workflow.

## 2. Create the shared runtime SSH key

From the repository root:

~~~powershell
cd "06-spe-multicloud-gcp-aws"
ssh-keygen -t rsa -b 4096 -N "" -f .\tf-packer
~~~

Packer uses its own temporary access to prepare each build VM. It copies only
`tf-packer.pub` into the finished image for the runtime `terraform` account.
The private `tf-packer` file never leaves my laptop and is ignored by Git.

If the key already exists and I still use it, I do not overwrite it.

## 3. Configure the image builds

~~~powershell
cd images
Copy-Item variables.pkrvars.hcl.example variables.pkrvars.hcl
~~~

Set my GCP project and the locations I want to use:

~~~hcl
gcp_project_id = "my-gcp-project"
gcp_zone       = "us-central1-c"
aws_region     = "us-east-1"
~~~

The remaining values control Packer's temporary hardware:

| Variable | GCP example | AWS example |
|---|---:|---:|
| Build VM | `gcp_build_vm_size = "e2-medium"` | `aws_build_vm_size = "c7i-flex.large"` |
| Image disk | `image_disk_size_gb = 30` | Same shared value |
| Disk type | `gcp_image_disk_type = "pd-standard"` | `aws_image_disk_type = "gp3"` |

These are build-machine settings. Terraform has separate variables for the
hardware of the final SPE.

If GCP reports that the selected build zone has insufficient capacity, change
only `gcp_zone` to another zone in the same region and run the build again. A
GCP custom image is project-wide, so this does not change where Terraform may
later create the final VM.

Initialize, format, and validate the complete template:

~~~powershell
packer init .
packer fmt .
packer validate -var-file="variables.pkrvars.hcl" .
~~~

## 4. Build one or both native images

Build only GCP:

~~~powershell
packer build -only="spe.googlecompute.gcp" -var-file="variables.pkrvars.hcl" .
~~~

Build only AWS:

~~~powershell
& ..\scripts\Invoke-WithAwsLogin.ps1 packer build '-only=spe.amazon-ebs.aws' '-var-file=variables.pkrvars.hcl' .
~~~

Build both in one run:

~~~powershell
& ..\scripts\Invoke-WithAwsLogin.ps1 packer build '-var-file=variables.pkrvars.hcl' .
~~~

The last command can build in both clouds at the same time, so it can incur
charges in both clouds at the same time. The AWS builder expects an account
with a default VPC unless I later provide explicit build-network settings.

Both artifacts use the logical family `learn-spe-multicloud`. GCP stores this
as an image family. AWS stores it as the `ImageFamily` tag because AWS does not
have GCP image families.

Inspect the results:

~~~powershell
gcloud compute images list --filter="family=learn-spe-multicloud"
aws ec2 describe-images --owners self --filters "Name=tag:ImageFamily,Values=learn-spe-multicloud" --query "Images[*].[ImageId,Name,State]" --output table
~~~

## 5. Prepare the deployment values

Copy the values for the cloud or clouds I want to use:

~~~powershell
cd ..
Copy-Item instances\gcp\terraform.tfvars.example instances\gcp\terraform.tfvars
Copy-Item instances\aws\terraform.tfvars.example instances\aws\terraform.tfvars
~~~

Set the GCP project in `instances/gcp/terraform.tfvars`. In both files, replace
`YOUR_PUBLIC_IPV4/32` with the current public address of the laptop running SSH
and Guacamole.

Both roots use the same important interface:

| Variable | Meaning |
|---|---|
| `spe_id` | Name of the final SPE |
| `vm_size` | Provider-specific compute shape |
| `disk_size_gb` | Boot-disk capacity, with a 30 GB minimum |
| `disk_type` | Provider-specific disk performance class |
| `ssh_source_cidr` | One address allowed to reach TCP 22 |
| `rdp_source_cidr` | Guacamole gateway address allowed to reach TCP 3389 |
| `heartbeat_interval_seconds` | Seconds between heartbeats, read by the VM at boot from instance metadata |

The location and network variables are also exposed because their valid shape
differs by cloud.

Comparable starting values are:

~~~text
GCP: e2-medium, 30 GB pd-standard
AWS: c7i-flex.large, 30 GB gp3
~~~

Both provide 2 virtual CPUs and 4 GB of memory. Cloud performance and prices
are not identical, even when the numbers look similar.

## 6. Select a cloud and deploy

From the lesson root, choose one value:

~~~powershell
$cloud = "gcp" # change to "aws" when I want AWS
cd "instances\$cloud"
terraform init
terraform fmt
terraform validate

if ($cloud -eq "aws") {
    & ..\..\scripts\Invoke-WithAwsLogin.ps1 terraform plan
    & ..\..\scripts\Invoke-WithAwsLogin.ps1 terraform apply
}
else {
    terraform plan
    terraform apply
}
~~~

Read the plan before approving it. The selected root finds the newest image in
its own cloud and creates one isolated network, restricted SSH and RDP access,
a public address, a 30 GB encrypted boot disk, and the final SPE.

The two roots deliberately have the same outputs:

~~~powershell
terraform output
terraform output -raw ssh_command
terraform output -raw rdp_address
terraform output -raw image_id
~~~

I can deploy both clouds at once because they have separate state. I run the
same commands once in `instances/gcp` and once in `instances/aws`.

## 7. Connect through SSH

Run the `ssh_command` output from the current Terraform directory. If Windows
reports that the private-key permissions are too open, restrict the key once:

~~~powershell
$keyPath = Resolve-Path ..\..\tf-packer
icacls $keyPath /inheritance:r
icacls $keyPath /grant:r "$($env:USERNAME):(R)"
~~~

Then run the SSH command again. A new cloud VM has a new SSH host key. I verify
the address belongs to the VM I just created before accepting it.

Inside each SPE, configure the desktop account at runtime:

~~~bash
sudo passwd speuser
sudo systemctl is-active xrdp spe-monitoring-agent auditd zeek
~~~

No reusable desktop password is stored in either image or Terraform state.

## 8. Add the selected SPEs to Guacamole

From the lesson root:

~~~powershell
Copy-Item gateway\user-mapping.xml.example gateway\user-mapping.xml
~~~

The example contains one GCP connection and one AWS connection. Replace the IP
and desktop-password placeholders for every SPE I deployed. Remove the unused
connection if I built only one cloud. Also replace `CHANGE_ME` with the local
Guacamole web password.

Start the same local gateway used in Lesson 5:

~~~powershell
cd gateway
docker compose up -d
docker compose ps
~~~

Open:

~~~text
http://127.0.0.1:8081/guacamole/
~~~

The menu labels make it clear whether I am opening **GCP SPE desktop** or
**AWS SPE desktop**. The desktop experience inside each VM should be the same.

## 9. Run a short parity check

Perform this check in both clouds:

~~~bash
hostname
python3 --version
sudo systemctl is-enabled xrdp spe-monitoring-agent auditd zeek zeek-cron.timer
sudo spe-internet status
sudo tail -n 1 /var/log/audit/audit.log
sudo tail -n 1 /var/log/spe-audit/network.jsonl | jq .
find ~/spe-data-lab -maxdepth 2 -type f | sort
~~~

Then use the graphical desktop to open the Jupyter notebook and RStudio project
as in Lesson 5. Exercise `spe-internet off` and `on`, create a short HTTPS
connection, inspect both audit logs, and reboot. The acceptance test is equal
behavior, not identical cloud IDs or background log events.

The detailed application and audit-log instructions remain in Lesson 5 and in
`files/logging/AUDIT-LOG-GUIDE.md`. How the heartbeat and both audit streams are
produced, stored, and rotated, and what a future off-VM exporter must account
for, is explained in `files/logging/TELEMETRY-PIPELINE-GUIDE.md`.

## 10. Change hardware without changing the SPE recipe

To give a final VM more memory, change only `vm_size` in that cloud's
`terraform.tfvars` and review `terraform plan`:

~~~hcl
# GCP example
vm_size = "e2-standard-2"

# AWS example
vm_size = "m7i-flex.large"
~~~

To enlarge storage:

~~~hcl
disk_size_gb = 40
~~~

The image and final disk both need at least 30 GB. A final disk can be larger
than the image. Reducing an existing cloud disk is generally not an in-place
operation, so treat disk-size reductions as a rebuild or migration task.

Changing `disk_type` selects a cloud-specific storage class. Never assume
similarly named classes have equal performance or price; check the provider's
current documentation before choosing.

## 11. Switch clouds safely

To stop using one deployment and create the other:

1. Enter the current cloud's Terraform directory.
2. Run `terraform destroy` and review the resources to remove.
3. Enter the other cloud's directory.
4. Run `terraform plan` and `terraform apply` there.

I do not copy Terraform state between providers. State contains provider-
specific resource identities.

I can also keep both deployments for comparison. They remain independent and
will both continue to incur charges until destroyed.

## 12. Clean up

Destroy final infrastructure from each root that was applied:

~~~powershell
terraform '-chdir=instances\gcp' destroy
& .\scripts\Invoke-WithAwsLogin.ps1 terraform '-chdir=instances\aws' destroy
docker compose -f gateway\compose.yaml down
~~~

Terraform does not delete Packer images.

List GCP images before deleting an exact old image:

~~~powershell
gcloud compute images list --filter="family=learn-spe-multicloud"
gcloud compute images delete EXACT_GCP_IMAGE_NAME
~~~

An AWS AMI has a backing EBS snapshot. Record both exact IDs, deregister the
AMI, and then delete its snapshot:

~~~powershell
aws ec2 describe-images --owners self --filters "Name=tag:ImageFamily,Values=learn-spe-multicloud" --query "Images[*].[ImageId,Name,BlockDeviceMappings[*].Ebs.SnapshotId]" --output table
aws ec2 deregister-image --image-id EXACT_AMI_ID
aws ec2 delete-snapshot --snapshot-id EXACT_SNAPSHOT_ID
~~~

These image deletions are permanent. I verify the IDs and confirm that no VM
still needs the image before running them.

## Security and scope

- This remains a learning proof of concept, not a production hardened SPE.
- The runtime SSH public key is baked into both images for continuity with the
  earlier lessons. A production design injects runtime access per deployment.
- SSH and RDP are restricted to one source IPv4 address, but both final VMs
  still have public addresses.
- Guacamole XML stores forwarded RDP credentials in plaintext locally.
- Local audit logs can be changed by a root administrator or lost with the VM.
- The images use AMD64. ARM shapes need separate native images and testing.
- AWS AMIs are regional. Build or copy an AMI into every AWS region where it
  will be deployed.
- The `spe-internet` policy is shared Linux behavior. Cloud firewalls remain a
  second, provider-specific security layer.

## Official documentation

- [Packer multicloud artifacts](https://developer.hashicorp.com/packer/tutorials/cloud-production/multicloud)
- [Packer Amazon EBS builder](https://developer.hashicorp.com/packer/integrations/hashicorp/amazon/latest/components/builder/ebs)
- [Packer Google Compute builder](https://developer.hashicorp.com/packer/integrations/hashicorp/googlecompute/latest/components/builder/googlecompute)
- [Canonical Ubuntu images on AWS](https://documentation.ubuntu.com/aws/en/latest/aws-how-to/instances/find-ubuntu-images/)
- [Terraform providers in modules](https://developer.hashicorp.com/terraform/language/modules/develop/providers)
- [AWS CLI `export-credentials`](https://docs.aws.amazon.com/cli/latest/reference/configure/export-credentials.html)
- [AWS root-user best practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/root-user-best-practices.html)
- [AWS AMIs are regional](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/CopyingAMIs.html)
