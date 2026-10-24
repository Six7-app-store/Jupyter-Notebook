# Prüft, wie VM, Konten, Zugangsdaten und Einrichtung aus den Variablen
# entstehen. Alle Provider sind gemockt: der Test braucht keinen
# OpenStack-Zugang und legt nichts an.
#
#   cd tofu && tofu init -backend=false && tofu test

mock_provider "openstack" {
  mock_data "openstack_images_image_v2" {
    defaults = {
      id = "00000000-0000-0000-0000-00000000image"
    }
  }
  mock_resource "openstack_networking_port_v2" {
    defaults = {
      all_fixed_ips = ["141.72.10.7", "2001:db8:4::7"]
      mac_address   = "fa:16:3e:00:00:07"
    }
  }
}

mock_provider "random" {}

variables {
  users = {
    "Team #1" = [{ email = "Anna.Alt@dhbw.de" }]
    "2b"      = [{ email = "ben@dhbw.de" }, { email = "cem@dhbw.de" }]
  }
}

run "eine_vm_fuer_alle" {
  command = apply

  assert {
    condition     = openstack_compute_instance_v2.shared_vm.flavor_name == "gp1.small"
    error_message = "Ohne Auswahl muss gp1.small gelten."
  }
  assert {
    condition     = length(openstack_compute_instance_v2.shared_vm.block_device) == 0
    error_message = "disk_size_gb = 0 darf kein Volume anlegen."
  }
  assert {
    condition     = toset(keys(output.team_vms)) == toset(["Team #1", "2b"])
    error_message = "team_vms braucht einen Eintrag je Team, damit die Oberflaeche den Link zuordnet."
  }
}

run "konten_und_gruppen" {
  command = apply

  assert {
    condition     = toset([for u in yamldecode(local.cloud_init).users : u.name]) == toset(["annaalt", "ben", "cem"])
    error_message = "Jede Person bekommt ein Konto, Name aus der E-Mail, klein und ohne Punkte."
  }
  assert {
    condition     = toset(yamldecode(local.cloud_init).groups) == toset(["team-1", "t-2b"])
    error_message = "Teamnamen muessen gueltige Linux-Gruppen werden (\"Team #1\" -> team-1, \"2b\" -> t-2b)."
  }
  assert {
    condition     = length(yamldecode(local.cloud_init).chpasswd.users) == 3
    error_message = "Jede Person braucht ein Passwort, JupyterHub meldet ueber PAM an."
  }
  assert {
    condition     = contains([for f in yamldecode(local.cloud_init).write_files : f.path], "/opt/jupyter-notebook/jupyterhub_config.py")
    error_message = "Die JupyterHub-Konfiguration muss auf der VM liegen."
  }
  assert {
    condition     = yamldecode(local.cloud_init).runcmd[length(yamldecode(local.cloud_init).runcmd) - 1] == ["bash", "/opt/jupyter-notebook/jupyter-setup.sh"]
    error_message = "Das Setup-Skript muss zuletzt laufen, sein Exit-Code entscheidet ueber cloud-final."
  }
}

run "zugang_ueber_ipv6" {
  command = apply

  assert {
    condition     = alltrue([for a in values(output.user_accounts) : a.ip == "2001:db8:4::7" && a.port == 8000 && a.protocol == "web"])
    error_message = "Im Standardnetz ist nur IPv6 oeffentlich - die Zugangsdaten muessen sie nennen."
  }
  assert {
    condition     = output.team_vms["2b"].url == "http://[2001:db8:4::7]:8000/"
    error_message = "Eine IPv6-Adresse gehoert in der URL in eckige Klammern."
  }
  assert {
    condition     = keys(openstack_networking_secgroup_rule_v2.hub) == ["IPv6"] && openstack_networking_secgroup_rule_v2.hub["IPv6"].remote_ip_prefix == "::/0"
    error_message = "Ohne Auswahl gilt ipv6: eine Regel fuer IPv6."
  }
}

run "ipv4_nur_aus_dem_campus" {
  command = apply

  variables {
    ip_mode         = "ipv4"
    network_v4_uuid = "00000000-0000-0000-0000-0000000000v4"
  }

  assert {
    condition     = openstack_networking_port_v2.primary.network_id == "00000000-0000-0000-0000-0000000000v4"
    error_message = "ipv4 muss die VM ins IPv4-Netz haengen."
  }
  assert {
    condition     = openstack_networking_secgroup_rule_v2.hub["IPv4"].remote_ip_prefix == "141.72.0.0/16"
    error_message = "Ueber IPv4 bleibt JupyterHub auf Campus und VPN beschraenkt."
  }
  assert {
    condition     = output.team_vms["2b"].url == "http://141.72.10.7:8000/"
    error_message = "Die URL muss die IPv4 der VM nennen."
  }
}

run "dual_haengt_ipv4_als_zweite_schnittstelle_an" {
  command = apply

  variables {
    ip_mode         = "dual"
    network_v4_uuid = "00000000-0000-0000-0000-0000000000v4"
  }

  assert {
    condition     = length(openstack_compute_interface_attach_v2.v4) == 1
    error_message = "dual braucht die IPv4-Schnittstelle als zweiten Port."
  }
  assert {
    condition     = toset(keys(openstack_networking_secgroup_rule_v2.hub)) == toset(["IPv4", "IPv6"])
    error_message = "dual braucht Regeln fuer beide Familien."
  }
  assert {
    condition     = yamldecode(one([for f in yamldecode(local.cloud_init).write_files : f.content if f.path == "/etc/netplan/60-secondary-ipv4.yaml"])).network.ethernets.secondary.routing-policy[0].from == "141.72.10.7"
    error_message = "cloud-init muss die IPv4-Schnittstelle mit eigener Routing-Tabelle einrichten."
  }
}

run "ipv4_ohne_netz_wird_abgelehnt" {
  command = plan

  variables {
    ip_mode = "ipv4"
  }

  expect_failures = [openstack_compute_instance_v2.shared_vm]
}

run "unbekannter_flavor_wird_abgelehnt" {
  command = plan

  variables {
    flavor = "gpu.huge"
  }

  expect_failures = [var.flavor]
}
