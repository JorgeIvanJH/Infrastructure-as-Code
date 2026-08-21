# 02 - Make a GCP VM accessible through SSH

## Goal

Lesson 1 created a VM, but a public IP alone is not enough for SSH. This lesson
adds the minimum pieces needed for direct access:

1. A Debian VM with an ephemeral public IPv4 address.
2. A firewall rule allowing TCP port 22.
3. A network tag connecting that rule to this VM.
4. A /32 source range so only my current public IP can connect.

## Files

- [main.tf](main.tf) creates the network, firewall, and VM.
- [variables.tf](variables.tf) validates the SSH source as one IPv4 address.
- [terraform.tfvars.example](terraform.tfvars.example) shows local values.
- [outputs.tf](outputs.tf) prints the public IP and an SSH command.

## Prepare variables

Copy the example:

~~~powershell
Copy-Item terraform.tfvars.example terraform.tfvars
~~~

Find your current public IP:

~~~powershell
(Invoke-RestMethod -Uri "https://api.ipify.org").Trim()
~~~

Edit terraform.tfvars:

~~~hcl
project         = "YOUR_PROJECT_ID"
region          = "us-central1"
zone            = "us-central1-c"
ssh_source_cidr = "YOUR_PUBLIC_IP/32"
~~~

The /32 means one address. Do not use 0.0.0.0/0 for SSH.

## Deploy

~~~powershell
gcloud auth login
gcloud auth application-default login

terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
~~~

## Connect

Print and run the generated command:

~~~powershell
terraform output -raw ssh_command
~~~

Or run:

~~~powershell
gcloud compute ssh accessible-vm --zone=us-central1-c --project=YOUR_PROJECT_ID
~~~

**gcloud compute ssh** creates an SSH key when needed and installs its public
key through Google Cloud metadata. Lesson 4 shows a different approach where a
public key is placed inside a Packer image.

If your public IP changes, update ssh_source_cidr and run terraform apply again.

## Clean up

~~~powershell
terraform destroy
~~~

Because all required values are in terraform.tfvars, destroy does not ask for
the IP again.

## Cost note

The e2-micro VM and standard disk may fit within eligible Free Tier limits, but
an external IPv4 address can be billed separately. Always check the current
[Google Cloud pricing](https://cloud.google.com/vpc/network-pricing#ipaddress).

Further reading:

- [GCP firewall rules](https://cloud.google.com/firewall/docs/firewalls)
- [Connect to Linux VMs](https://cloud.google.com/compute/docs/connect/standard-ssh)
- [Terraform Google Compute instance](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_instance)
