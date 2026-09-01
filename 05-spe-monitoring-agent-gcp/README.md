# Lesson 5: A complete learning SPE

This lesson starts with the same Packer and Terraform design as lesson 4:

1. Packer starts a temporary GCP VM.
2. Packer prepares a reusable image.
3. Terraform finds that image and creates the final VM.
4. I can administer the VM through SSH.

The final VM is a Secure Processing Environment, or SPE. The monitoring agent
is one component inside the SPE; it is not the whole VM.

This lesson adds five things to the image:

- A small Python monitoring agent managed by systemd.
- An XFCE desktop that Apache Guacamole can reach through RDP.
- A data workspace with JupyterLab, RStudio Desktop, and `hepatitis.csv`.
- A small administrator command for controlling new outbound internet access.
- Local operating-system and network audit logs in JSON Lines format.

Guacamole runs in Docker on my laptop. It is a web gateway: my browser talks
to Guacamole, and Guacamole talks to the SPE. I do not connect the browser
directly to RDP.

~~~text
browser -> Guacamole on my laptop -> RDP on port 3389 -> xrdp -> XFCE desktop
                                              |
                                              `-> SPE in GCP

Python agent -> standard output -> systemd journal -> journalctl

hepatitis.csv -> Jupyter notebook (Python)
              `-> RStudio project (R)

administrator -> spe-internet on|off|status -> Linux nftables output rules

login + programs + terminal input -> auditd -> Laurel -> os.jsonl
network connection metadata       -> Zeek             -> network.jsonl
~~~

This is a learning proof of concept. Guacamole is available only on my laptop,
and the RDP firewall accepts only the public IP address of that laptop.

At the end, I can sign in through Guacamole, read the same CSV in a Jupyter
notebook and RStudio, control new outbound internet connections, and inspect
the SPE's local audit trail.

## What Packer puts in the image

- Python 3.12 and the SPE monitoring agent.
- A systemd service that starts and restarts the agent.
- XFCE, a lightweight Linux desktop environment.
- xrdp and xorgxrdp, which provide an RDP server for the XFCE desktop.
- JupyterLab and pandas in a separate Python virtual environment.
- R and the open-source RStudio Desktop application.
- A small browser for opening JupyterLab inside the XFCE desktop.
- The hepatitis CSV, an example notebook, and an example RStudio project.
- `nftables` and the `spe-internet` administrator command.
- A systemd service that restores the selected internet mode after reboot.
- auditd and `pam_tty_audit` for logins, programs, and terminal input.
- Laurel for readable operating-system events in `os.jsonl`.
- Zeek for connection metadata in `network.jsonl`.
- Local log rotation for both JSONL outputs.
- `terraform`, the SSH administrator used in these lessons.
- `speuser`, the end user who signs in to the graphical desktop.

The `speuser` account has no working password in the image. After Terraform
creates the final VM, I set its password through SSH. This prevents a reusable
password from being copied into every VM made from the image. It also keeps the
password out of Git, Packer files, Terraform files, and Terraform state.

The Packer build VM and final SPE use `e2-medium`, which has 4 GB of memory.
XFCE is lightweight, but a graphical desktop needs more memory than the
`e2-micro` used earlier. Four GB is also enough for this small dataset and the
learning applications. The 30 GB boot disk has room for the desktop and data
tools. These resources can cost money.

## Files in this lesson

~~~text
05-spe-monitoring-agent-gcp/
|-- files/
|   |-- spe-jupyter
|   |-- spe-jupyter.desktop
|   |-- spe-internet
|   |-- spe-internet-allowlist.nft
|   |-- spe-internet-disabled.nft
|   |-- spe-internet-restore.service
|   |-- spe-audit-logrotate
|   |-- spe-audit.rules
|   |-- AUDIT-LOG-GUIDE.md
|   |-- spe-laurel.toml
|   |-- spe-network-audit
|   |-- spe-network-audit.service
|   |-- spe-network-audit.zeek
|   |-- spe-pam-tty-audit
|   |-- spe-monitoring-agent.py
|   |-- spe-monitoring-agent.service
|   `-- spe-rstudio.desktop
|-- data/
|   `-- hepatitis.csv
|-- environments/
|   |-- python/
|   |   `-- requirements.txt
|   `-- r/
|       `-- requirements.R
|-- examples/
|   |-- python/
|   |   `-- read-hepatitis.ipynb
|   `-- r/
|       |-- read-hepatitis.R
|       `-- spe-data-lab.Rproj
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
|   |-- setup-auditing.sh
|   |-- setup-data-tools.sh
|   |-- setup-internet-control.sh
|   `-- setup.sh
|-- tf-packer       # local private key; ignored by Git
`-- tf-packer.pub   # public key copied into the image; ignored by Git
~~~

