# Learn Terraform Provisioning on GCP

This project builds an Ubuntu image with Packer and then deploys a VM from that
image with Terraform. It uses the Google Cloud project
`even-lyceum-505816-g5`, region `us-central1`, and zone `us-central1-c`.

The provisioning lesson is unchanged: Packer copies `tf-packer.pub` into its
temporary build VM, and `scripts/setup.sh` creates a `terraform` user, installs
the public key, and downloads the example Go application.

## Authenticate

```powershell
gcloud auth login
gcloud auth application-default login
gcloud config set project even-lyceum-505816-g5
```

## Build the GCP image

Create `tf-packer` and `tf-packer.pub` in this directory first, as described in
the parent README. Then run:

```powershell
cd .\images
packer init .
packer fmt -check .
packer validate .
packer build .
```

Packer creates a timestamped custom image in the image family
`learn-terraform-packer`. Terraform automatically selects the newest image in
that family.

## Deploy the VM

From the `images` directory:

```powershell
cd ..\instances
$myPublicIp = (Invoke-RestMethod -Uri "https://api.ipify.org").Trim()
terraform init -upgrade
terraform fmt -check
terraform validate
terraform plan -var="ssh_source_cidr=$myPublicIp/32"
terraform apply -var="ssh_source_cidr=$myPublicIp/32"
```

The SSH firewall rule accepts traffic only from your current public IPv4
address. If that address changes, apply again with the new value.

## Connect

```powershell
terraform output -raw ssh_command
ssh -i ..\tf-packer terraform@$(terraform output -raw public_ip)
```

## Run and access the Go application

Inside the VM, start the application:

```bash
cd ~/learn-go-webapp-demo
go run webapp.go
```

Keep that SSH terminal open while the application runs. On the local computer,
get the public IP with `terraform output -raw public_ip`, then open:

```text
http://PUBLIC_IP:8080
```

From a second SSH session, verify the application directly on the VM with:

```bash
curl http://localhost:8080
```

To keep the application running after closing SSH, start it in the background:

```bash
nohup go run webapp.go > webapp.log 2>&1 &
```

Inspect or stop the background application with:

```bash
cat webapp.log
pkill -f "go run webapp.go"
```

When finished, remove the VM and network resources:

```powershell
terraform destroy -var="ssh_source_cidr=$myPublicIp/32"
```

The Packer image is separate from Terraform state and remains in the project
after `terraform destroy`.
