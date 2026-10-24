# JupyterHub – gemeinsame Notebook-Umgebung

Eine JupyterHub-Instanz auf einer gemeinsamen VM. Jede Person meldet sich mit
eigenen Zugangsdaten an und bekommt eine eigene JupyterLab-Sitzung mit eigenem
Home-Verzeichnis.

## Vorinstallierte Software

- JupyterHub und JupyterLab (aktuelle Versionen aus PyPI zum Zeitpunkt des
  Deployments), Python-Kernel
- Python 3 (inkl. pip, venv), Git, Node.js 24 für den Proxy vor JupyterHub

Weitere Pakete installiert jede Person selbst, etwa mit
`pip install --user pandas` im Terminal von JupyterLab.

## User-Management

- **Ein Linux-Konto pro Person**, abgeleitet aus der E-Mail-Adresse
  (`anna.alt@dhbw.de` → `annaalt`; beginnt der Name mit einer Ziffer, kommt
  ein `u` davor)
- JupyterHub meldet über PAM an: Benutzername und Passwort sind die des
  Linux-Kontos
- Alle Teams landen auf **einer gemeinsamen VM**, jedes Team als eigene
  Linux-Gruppe
- Das Passwort gilt auch für `sudo` und SSH

## VM-Deployment

| | |
|---|---|
| VMs gesamt | **1** (geteilt von allen Teams und Personen) |
| Größe | wählbar: `gp1.small`, `gp1.medium`, `gp1.large` (Standard `gp1.small`) |
| Festplatte | wählbar: 10–200 GB, Standard ist die Platte des Flavors (10 GB) |
| Erreichbar über | HTTP auf Port 8000, wählbar über IPv6 (Standard), IPv4 oder beides |
| Floating IP | Nein |

Jede laufende JupyterLab-Sitzung braucht Arbeitsspeicher. Für mehr als eine
Handvoll Personen gleichzeitig besser `gp1.medium` oder größer wählen.

## Konfigurierbare Variablen

| Variable | Beschreibung | Standard |
|---|---|---|
| `flavor` | Größe der VM | `gp1.small` |
| `disk_size_gb` | Festplatte in GB, `0` nutzt die Platte des Flavors | `0` |
| `ip_mode` | Adressfamilie: `ipv4`, `ipv6` oder `dual` | `ipv6` |
| `network_uuid` | Netz mit öffentlicher IPv6, für `ipv6` und `dual` | `DHBWV6` |
| `network_v4_uuid` | Netz mit öffentlich gerouteter IPv4, für `ipv4` und `dual` | leer |
| `shared_secgroup_id` | ID der gemeinsamen Security Group | `default` |
| `web_source_v4` | IPv4-Präfix, das JupyterHub erreichen darf | `141.72.0.0/16` |
| `web_source_v6` | IPv6-Präfix, das JupyterHub erreichen darf | `::/0` |

## Erreichbarkeit

JupyterHub lauscht auf `[::]:8000` und damit auf IPv4 und IPv6. Die
Verbindung ist unverschlüsseltes HTTP. Über IPv4 bleibt der Hub deshalb wie
bisher auf Campus und VPN beschränkt (`web_source_v4`). Für IPv6 ist das
Campus-Präfix nicht hinterlegt, und im Standardnetz wäre die VM sonst gar
nicht erreichbar; `web_source_v6` steht deshalb auf `::/0` und lässt sich im
Wizard eingrenzen.

`ip_mode` funktioniert wie bei der
[Ubuntu-App](https://github.com/Six7-app-store/Ubuntu-App#adressfamilie-ip_mode).

## Einrichtung beim Boot

Es wird kein Image mehr gebaut (ADR 0010 im deployment-Repo). cloud-init legt
Konten und Gruppen an und die Dateien aus [`tofu/files/`](tofu/files/) ab,
danach installiert [`jupyter-setup.sh`](tofu/files/jupyter-setup.sh)
Node.js, JupyterHub und JupyterLab und startet den Dienst.

Das Skript meldet erst Erfolg, wenn die Anmeldeseite antwortet. Scheitert ein
Schritt, scheitert `cloud-final.service`, und der App Store zeigt das
Deployment als fehlgeschlagen mit den passenden Zeilen aus der Konsole
(ADR 0011). Das Protokoll steht auf der VM in
`/var/log/cloud-init-output.log`.

Wie lange die Einrichtung auf newstack dauert, ist noch nicht gemessen.

## Prüfen ohne Cloud

```bash
cd tofu
tofu init -backend=false
tofu fmt -check -recursive
tofu validate
tofu test
```

Die Tests mocken alle Provider und brauchen keinen OpenStack-Zugang. Die CI
([`.github/workflows/opentofu.yml`](.github/workflows/opentofu.yml)) fährt
dieselben Schritte und prüft zusätzlich das Setup-Skript mit ShellCheck.
