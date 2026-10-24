#!/usr/bin/env bash
# Richtet JupyterHub beim ersten Start der VM ein. Die Linux-Konten hat
# cloud-init vorher angelegt, Konfiguration und Unit liegen unter
# /opt/jupyter-notebook/.
#
# Bricht das Skript ab, scheitert cloud-final.service, und der App Store
# meldet das Deployment als fehlgeschlagen (ADR 0011 im deployment-Repo).
set -euo pipefail

log() { echo "[jupyter] $*"; }

FILES=/opt/jupyter-notebook
NODE_MAJOR=24

export DEBIAN_FRONTEND=noninteractive
# cloud-init startet runcmd ohne HOME; pip und npm brauchen es.
export HOME=/root

# Beim ersten Boot hält oft apt-daily die dpkg-Sperre; warten statt scheitern.
apt_get() { apt-get -y -q -o DPkg::Lock::Timeout=600 "$@"; }

log "Pakete installieren"
apt_get update
apt_get install --no-install-recommends \
  ca-certificates \
  curl \
  git \
  gnupg \
  python3 \
  python3-pip \
  python3-venv \
  ufw

# configurable-http-proxy, der Proxy vor JupyterHub, braucht Node.js
log "Node.js ${NODE_MAJOR} aus NodeSource installieren"
mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
  | gpg --batch --yes --dearmor -o /etc/apt/keyrings/nodesource.gpg
printf 'Types: deb\nURIs: https://deb.nodesource.com/node_%s.x/\nSuites: nodistro\nComponents: main\nSigned-By: /etc/apt/keyrings/nodesource.gpg\n' \
  "$NODE_MAJOR" >/etc/apt/sources.list.d/nodesource.sources
apt_get update
apt_get install --no-install-recommends nodejs

log "JupyterHub und JupyterLab installieren"
python3 -m venv /opt/jupyterhub
/opt/jupyterhub/bin/pip install --quiet --upgrade pip
/opt/jupyterhub/bin/pip install --quiet jupyterhub jupyterlab
npm install --global --silent configurable-http-proxy

log "Dienst einrichten"
install -d -m 700 /var/lib/jupyterhub
install -d -m 755 /etc/jupyterhub
install -m 644 "$FILES/jupyterhub_config.py" /etc/jupyterhub/jupyterhub_config.py
install -m 644 "$FILES/jupyterhub.service" /etc/systemd/system/jupyterhub.service
systemctl daemon-reload
systemctl enable --now jupyterhub

# Firewall: erst SSH freigeben, dann einschalten (nicht umgekehrt)
ufw allow OpenSSH
ufw allow 8000/tcp
ufw --force enable

# Erst fertig melden, wenn die Anmeldeseite antwortet
for _ in $(seq 1 60); do
  if curl -sf -o /dev/null http://localhost:8000/hub/login; then
    log "JupyterHub erreichbar"
    exit 0
  fi
  sleep 2
done

log "JupyterHub antwortet nicht auf http://localhost:8000/hub/login"
systemctl status jupyterhub --no-pager || true
exit 1
