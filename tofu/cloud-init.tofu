# -----------------------------------------------------------------------------
# Einrichtung der VM beim ersten Boot
#
# Ersetzt das fruehere Packer-Image (ADR 0010 im deployment-Repo).
# cloud-init legt die Konten und Teamgruppen an und die Dateien aus
# tofu/files/ ab, jupyter-setup.sh installiert danach JupyterHub.
#
# Die Konfiguration wird mit yamlencode gebaut statt als Template: yamlencode
# quotet jeden Wert selbst. "Team #1" wird nicht am " #" abgeschnitten, und
# ein Passwort mit fuehrendem ! @ % oder * bleibt gueltiges YAML.
# -----------------------------------------------------------------------------

locals {
  cloud_init_config = {
    ssh_pwauth = true

    # JupyterHub lauscht auf [::] und erreicht seinen Proxy dann ueber den
    # Hostnamen der VM. Der muss sich aufloesen lassen, sonst startet der Hub
    # nicht ("Name or service not known").
    manage_etc_hosts = "localhost"

    # Linux-Gruppen je Team (Namen aus local.group_names in main.tofu)
    groups = local.unique_groups

    users = [
      for uid, user in local.users_map : {
        name        = user.username
        shell       = "/bin/bash"
        sudo        = ["ALL=(ALL) ALL"]
        groups      = user.group
        lock_passwd = false
      }
    ]

    chpasswd = {
      expire = false
      users = [
        for uid, user in local.users_map : {
          name     = user.username
          password = random_password.user_passwords[uid].result
          type     = "text"
        }
      ]
    }

    write_files = concat(
      [
        for f in sort(fileset("${path.module}/files", "**")) : {
          path        = "/opt/jupyter-notebook/${f}"
          encoding    = "gz+b64"
          content     = base64gzip(file("${path.module}/files/${f}"))
          permissions = endswith(f, ".sh") ? "0755" : "0644"
        }
      ],
      [
        {
          # Vorne einsortiert, damit es vor 60-cloudimg-settings.conf des
          # Ubuntu-Images gilt: sshd nimmt den ersten Wert.
          path        = "/etc/ssh/sshd_config.d/01-click-n-deploy.conf"
          permissions = "0644"
          content     = <<-EOT
            PasswordAuthentication yes
            PubkeyAuthentication yes
            PermitRootLogin no
            UsePAM yes
          EOT
        },
      ],
      # ip_mode = dual: die IPv4-Schnittstelle, die OpenTofu nach dem Boot
      # anhaengt. Ihre Default-Route ueber das Gateway des IPv4-Netzes steht
      # in einer eigenen Tabelle, und nur Pakete mit ihrer Adresse als
      # Absender nehmen diese Tabelle. Sonst gingen Antworten ueber die
      # Hauptschnittstelle hinaus, und Neutrons Port-Security verwirft sie
      # als gefaelschten Absender. Gleiches Muster wie der Staging-Aufbau
      # im deployment-Repo.
      local.dual ? [
        {
          path        = "/etc/netplan/60-secondary-ipv4.yaml"
          permissions = "0600"
          content = yamlencode({
            network = {
              version = 2
              ethernets = {
                secondary = {
                  match           = { macaddress = local.secondary_mac }
                  dhcp4           = true
                  dhcp6           = false
                  accept-ra       = false
                  dhcp4-overrides = { use-routes = false }
                  routes          = [{ to = "default", via = local.secondary_gateway, table = 100 }]
                  routing-policy  = [{ from = local.secondary_ipv4, table = 100 }]
                }
              }
            }
          })
        },
      ] : [],
    )

    runcmd = concat(
      ["systemctl restart ssh"],
      local.dual ? [
        # Die IPv4-Schnittstelle kommt erst nach dem Boot dazu. Bis zu fuenf
        # Minuten auf ihre MAC warten, dann die netplan-Datei oben anwenden.
        # Kommt sie nicht, bleibt die VM ueber IPv6 erreichbar.
        ["sh", "-c", "for i in $(seq 1 60); do if ip -o link | grep -qi \"$1\"; then netplan apply; break; fi; sleep 5; done", "sh", local.secondary_mac],
      ] : [],
      [
        # Als letzter Befehl: sein Exit-Code entscheidet, ob cloud-final als
        # fehlgeschlagen gilt.
        ["bash", "/opt/jupyter-notebook/jupyter-setup.sh"],
      ],
    )

    final_message = "JupyterHub bereit fuer ${length(local.all_users)} Personen"
  }

  cloud_init = "#cloud-config\n${yamlencode(local.cloud_init_config)}"
}