`gateway/compose.yaml` starts the two official Guacamole containers. The web
application gives me the browser interface. `guacd` translates Guacamole's
instructions into RDP.

`gateway/user-mapping.xml.example` is a safe template for the local Guacamole
login and SPE connection. Its real copy is ignored by Git because it contains
the Guacamole password, the `speuser` password, and the current SPE address.

`environments/python/requirements.txt` pins the Python packages installed in
`/opt/spe-python`. This keeps notebook packages separate from Ubuntu's system
Python.

There is no single universal R equivalent of `requirements.txt`. For this
small example, `environments/r/requirements.R` records the minimum R version
and checks the environment. The R example uses `read.csv()`, which is already
included with R, so it does not download an extra R package. Later lessons can
add `install.packages()` calls to this file.

`scripts/setup-data-tools.sh` installs the data applications and builds this
user-owned workspace in the image:

~~~text
/home/speuser/spe-data-lab/
|-- data/hepatitis.csv
|-- environments/python/requirements.txt
|-- environments/r/requirements.R
|-- notebooks/read-hepatitis.ipynb
`-- r/
    |-- read-hepatitis.R
    `-- spe-data-lab.Rproj
~~~

JupyterLab and RStudio read the same CSV. The example contains 154 data rows
and 20 columns. Some cells are empty on purpose and appear as missing values.
The setup script pins the open-source RStudio Desktop installer version so a
build does not silently change to a different IDE release.

`files/spe-internet` is the small administrator command. It manages only the
`inet spe_egress` nftables table, so it does not replace or flush unrelated
firewall rules. `files/spe-internet-disabled.nft` contains the restricted
outbound policy. `files/spe-internet-allowlist.nft` is empty in this lesson and
provides one clear place for a future control-layer exception.

`files/spe-audit.rules` tells Linux Audit to record programs started by signed-
in users. `files/spe-pam-tty-audit` adds raw interactive terminal input so a
shell built-in such as `cd` is also visible. `files/spe-laurel.toml` converts
those audit events into `/var/log/spe-audit/os.jsonl`.

`files/spe-network-audit.zeek` asks Zeek to keep only connection summaries:
addresses, ports, protocol, duration, state, packet counts, and byte counts.
The small `spe-network-audit` launcher finds the VM's default network
interface. Its systemd service writes `/var/log/spe-audit/network.log`; the
friendlier `network.jsonl` name is a link to that file. `spe-audit-logrotate`
keeps the network output bounded, while Laurel rotates its own output.

`files/AUDIT-LOG-GUIDE.md` explains how to read these records and connect a
login session with terminal input and executed programs. It also explains how
to compare that operating-system timeline with Zeek's network timeline without
claiming that a connection belongs to a process when the logs cannot prove it.

For this small proof of concept, the gateway uses Guacamole's simple XML
authentication instead of adding a database. Apache describes this as useful
for small setup checks, not as a production authentication design.

## 1. Check the requirements

I need:

- The tools and GCP authentication from the repository's main README.
- A GCP project with billing and the Compute Engine API enabled.
- Docker Desktop running on my laptop for Guacamole.
- My laptop's current public IPv4 address.
- Internet access during the Packer build so the temporary VM can reach Ubuntu,
  PyPI, Posit's official RStudio download site, and the official Zeek package
  repository.

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

The temporary Packer VM is an `e2-medium` because installing and checking the
desktop and data tools needs more memory. The build can take several minutes
because it downloads JupyterLab, R, RStudio, a browser, and Zeek.
Packer deletes the temporary VM after a successful build. The resulting image
stays in GCP and belongs to the
`learn-spe-monitoring-agent` image family.

