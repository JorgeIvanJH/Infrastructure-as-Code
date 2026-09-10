#!/usr/bin/env bash

set -euo pipefail

readonly RSTUDIO_VERSION="2026.08.1-195"
readonly RSTUDIO_DEB="/tmp/rstudio-${RSTUDIO_VERSION}-amd64.deb"
readonly RSTUDIO_URL="https://download1.rstudio.org/electron/jammy/amd64/rstudio-${RSTUDIO_VERSION}-amd64.deb"
readonly PYTHON_ENV="/opt/spe-python"
readonly WORKSPACE="/home/speuser/spe-data-lab"

# Install the operating-system packages used by the data tools. Epiphany is a small browser that can display JupyterLab inside the XFCE desktop.
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  curl \
  epiphany-browser \
  libasound2t64 \
  libnspr4 \
  libnss3 \
  python3-venv \
  r-base

# Install the pinned open-source RStudio Desktop build from Posit's official download site. The explicit libnspr4 and libnss3 packages above ensure that its Electron desktop application has the required runtime libraries.
curl --fail --location --retry 3 --output "$RSTUDIO_DEB" "$RSTUDIO_URL"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$RSTUDIO_DEB"
sudo rm -f "$RSTUDIO_DEB"

# Keep the notebook packages out of Ubuntu's system Python. The requirements file is the single place where this lesson declares Python packages.
sudo python3 -m venv "$PYTHON_ENV"
sudo "$PYTHON_ENV/bin/python" -m pip install \
  --disable-pip-version-check \
  --requirement /tmp/python-requirements.txt

# Create one workspace owned by the graphical end user. Both JupyterLab and RStudio read the same copy of the CSV from this folder.
sudo install -d -o speuser -g speuser -m 0755 \
  "$WORKSPACE/data" \
  "$WORKSPACE/environments/python" \
  "$WORKSPACE/environments/r" \
  "$WORKSPACE/notebooks" \
  "$WORKSPACE/r"

sudo install -o speuser -g speuser -m 0644 \
  /tmp/hepatitis.csv \
  "$WORKSPACE/data/hepatitis.csv"
sudo install -o speuser -g speuser -m 0644 \
  /tmp/python-requirements.txt \
  "$WORKSPACE/environments/python/requirements.txt"
sudo install -o speuser -g speuser -m 0644 \
  /tmp/r-requirements.R \
  "$WORKSPACE/environments/r/requirements.R"
sudo install -o speuser -g speuser -m 0644 \
  /tmp/read-hepatitis.ipynb \
  "$WORKSPACE/notebooks/read-hepatitis.ipynb"
sudo install -o speuser -g speuser -m 0644 \
  /tmp/read-hepatitis.R \
  "$WORKSPACE/r/read-hepatitis.R"
sudo install -o speuser -g speuser -m 0644 \
  /tmp/spe-data-lab.Rproj \
  "$WORKSPACE/r/spe-data-lab.Rproj"

# Add two clear entries to XFCE's application menu.
sudo install -o root -g root -m 0755 /tmp/spe-jupyter /usr/local/bin/spe-jupyter
sudo install -o root -g root -m 0644 \
  /tmp/spe-jupyter.desktop \
  /usr/share/applications/spe-jupyter.desktop
sudo install -o root -g root -m 0644 \
  /tmp/spe-rstudio.desktop \
  /usr/share/applications/spe-rstudio.desktop

# Validate the installed environment and the shared data before saving the image. The expected data shape is 154 rows and 20 columns.
sudo -u speuser "$PYTHON_ENV/bin/jupyter" lab --version
sudo -u speuser "$PYTHON_ENV/bin/python" -c \
  "import pandas as pd; data = pd.read_csv('$WORKSPACE/data/hepatitis.csv'); assert data.shape == (154, 20); print('Python data check:', data.shape)"
sudo -u speuser Rscript "$WORKSPACE/environments/r/requirements.R"
sudo -u speuser bash -c "cd '$WORKSPACE/r' && Rscript read-hepatitis.R"

# Report all unresolved shared libraries together before trying to start RStudio. This makes a failed image build easier to diagnose.
rstudio_binary="$(readlink -f "$(command -v rstudio)")"
missing_libraries="$(ldd "$rstudio_binary" | awk '/not found/ { print $1 }')"
if [[ -n "$missing_libraries" ]]; then
  printf 'RStudio is missing these shared libraries:\n%s\n' "$missing_libraries" >&2
  exit 1
fi

rstudio --version

# Clean up the temporary files
sudo rm -f \
  /tmp/hepatitis.csv \
  /tmp/python-requirements.txt \
  /tmp/r-requirements.R \
  /tmp/read-hepatitis.ipynb \
  /tmp/read-hepatitis.R \
  /tmp/spe-data-lab.Rproj \
  /tmp/spe-jupyter \
  /tmp/spe-jupyter.desktop \
  /tmp/spe-rstudio.desktop
