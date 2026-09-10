the researcher works inside an XFCE desktop reached through Guacamole and RDP. these three files put the two data tools, JupyterLab and RStudio, one click away in that desktop's application menu, already pointed at the example workspace.

`spe-jupyter` is a small launcher: it moves into the workspace, `~/spe-data-lab` unless `SPE_DATA_WORKSPACE` says otherwise, and starts JupyterLab from the SPE's own python environment in `/opt/spe-python`, listening on `127.0.0.1` only, with the workspace as its root. it opens in a terminal on purpose, so the URL and token JupyterLab prints are visible if the browser does not open by itself. the two `.desktop` files are standard freedesktop menu entries: XFCE reads them from `/usr/share/applications` and shows them as **SPE JupyterLab** and **SPE RStudio Data Lab**. RStudio needs no launcher script, its entry calls `rstudio` directly with the example project.

# where each file lands on the VM

| here | on the VM | what it is |
|---|---|---|
| `spe-jupyter` | `/usr/local/bin/spe-jupyter` | launcher. `cd` into the workspace and `exec` JupyterLab from `/opt/spe-python`, bound to localhost, browser `epiphany` |
| `spe-jupyter.desktop` | `/usr/share/applications/spe-jupyter.desktop` | menu entry **SPE JupyterLab**, runs the launcher in a terminal |
| `spe-rstudio.desktop` | `/usr/share/applications/spe-rstudio.desktop` | menu entry **SPE RStudio Data Lab**, opens `/home/speuser/spe-data-lab/r/spe-data-lab.Rproj` with `--disable-gpu`, which RStudio needs over RDP |

all installed by [setup-data-tools.sh](../../scripts/setup-data-tools.sh), which also creates the python environment, installs R and RStudio, and copies the example workspace into `speuser`'s home.

# two things worth knowing

- every click here is audited. the launcher and the programs it starts are `execve` calls by a human, so they appear in `/var/log/audit/audit.log` with key `spe_cli`. one click can produce several process lines (the launcher, jupyter, its python kernels, the browser), which is why the audit guide says to group by time and parent process before counting actions.
- `spe-rstudio.desktop` hardcodes `/home/speuser/...`, so it only works for `speuser`. `spe-jupyter` uses `$HOME` and works for any account with a workspace. if a second desktop account is ever added, the RStudio entry is the one to generalise.
