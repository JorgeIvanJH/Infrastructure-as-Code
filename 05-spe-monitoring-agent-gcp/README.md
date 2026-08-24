# Lesson 5: An SPE with monitoring and graphical access

This lesson starts with the same Packer and Terraform design as lesson 4:

1. Packer starts a temporary GCP VM.
2. Packer prepares a reusable image.
3. Terraform finds that image and creates the final VM.
4. I can administer the VM through SSH.

The final VM is a Secure Processing Environment, or SPE. The monitoring agent
is one component inside the SPE; it is not the whole VM.

This lesson adds two things to the image:

- A small Python monitoring agent managed by systemd.
- An XFCE desktop that Apache Guacamole can reach through RDP.

Guacamole runs in Docker on my laptop. It is a web gateway: my browser talks
to Guacamole, and Guacamole talks to the SPE. I do not connect the browser
directly to RDP.

~~~text
browser -> Guacamole on my laptop -> RDP on port 3389 -> xrdp -> XFCE desktop
                                              |
                                              `-> SPE in GCP

Python agent -> standard output -> systemd journal -> journalctl
~~~

This is a learning proof of concept. Guacamole is available only on my laptop,
and the RDP firewall accepts only the public IP address of that laptop.

## What Packer puts in the image

- Python 3.12 and the SPE monitoring agent.
- A systemd service that starts and restarts the agent.
- XFCE, a lightweight Linux desktop environment.
- xrdp and xorgxrdp, which provide an RDP server for the XFCE desktop.
- `terraform`, the SSH administrator used in these lessons.
- `speuser`, the end user who signs in to the graphical desktop.

The `speuser` account has no working password in the image. After Terraform
creates the final VM, I set its password through SSH. This prevents a reusable
password from being copied into every VM made from the image. It also keeps the
password out of Git, Packer files, Terraform files, and Terraform state.

The Packer build VM and final SPE use `e2-medium`, which has 4 GB of memory.
XFCE is lightweight, but a graphical desktop needs more memory than the
`e2-micro` used earlier. The 30 GB boot disk also has room for the desktop
packages. These resources can cost money.

## Files in this lesson

~~~text
05-spe-monitoring-agent-gcp/
|-- files/
|   |-- spe-monitoring-agent.py
|   `-- spe-monitoring-agent.service
|-- gateway/
|   |-- compose.yaml
|   `-- user-mapping.xml.example
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

`gateway/compose.yaml` starts the two official Guacamole containers. The web
application gives me the browser interface. `guacd` translates Guacamole's
instructions into RDP.

`gateway/user-mapping.xml.example` is a safe template for the local Guacamole
login and SPE connection. Its real copy is ignored by Git because it contains
a local password and the current SPE address.

For this small proof of concept, the gateway uses Guacamole's simple XML
authentication instead of adding a database. Apache describes this as useful
for small setup checks, not as a production authentication design.

## 1. Check the requirements

I need:

- The tools and GCP authentication from the repository's main README.
- A GCP project with billing and the Compute Engine API enabled.
- Docker Desktop running on my laptop for Guacamole.
- My laptop's current public IPv4 address.

I can check that Docker is ready with:

~~~powershell
docker version
docker compose version
~~~

## 2. Prepare the SSH key and Packer values

From the repository root:

~~~powershell
cd "05-spe-monitoring-agent-gcp"
ssh-keygen -t rsa -b 4096 -f .\tf-packer
cd images
Copy-Item variables.pkrvars.hcl.example variables.pkrvars.hcl
~~~

Do not run `ssh-keygen` over a key that I still use. If `tf-packer` already
exists, I reuse it.

Open `variables.pkrvars.hcl` and replace `YOUR_PROJECT_ID`. The private SSH key
stays on my laptop. Packer copies only `tf-packer.pub` into the image.

## 3. Build the SPE image

From the `images` folder:

~~~powershell
packer init .
packer fmt .
packer validate -var-file="variables.pkrvars.hcl" .
packer build -var-file="variables.pkrvars.hcl" .
~~~

The temporary Packer VM is an `e2-medium` because installing and checking a
desktop needs more memory. Packer deletes that temporary VM after a successful
build. The resulting image stays in GCP and belongs to the
`learn-spe-monitoring-agent` image family.

I can see it in the GCP Console under:

`Compute Engine` -> `Storage` -> `Images`

## 4. Prepare and create the final SPE

Find the public IPv4 address used by my laptop and add `/32`. For example,
`203.0.113.10` becomes `203.0.113.10/32`.

~~~powershell
cd ..\instances
Copy-Item terraform.tfvars.example terraform.tfvars
~~~

Open `terraform.tfvars` and set the project, location, and both CIDR values.
When SSH and Guacamole run from the same laptop, the two values are normally
the same:

~~~hcl
ssh_source_cidr = "203.0.113.10/32"
rdp_source_cidr = "203.0.113.10/32"
~~~

The first firewall rule allows SSH on TCP port 22. The second allows RDP on TCP
port 3389. Both use `/32`, so they accept one public address instead of the
whole internet. The RDP rule applies only to the VM with the `rdp` network tag.

If an older version of this lesson is still running, destroy it before creating
this fresh version. Then run:

~~~powershell
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
~~~

Read the plan before approving it. Terraform creates an `e2-medium` VM named
`spe-demo-001` from the newest image in the family.

## 5. Set the desktop user's password

Get and run the SSH command:

~~~powershell
terraform output -raw ssh_command
~~~

Inside the SPE, set a new password for the graphical end user:

~~~bash
sudo passwd speuser
~~~

The command asks for the new password twice. It does not display the password
while I type. This password exists only on this final VM. `speuser` is not a
sudo administrator.

Check the graphical services:

~~~bash
sudo systemctl status xrdp
sudo systemctl is-enabled xrdp
~~~

The service should be active and enabled. Type `q` to leave the status view.

## 6. Configure the local Guacamole gateway

Return to PowerShell on the laptop. Get the SPE's current public IP:

~~~powershell
terraform output -raw public_ip
cd ..\gateway
Copy-Item user-mapping.xml.example user-mapping.xml
~~~

Open `user-mapping.xml` and replace:

- `CHANGE_ME` with a new password for the local Guacamole web page.
- `SPE_PUBLIC_IP` with the value from the Terraform output.

Because this value is inside XML, avoid the characters `<`, `>`, `&`, and
quotes in this temporary learning password unless they are correctly escaped.

The template deliberately does not store the `speuser` password. I enter that
password in the xrdp login screen when I open the desktop.

Start the gateway:

~~~powershell
docker compose up -d
docker compose ps
~~~

I can also check the complete network path from the laptop to xrdp:

~~~powershell
$speIp = terraform -chdir=..\instances output -raw public_ip
Test-NetConnection $speIp -Port 3389
~~~

`TcpTestSucceeded` should be `True`.

Only the Guacamole web application is published, at `127.0.0.1:8081`. Port
8081 avoids common conflicts with other local applications that use 8080. The
`guacd` RDP proxy remains inside the private Docker network.

## 7. Open the SPE desktop

Open this address in a browser on the laptop:

~~~text
http://127.0.0.1:8081/guacamole/
~~~

Sign in with:

- Username: `student`
- Password: the Guacamole password placed in `user-mapping.xml`

Open **SPE desktop**. At the blue xrdp login screen, use:

- Session: `Xorg`
- Username: `speuser`
- Password: the password set with `sudo passwd speuser`

Guacamole is only the gateway. The XFCE desktop and the end-user session run
inside the GCP VM.

## 8. Verify the monitoring agent

The graphical additions do not change the heartbeat. Through SSH, run:

~~~bash
sudo systemctl status spe-monitoring-agent
sudo journalctl -u spe-monitoring-agent -f
~~~

Every 30 seconds, the journal should show a heartbeat like:

~~~json
{"spe_id":"spe-demo-001","timestamp":"2026-08-24T14:30:00Z","message":"SPE monitoring agent is alive"}
~~~

Press `Ctrl+C` to stop following the journal. This does not stop the agent.

## 9. Check automatic startup

Reboot the SPE from SSH:

~~~bash
sudo reboot
~~~

After it starts again, reconnect through SSH and verify:

~~~bash
sudo systemctl is-active xrdp
sudo systemctl is-active spe-monitoring-agent
~~~

Both services should say `active`. The desktop password remains on the VM, so
the same Guacamole connection works after a normal reboot.

## Troubleshooting

If SSH says `REMOTE HOST IDENTIFICATION HAS CHANGED`, stop and first ask why.
When I deliberately destroy and recreate a VM, GCP can assign the same public
IP to a different VM. The new VM has new SSH host keys, while my laptop still
remembers the keys that belonged to the old VM.

If I know the VM was recreated, I confirm its current Terraform address and
remove only that address's old SSH record:

~~~powershell
$speIp = terraform output -raw public_ip
ssh-keygen -R $speIp
ssh -i ..\tf-packer "terraform@$speIp"
~~~

SSH asks me to trust the new key. If the fingerprint is the same one shown in
my immediately preceding connection attempt, I enter `yes`. If I did not
recreate the VM, or the fingerprint changes again unexpectedly, I do not
connect until I investigate. `ssh-keygen -R` keeps a backup named
`known_hosts.old`.

If Guacamole does not open, run this from the `gateway` folder:

~~~powershell
docker compose ps
docker compose logs guacamole
~~~

Check that `user-mapping.xml` exists and contains valid XML.

If the desktop connection times out, check:

- The SPE public IP in `user-mapping.xml` matches `terraform output public_ip`.
- `rdp_source_cidr` matches the laptop's current public IPv4 address plus `/32`.
- `sudo systemctl status xrdp` says the service is active.
- The GCP VM has the `rdp` network tag.

Home internet addresses can change. If mine changes, I update
`rdp_source_cidr` and run `terraform apply` again. I do not change the Packer
image for a firewall address change.

If xrdp rejects the login, reconnect with SSH and set the password again:

~~~bash
sudo passwd speuser
~~~

## Cleanup

Stop the local gateway from the `gateway` folder:

~~~powershell
docker compose down
~~~

Destroy the GCP resources from the `instances` folder:

~~~powershell
cd ..\instances
terraform destroy
~~~

Terraform does not delete the Packer image. Delete the
`learn-spe-monitoring-agent-...` image separately from `Compute Engine` ->
`Storage` -> `Images` when it is no longer needed.

## Security boundaries in this lesson

- No private SSH key or desktop password is stored in the image.
- The real `user-mapping.xml` is ignored by Git.
- Guacamole listens only on the laptop's loopback address, not the local
  network or public internet.
- GCP allows RDP only from `rdp_source_cidr`, not `0.0.0.0/0`.
- `guacd` is not published as a host port.
- The xrdp certificate is self-signed, so this proof of concept tells
  Guacamole to accept it. A production design needs proper certificate and
  identity management.
- Guacamole's XML authentication is for this local proof of concept, not a
  public or production gateway.

## Remember

- The SPE is the VM. The monitoring agent is one service inside it.
- XFCE draws the Linux desktop; xrdp exposes it through RDP.
- Guacamole changes RDP into a browser-accessible experience.
- Packer installs the reusable software. Terraform creates the network,
  firewall rules, and final SPE.
- A runtime password is safer than baking one into a reusable image.
- RDP port 3389 is reachable only from the configured gateway address.

## Official documentation

- [Apache Guacamole: introduction](https://guacamole.apache.org/doc/1.6.0/gug/introduction.html)
- [Apache Guacamole with Docker](https://guacamole.apache.org/doc/1.6.0/gug/guacamole-docker.html)
- [Apache Guacamole XML authentication](https://guacamole.apache.org/doc/1.6.0/gug/configuring-guacamole.html#user-mapping)
- [Apache Guacamole RDP settings](https://guacamole.apache.org/doc/1.6.0/gug/configuring-guacamole.html#rdp)
- [Ubuntu 24.04 XFCE package](https://packages.ubuntu.com/noble/all/xfce4)
- [Ubuntu 24.04 xrdp package](https://packages.ubuntu.com/noble/xrdp)
- [Google Cloud VPC firewall rules](https://cloud.google.com/firewall/docs/firewalls)