The final Packer provisioner also tests this lesson's internet command. It
turns access off, confirms a new HTTPS request fails while Packer's SSH session
remains connected, turns access on, and confirms HTTPS works again.

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

Create the final SPE:

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
- `SPE_DESKTOP_PASSWORD` with the password set by `sudo passwd speuser`.

These values are inside XML. For this temporary lesson, use passwords that do
not contain `<`, `>`, `&`, or XML attribute quotes unless those characters are
correctly escaped.

This gives the student one visible login. Guacamole checks the `student`
password, then sends the stored `speuser` credentials to xrdp when the
connection opens.

This is simple credential forwarding, not true single sign-on. True SSO lets
both systems trust the same identity provider. Here, Guacamole stores a second
password in plaintext and submits it for me. I use this only for the local
learning proof of concept and never commit `user-mapping.xml` to Git.

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

Open **SPE desktop**. Guacamole sends the stored `speuser` credentials to
xrdp, so the XFCE desktop should open without asking for a second login.

Guacamole is only the gateway. The XFCE desktop and the end-user session run
inside the GCP VM.

## 8. Find the shared data workspace

Inside the XFCE desktop, open **Applications** -> **Terminal Emulator** and run:

~~~bash
cd ~/spe-data-lab
find . -maxdepth 2 -type f | sort
~~~

I should see the CSV, notebook, R script, RStudio project, and both environment
files. Both tools use this one workspace owned by `speuser`, so I can save
changes made during the lesson.

## 9. Read the CSV in a Jupyter notebook

From the XFCE application menu, open **Development** -> **SPE JupyterLab**.
A terminal starts the Jupyter process, then the browser opens inside the SPE.

If the menu entry is not visible yet, run this in the XFCE terminal:

~~~bash
spe-jupyter
~~~

Jupyter prints a URL containing a temporary token. If the browser does not
open automatically, copy the complete `http://127.0.0.1:8888/lab?...` URL from
the terminal and paste it into the browser inside the XFCE desktop.

In JupyterLab:

1. Open `notebooks`.
2. Open `read-hepatitis.ipynb`.
3. Select **Run** -> **Run All Cells**.

The notebook displays the first rows, reports 154 rows and 20 columns, and
counts the missing values. `pandas.read_csv()` performs the CSV read.

Jupyter listens on `127.0.0.1` inside the SPE. It is not exposed through a new
GCP firewall rule. Remember that this is different from `127.0.0.1:8081` on
the laptop, where Guacamole runs.

To stop Jupyter, return to its terminal, press `Ctrl+C`, and confirm with `y`.
Closing only the browser tab does not stop the Jupyter process.

## 10. Read the CSV in RStudio

From the XFCE application menu, open **Development** -> **SPE RStudio Data
Lab**. The launcher opens the prepared `spe-data-lab.Rproj` project.
It disables GPU acceleration because this graphical session is rendered over
xrdp rather than by a physical GPU.

If the menu entry is not visible, run this in the XFCE terminal:

~~~bash
rstudio --disable-gpu ~/spe-data-lab/r/spe-data-lab.Rproj
~~~

In RStudio:

1. Open `read-hepatitis.R` from the **Files** pane.
2. Click **Source** above the script.
3. Look at the Console output.
4. Select the `hepatitis` object in the **Environment** pane to reopen the
   spreadsheet-style data viewer if needed.

The script uses base R's `read.csv()` function. It reports 154 rows and 20
columns, prints the first rows, counts missing values, and opens the data
viewer. No additional R package is needed for this first example.

## 11. Control outbound internet access

The SPE starts with internet access enabled. Through SSH, confirm the current
mode and make a new request:

~~~bash
sudo spe-internet status
curl --head --connect-timeout 5 https://example.com
~~~

The status should say `Internet access: enabled`, and `curl` should return HTTP
headers. Now disable new general outbound connections:

~~~bash
sudo spe-internet off
sudo spe-internet status
curl --head --connect-timeout 5 https://example.com
~~~

The status should say `Internet access: disabled`, and the new `curl` request
should fail. The current SSH connection remains open because reply traffic is
allowed. To make the management test stronger, I open a second PowerShell
window on my laptop and run the Terraform SSH output again. A new inbound SSH
connection should still work:

