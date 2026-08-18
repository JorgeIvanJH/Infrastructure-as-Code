# My first accessible VM

This configuration keeps the basic GCP example and adds only what direct SSH
access requires:

1. A Debian Linux image with SSH support.
2. An ephemeral external IPv4 address.
3. A firewall rule allowing TCP port 22 from your public IPv4 address only.
4. An `ssh` network tag connecting that firewall rule to this VM.

The VM uses the free-tier-eligible `e2-micro` type and a 10 GB `pd-standard`
disk in `us-central1`. The external IPv4 address is billed separately from the
Compute Engine free-tier VM allowance.

## Deploy and connect

Authenticate once:

```powershell
gcloud auth application-default login
gcloud auth login
```

From this directory, find your current public IPv4 address and deploy:

```powershell
$myPublicIp = (Invoke-RestMethod -Uri "https://api.ipify.org").Trim()
terraform init
terraform apply -var="project=YOUR_PROJECT_ID" -var="ssh_source_cidr=$myPublicIp/32"
```

Connect using the command printed by Terraform, or run:

```powershell
terraform output -raw ssh_command
gcloud compute ssh accessible-vm --zone=us-central1-a --project=YOUR_PROJECT_ID
```

`gcloud compute ssh` creates an SSH key when needed and installs its public key
in Google Cloud metadata. This keeps key bootstrapping out of the Terraform
configuration.

If your public IP changes, run `terraform apply` again with the new `/32` value
before connecting. When finished, remove all resources with:

```powershell
terraform destroy -var="project=YOUR_PROJECT_ID" -var="ssh_source_cidr=$myPublicIp/32"
```
