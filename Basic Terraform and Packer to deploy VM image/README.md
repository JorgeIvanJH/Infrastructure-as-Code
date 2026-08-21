Packer vs Ansible in 1 sentence: Packer creates golden image to setup VMs from build, Ansible configures VMs running already, so use packer if you dont mind deleting and recreating instances, and use ansible to fix/patch existing VMs.


# Provision infrastructure with Packer following [this guide](https://developer.hashicorp.com/terraform/tutorials/provision/packer)


Terraform configuration for a compute instance can use a Packer image to provision your instance without manual configuration.

In this tutorial, you will create a Packer image with a user group, a new user with authorized SSH keys, and a Go web app. Then, you will deploy this image using Terraform. Finally, you will access the instance via SSH to deploy the Go web app.


cloned: git clone -b packer https://github.com/hashicorp-education/learn-terraform-provisioning

From this directory, create the local SSH key in the cloned
`learn-terraform-provisioning` repository:

```powershell
ssh-keygen -t rsa -b 4096 -f ".\learn-terraform-provisioning\tf-packer"
```

This creates the following files on your Windows host:

- `learn-terraform-provisioning\tf-packer` — the private key; keep it local and
  never commit it to Git.
- `learn-terraform-provisioning\tf-packer.pub` — the public key Packer copies
  into the image.

The public key should not be in a local `tmp` directory. During the build, the
file provisioner in `images\image.pkr.hcl` copies the host file
`tf-packer.pub` to `/tmp/tf-packer.pub` inside Packer's temporary Linux build
instance. The `scripts\setup.sh` script then installs it as
`/home/terraform/.ssh/authorized_keys`.

## build block 

the build block on [packer's template](learn-terraform-provisioning/images/image.pkr.hcl) copies the ssh's .pub file into the temporary vm and executes the shell script. though packer runs locally in this laptop's CLI, depending on the provider things can run instead on the VM used to create the image, in the case of  provisioner "shell", that one executes in the temporary VM.

## Run and access the Go application

After Terraform creates the VM, connect from the `instances` directory:

```powershell
terraform output -raw ssh_command
ssh -i ..\tf-packer terraform@$(terraform output -raw public_ip)
```

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