~~~powershell
terraform output -raw ssh_command
~~~

Enable outbound internet access again and repeat the request:

~~~bash
sudo spe-internet on
sudo spe-internet status
curl --head --connect-timeout 5 https://example.com
~~~

To prove that the selected mode survives reboot, I disable it, reboot, and
reconnect from the laptop:

~~~bash
sudo spe-internet off
sudo reboot
~~~

After reconnecting through SSH:

~~~bash
sudo spe-internet status
curl --head --connect-timeout 5 https://example.com
~~~

The status should show effective mode `disabled` and saved mode `off`, and the
request should fail. I can finish the exercise online with:

~~~bash
sudo spe-internet on
~~~

The disabled policy still allows loopback traffic, replies belonging to SSH or
RDP connections, DHCP renewal, and GCP's metadata address
`169.254.169.254`. It does not change Terraform's inbound GCP firewall rules.

For a future control-layer proof of concept, an administrator can place a
narrow nftables rule in `/etc/spe-internet/allowlist.nft`, for example one
fixed IPv4 address and TCP port. Running `sudo spe-internet off` validates and
atomically reapplies the policy. This lesson does not add such an exception or
the external service yet.

There is no Terraform variable for this mode. Every new SPE starts online, and
the command manages its runtime state from then on. This avoids making every
`terraform apply` overwrite an administrator's saved choice.

## 12. Verify local auditing

The two audit outputs are:

~~~text
/var/log/spe-audit/os.jsonl       login, logout, programs, and terminal input
/var/log/spe-audit/network.jsonl  network connection summaries
~~~

Each line is one JSON object. The files are not writable by `speuser`. I use
the `terraform` administrator and `sudo` to inspect them.

For a field-by-field explanation, including how to recognize automatic `cron`
events and match login, TTY, program, and network records, see
[`files/AUDIT-LOG-GUIDE.md`](files/AUDIT-LOG-GUIDE.md).

First, check the collectors through SSH:

~~~bash
sudo systemctl is-active auditd
sudo systemctl is-active spe-network-audit
sudo pgrep --list-full laurel
~~~

All three checks should show a running collector. Laurel runs as an auditd
plug-in, so it does not have a separate systemd service.

Now create a small, easy-to-recognize trail as the researcher:

1. Sign in to **SPE desktop** through Guacamole as described above.
2. Open **Terminal Emulator**.
3. Run a shell built-in and a few external programs:

~~~bash
cd ~/spe-data-lab
pwd
python3 --version
curl --head --connect-timeout 5 https://example.com
~~~

`cd` is a shell built-in, so no new program starts for that command. Its raw
terminal input is covered by `pam_tty_audit`. The other commands are programs
and are covered by the `execve` audit rules. The `curl` request also creates a
network connection for Zeek to summarize.

Close the terminal and use the XFCE menu to log out of the desktop. This ends
the researcher session and creates the logout event. Reconnect through SSH as
the `terraform` administrator and inspect the records:

~~~bash
sudo jq 'select(.USER_LOGIN or .USER_START or .USER_END or .USER_LOGOUT)' \
  /var/log/spe-audit/os.jsonl
sudo jq 'select(.EXECVE)' /var/log/spe-audit/os.jsonl
sudo jq 'select(.TTY)' /var/log/spe-audit/os.jsonl
sudo tail -n 10 /var/log/spe-audit/network.jsonl | jq .
~~~

The exact login field depends on the program that opened the session. I should
see login/start and end/logout records, `EXECVE.ARGV` arrays for external
programs, a `TTY.data` value containing the terminal input, and a network JSON
object similar to:

~~~json
{"ts":1787754601.25,"uid":"Cexample123","id.orig_h":"10.0.0.2","id.orig_p":43210,"id.resp_h":"93.184.216.34","id.resp_p":443,"proto":"tcp","duration":0.12,"orig_bytes":80,"resp_bytes":300,"conn_state":"SF","orig_pkts":6,"resp_pkts":5,"orig_ip_bytes":400,"resp_ip_bytes":560}
~~~

