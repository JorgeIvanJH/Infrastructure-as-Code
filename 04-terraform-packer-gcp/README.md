# Lesson 4: Build a GCP image, then deploy it with Terraform

This lesson brings the earlier ideas together:

- Packer builds a reusable VM image in GCP.
- Terraform creates the network, firewall rules, and final VM from that image.
- A shell script installs the software while Packer is building the image.

The result is a VM that already contains a small Go web application and a
learning user named `terraform`.

## The whole journey

~~~text
Your computer
   |
   | packer build
   v
temporary GCP build VM --> setup.sh --> custom GCP image
                                            |
                                            | terraform apply
                                            v
                                  network + firewall + final VM
~~~

Packer deletes its temporary build VM after a successful build. The custom
image stays in GCP so Terraform can use it. Terraform does not manage that
image because Terraform did not create it.

## Files in this lesson

~~~text
04-terraform-packer-gcp/
|-- images/
|   |-- image.pkr.hcl
|   `-- variables.pkrvars.hcl.example
|-- instances/
|   |-- main.tf
|   |-- variables.tf
|   `-- terraform.tfvars.example
|-- scripts/
|   `-- setup.sh
|-- tf-packer       # local private key; ignored by Git
`-- tf-packer.pub   # public key copied into the image; ignored by Git
~~~

The `.example` files are safe templates for Git. Your real value files are
ignored by Git.

## 1. Authenticate to GCP

Packer and Terraform use Application Default Credentials (ADC):

~~~powershell
gcloud auth application-default login
~~~

This gives programs on your computer permission to call Google Cloud APIs as
you. It is different from `gcloud auth login`, which signs the `gcloud` command
itself in.

Your GCP project needs billing and the Compute Engine API enabled.

## 2. Create the learning SSH key

From this lesson folder, create a key only if it does not already exist:

~~~powershell
cd "04-terraform-packer-gcp"
ssh-keygen -t rsa -b 4096 -f .\tf-packer
~~~

This creates:

- `tf-packer`, the private key that stays on your computer
- `tf-packer.pub`, the public key that Packer installs in the image

The public key does not need to exist in a local `tmp` folder. The Packer file
provisioner reads `../tf-packer.pub` from your computer and uploads it to
`/tmp/tf-packer.pub` inside the temporary build VM.

Then the shell provisioner uploads `../scripts/setup.sh` and runs it inside that
VM. The script moves the public key from `/tmp` to the new user's
`authorized_keys` file.

Packer also needs SSH while it builds the image. The Google Compute builder
normally creates and uses a separate temporary SSH key for the Ubuntu build
user. That temporary build access is removed with the build VM. The
`terraform` user and your public key are baked into the finished image for this
lesson.

## 3. Prepare the Packer values

~~~powershell
cd images
Copy-Item variables.pkrvars.hcl.example variables.pkrvars.hcl
~~~

Open `variables.pkrvars.hcl` and replace `YOUR_PROJECT_ID` with your GCP project
ID. You can also change the zone.

The zone is a Packer input because Packer must choose where to create its
temporary build VM. Terraform has its own region and zone because it creates a
different VM later. They are two separate runs with separate inputs.

## 4. Build the image

Run these commands from the `images` folder:

~~~powershell
packer init .
packer fmt .
packer validate -var-file="variables.pkrvars.hcl" .
packer build -var-file="variables.pkrvars.hcl" .
~~~

Packer creates a temporary VM and boot disk in GCP, connects over SSH, runs the
provisioners, saves the disk as a custom image, and removes the temporary build
resources.

See the result in the GCP Console:

`Compute Engine` → `Storage` → `Images`

The image name begins with `learn-terraform-packer-`. Every build also joins
the `learn-terraform-packer` image family. Terraform uses the newest usable
image in that family, so you do not need to copy an image name by hand.

## 5. Prepare the Terraform values

Find your current public IPv4 address using a trusted service. Add `/32` to the
end. For example, address `203.0.113.10` becomes `203.0.113.10/32`.

Then run:

~~~powershell
cd ..\instances
Copy-Item terraform.tfvars.example terraform.tfvars
~~~

Open `terraform.tfvars` and set your project ID, region, zone, and current IP.

The `/32` value lets the SSH firewall rule accept only that one public IPv4
address. Terraform needs the same input during `destroy` because it must load
the complete configuration before it can work out what to remove. Keeping the
value in `terraform.tfvars` prevents Terraform from asking for it each time.

## 6. Create the final VM

Run these commands from the `instances` folder:

~~~powershell
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
~~~

Terraform prints the public IP, an SSH command, and the application URL.

## 7. Connect and run the application

Use the `ssh_command` output, or run:

~~~powershell
ssh -i ..\tf-packer terraform@VM_PUBLIC_IP
~~~

Inside the VM:

~~~bash
cd ~/learn-go-webapp-demo
go run webapp.go
~~~

Leave that command running. Open a browser on your computer and visit:

~~~text
http://VM_PUBLIC_IP:8080
~~~

For a quick test from another SSH window, use `curl http://localhost:8080`.
This lesson starts the app by hand so you can see what it does. A production
image would normally install a service that starts the app automatically.

## Costs and cleanup

This lesson can create billable GCP resources:

- Packer temporarily uses a VM, disk, and possibly network traffic.
- The custom image remains stored after the Packer build.
- Terraform creates a VM, boot disk, network, firewall rules, and an external
  IPv4 address.

Prices and free-tier rules can change, so check the current GCP pricing pages.

Destroy the Terraform resources from the `instances` folder:

~~~powershell
terraform destroy
~~~

This does not delete the Packer image. To remove it, open `Compute Engine` →
`Storage` → `Images`, select the `learn-terraform-packer-...` image, and choose
Delete. Only do this after destroying every VM that needs the image.

## A security note

Baking a personal SSH public key into an image is useful for this small lesson,
but it is not a good production pattern. Every VM made from the image gets the
same key. Real systems normally use OS Login, short-lived access, or a secret
management process instead.

The web port is open to the internet so you can test the demo. Do not put
private information in this application.

## Remember

- Packer builds images; Terraform deploys infrastructure from them.
- A Packer region or zone describes the image build, not the final architecture.
- A file provisioner uploads a local file; a shell provisioner runs inside the
  temporary build VM.
- `/tmp` is inside the Linux build VM, not a folder beside your Windows key.
- `terraform destroy` removes Terraform resources, not the Packer image.

## Official documentation

- [HashiCorp: provision infrastructure with Packer](https://developer.hashicorp.com/terraform/tutorials/provision/packer)
- [Packer Google Compute builder](https://developer.hashicorp.com/packer/integrations/hashicorp/googlecompute/latest/components/builder/googlecompute)
- [Google Cloud operating-system image families](https://cloud.google.com/compute/docs/images/os-details)
- [Packer file provisioner](https://developer.hashicorp.com/packer/docs/provisioners/file)
- [Packer shell provisioner](https://developer.hashicorp.com/packer/docs/provisioners/shell)
- [Terraform Google Compute instance](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_instance)
- [Google Cloud Application Default Credentials](https://cloud.google.com/docs/authentication/provide-credentials-adc)
- [Google Cloud image pricing](https://cloud.google.com/compute/disks-image-pricing#disk)
- [Google Cloud free program](https://cloud.google.com/free/docs/free-cloud-features)
