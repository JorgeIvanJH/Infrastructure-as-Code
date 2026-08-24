# Lesson 5: A small SPE monitoring agent

This lesson uses the same design as lesson 4:

1. Packer starts a temporary GCP VM.
2. Packer prepares a reusable image.
3. Terraform finds that image and creates the final VM.
4. I connect to the VM through SSH.

The only new workload is a small Python program managed by systemd. There is
no IRIS integration, HTTP receiver, metrics platform, OpenTelemetry
integration, or control layer yet.

## What the proof of concept does

Every 30 seconds the agent writes one JSON heartbeat to standard output:

~~~json
{"spe_id":"spe-demo-001","timestamp":"2026-08-24T14:30:00Z","message":"SPE monitoring agent is alive"}
~~~

systemd captures standard output and puts it in the journal.

~~~text
Python agent -> standard output -> systemd journal -> journalctl
~~~

The program uses only the Python standard library. It does not send anything
over the network.

## New files

- `files/spe-monitoring-agent.py` creates and prints the heartbeat.
- `files/spe-monitoring-agent.service` tells systemd how to run and restart the
  program.
- `scripts/setup.sh` installs Python, the SSH key, the agent, and the service in
  the temporary build VM.
- `images/image.pkr.hcl` copies those files and creates the GCP image.
- `images/variables.pkrvars.hcl.example` provides safe example Packer values.
- `instances/main.tf` creates an SSH-accessible VM from the newest image in the
  `learn-spe-monitoring-agent` family.
- `instances/variables.tf` defines and validates the Terraform inputs.
- `instances/terraform.tfvars.example` provides safe example Terraform values.
- `instances/.terraform.lock.hcl` records the selected Google provider version.

The local `tf-packer` key and real variable files are ignored by Git. The
private key is never copied into the image. Only its public half is installed.

## Where the files go in the image

~~~text
/opt/spe-agent/spe-monitoring-agent.py
/etc/systemd/system/spe-monitoring-agent.service
~~~

The service runs as the existing `terraform` Linux user. It runs Python with
`-u`, which disables output buffering, and uses `Restart=on-failure`.

## 1. Prepare local access and values

Complete lesson 4 first, or create a local SSH key in this lesson folder:

~~~powershell
cd "05-spe-monitoring-agent-gcp"
ssh-keygen -t rsa -b 4096 -f .\tf-packer
~~~

Do not run `ssh-keygen` over an existing key that you still use.

Create the local Packer values:

~~~powershell
cd images
Copy-Item variables.pkrvars.hcl.example variables.pkrvars.hcl
~~~

Replace `YOUR_PROJECT_ID` in `variables.pkrvars.hcl`.

## 2. Build the image

From the `images` folder:

~~~powershell
packer init .
packer fmt .
packer validate -var-file="variables.pkrvars.hcl" .
packer build -var-file="variables.pkrvars.hcl" .
~~~

The image name begins with `learn-spe-monitoring-agent-` and belongs to the
`learn-spe-monitoring-agent` image family.

## 3. Create the VM

Prepare the Terraform values:

~~~powershell
cd ..\instances
Copy-Item terraform.tfvars.example terraform.tfvars
~~~

Set the project, region, zone, and your current public IPv4 address followed by
`/32`. Then run:

~~~powershell
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
~~~

This lesson uses its own image family, network, firewall, and VM names, so it
does not collide with lesson 4.

## 4. Verify the agent

Use the `ssh_command` output to connect:

~~~powershell
terraform output -raw ssh_command
~~~

Inside the VM, check the service:

~~~bash
sudo systemctl status spe-monitoring-agent
sudo journalctl -u spe-monitoring-agent -f
~~~

The second command follows the journal. A new heartbeat should appear every 30
seconds. Press `Ctrl+C` to stop following the journal; this does not stop the
agent.

Check that it starts at boot:

~~~bash
sudo systemctl is-enabled spe-monitoring-agent
sudo reboot
~~~

Reconnect after the VM boots and run the status and journal commands again.

Check automatic recovery by killing only the running process:

~~~bash
sudo systemctl kill --kill-whom=main --signal=SIGKILL spe-monitoring-agent
sudo systemctl status spe-monitoring-agent
sudo journalctl -u spe-monitoring-agent -n 10
~~~

systemd should start a new process after five seconds. `systemctl stop` is
different: systemd understands that as an intentional administrator request,
so it does not restart the service until it is started again.

## SPE ID

The program reads `SPE_ID` from its environment. If it is not set, the ID is
`spe-demo-001`. This first proof of concept deliberately uses the default. A
later lesson can decide how each VM should receive its own value.

## Cleanup

From the `instances` folder:

~~~powershell
terraform destroy
~~~

Terraform does not delete the Packer image. Delete the
`learn-spe-monitoring-agent-...` image separately from `Compute Engine` →
`Storage` → `Images` when it is no longer needed.

## Remember

- Packer installs the program and service into the image.
- `systemctl enable` makes the service start on future boots.
- systemd captures the program's standard output in the journal.
- `Restart=on-failure` restarts a crashed or killed process.
- The agent has no network integration and contains no secrets.

## Further reading

- [Python environment variables](https://docs.python.org/3/library/os.html#os.getenv)
- [Python date and time types](https://docs.python.org/3/library/datetime.html)
- [systemd service units](https://www.freedesktop.org/software/systemd/man/255/systemd.service.html)
- [journalctl](https://www.freedesktop.org/software/systemd/man/255/journalctl.html)