Zeek writes a connection summary when the connection closes or expires, so a
still-open connection may not appear immediately. I can follow new events in
two SSH windows:

~~~bash
sudo tail -F /var/log/spe-audit/os.jsonl | jq --unbuffered .
sudo tail -F /var/log/spe-audit/network.jsonl | jq --unbuffered .
~~~

Press `Ctrl+C` to stop following a file. This does not stop collection.

Finally, reboot and confirm collection resumes automatically:

~~~bash
sudo reboot
~~~

After reconnecting:

~~~bash
sudo systemctl is-active auditd
sudo systemctl is-active spe-network-audit
sudo tail -n 1 /var/log/spe-audit/os.jsonl | jq .
sudo tail -n 1 /var/log/spe-audit/network.jsonl | jq .
~~~

Laurel rotates `os.jsonl` at 10 MB and keeps five older files. `logrotate` does
the same for Zeek's network output and compresses older copies. auditd's raw
safety log is also limited to five 10 MB files.

## 13. Verify the monitoring agent

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

## 14. Check automatic startup

Reboot the SPE from SSH:

~~~bash
sudo reboot
~~~

After it starts again, reconnect through SSH and verify:

~~~bash
sudo systemctl is-active xrdp
sudo systemctl is-active spe-monitoring-agent
sudo systemctl is-active spe-internet-restore
sudo systemctl is-active auditd
sudo systemctl is-active spe-network-audit
~~~

All five services should say `active`. The desktop password remains on the VM,
so the same Guacamole connection works after a normal reboot.

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

Then place the same new password in the `password` connection parameter in
`gateway/user-mapping.xml`. Guacamole reloads changes to this file
automatically. Close the failed connection and open **SPE desktop** again.

If the blue xrdp login screen still appears, check that the connection contains
both of these parameters and that the password is current:

~~~xml
<param name="username">speuser</param>
<param name="password">SPE_DESKTOP_PASSWORD</param>
~~~

If JupyterLab does not start, open the XFCE terminal and run:

~~~bash
/opt/spe-python/bin/jupyter lab --version
/opt/spe-python/bin/python -c "import pandas; print(pandas.__version__)"
spe-jupyter
~~~

Keep the terminal open while using JupyterLab. If it prints an address instead
of opening the browser, copy the complete address into the browser inside the
SPE desktop.

If RStudio does not start, check R and RStudio from the XFCE terminal:

~~~bash
R --version
rstudio --version
rstudio --disable-gpu ~/spe-data-lab/r/spe-data-lab.Rproj
~~~

If either tool says the CSV is missing, verify that this exact file exists:

~~~bash
ls -l ~/spe-data-lab/data/hepatitis.csv
~~~

If `spe-internet off` reports a rule error, inspect the dedicated rules and
allow-list files. The command checks them before replacing an active policy:

~~~bash
sudo nft --check --file /etc/spe-internet/disabled.nft
sudo cat /etc/spe-internet/allowlist.nft
sudo spe-internet status
~~~

If the effective and saved modes do not match after an unexpected manual
firewall change, restore the saved choice with:

~~~bash
sudo systemctl restart spe-internet-restore
sudo spe-internet status
~~~

If operating-system audit events are missing, check the service, Laurel plug-
in, loaded rules, and PAM include:

~~~bash
sudo systemctl status auditd
sudo pgrep --list-full laurel
sudo auditctl -l
grep -F '@include spe-tty-audit' /etc/pam.d/common-session
sudo ausearch -k spe_cli --start recent
~~~

TTY auditing starts when a new PAM session opens. Log out and sign in again if
the session was already open when the configuration changed.

If network events are missing, check the service and the interface it selected:

~~~bash
sudo systemctl status spe-network-audit
sudo journalctl -u spe-network-audit --since today
ip -4 route show default
sudo ls -l /var/log/spe-audit/network*
~~~

Finish a short connection such as `curl https://example.com` and wait a few
seconds. A connection that is still open is not yet a complete Zeek summary.

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
- The real `user-mapping.xml` stores both passwords in plaintext on the laptop
  so Guacamole can forward the desktop credentials. It is ignored by Git.
- Guacamole listens only on the laptop's loopback address, not the local
  network or public internet.
- GCP allows RDP only from `rdp_source_cidr`, not `0.0.0.0/0`.
- `guacd` is not published as a host port.
- The xrdp certificate is self-signed, so this proof of concept tells
  Guacamole to accept it. A production design needs proper certificate and
  identity management.
- Guacamole's XML authentication is for this local proof of concept, not a
  public or production gateway.
- JupyterLab listens only inside the VM on `127.0.0.1`; port 8888 is not opened
  in the GCP firewall.
- Packer stores `hepatitis.csv` in the reusable image. Every VM made from that
  image receives a copy. Only use learning data here; never bake confidential,
  identifiable patient, credential, or secret data into an image.
- Internet mode `off` blocks new general outbound connections inside the guest
  operating system. It does not terminate connections that were already open.
- The policy deliberately keeps GCP's metadata address reachable for the guest
  environment. This is useful for VM health, but it means `off` is not complete
  network isolation.
- A root administrator can change or bypass a firewall inside the VM. A
  production boundary should also use centrally managed cloud egress controls.
- This proof of concept owns one nftables table. Do not add another service
  that flushes the full nftables ruleset without first integrating the two.
- The audit files stay on the VM. A root administrator can alter or delete
  them, and deleting the boot disk deletes the evidence. This proof of concept
  is not tamper-evident or a replacement for protected off-VM audit storage.
- `auditd` records external programs and their arguments. `pam_tty_audit`
  records raw terminal input, including typing mistakes and control keys, but
  not terminal output or a replayable desktop session.
- `log_passwd` is deliberately not enabled, so input entered while terminal
  echo is disabled is not intentionally recorded. Linux PAM warns that some
  nested or remote password prompts can still be captured. Do not type real
  secrets in an audited learning terminal.
- Zeek records addresses, ports, state, duration, packets, and bytes on the
  default VM interface. It does not store packet payloads and does not tell us
  which local user or process owns a connection.
- Local rotation limits growth, but an unusually busy SPE can rotate old audit
  history quickly. Production retention must be sized and protected centrally.

## Remember

- The SPE is the VM. The monitoring agent is one service inside it.
- XFCE draws the Linux desktop; xrdp exposes it through RDP.
- Guacamole changes RDP into a browser-accessible experience.
- JupyterLab and RStudio are applications inside the SPE desktop, not services
  exposed to the internet.
- Both examples read one shared CSV from `~/spe-data-lab/data`.
- Python packages live in `/opt/spe-python`; R uses its base CSV functions.
- `spe-internet` controls new outbound connections without changing inbound
  SSH or RDP rules.
- The saved internet mode is reapplied by systemd after reboot.
- auditd and `pam_tty_audit` collect login and command-line activity; Laurel
  makes those events readable JSON Lines.
- Zeek writes network connection metadata, not packet contents.
- Researchers cannot modify the two audit outputs as their normal user; the
  administrator inspects them with `sudo`.
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
- [JupyterLab installation and startup](https://jupyterlab.readthedocs.io/en/stable/getting_started/installation.html)
- [Python virtual environments](https://docs.python.org/3/library/venv.html)
- [pandas CSV reader](https://pandas.pydata.org/docs/reference/api/pandas.read_csv.html)
- [RStudio Desktop downloads](https://docs.posit.co/ide/user/)
- [R `read.csv()` documentation](https://stat.ethz.ch/R-manual/R-devel/library/utils/html/read.table.html)
- [nftables scripting](https://wiki.netfilter.org/wiki-nftables/index.php/Scripting)
- [nftables command reference](https://netfilter.org/projects/nftables/manpage.html)
- [GCP metadata server](https://cloud.google.com/compute/docs/metadata/querying-metadata)
- [Ubuntu auditd package](https://packages.ubuntu.com/noble/auditd)
- [Ubuntu Laurel manual](https://manpages.ubuntu.com/manpages/noble/man8/laurel.8.html)
- [Ubuntu `pam_tty_audit` manual](https://manpages.ubuntu.com/manpages/noble/man8/pam_tty_audit.8.html)
- [Zeek installation](https://docs.zeek.org/en/lts/install.html)
- [Zeek connection log](https://docs.zeek.org/en/lts/logs/conn.html)
