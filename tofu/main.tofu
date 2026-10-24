# OpenTofu erwartet weiterhin das Schluesselwort "terraform"; die Provider
# werden ueber registry.opentofu.org aufgeloest.
terraform {
  required_version = ">= 1.13.0"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "openstack" {
  cloud = "openstack"
  # Auth via OS_CLOUD + clouds.yaml (oder OS_* env vars)
}

############################
# APP-DEFAULTS
############################

locals {
  app_name = "jupyter-notebook"

  # Basis-Image; eingerichtet wird beim ersten Boot per cloud-init
  # (cloud-init.tofu), ein eigenes Image wird nicht gebaut.
  image_name = "Ubuntu 24.04"

  # Systemplatte als Cinder-Volume nur, wenn eine Groesse gewaehlt ist.
  boot_from_volume = var.disk_size_gb > 0

  hub_port = 8000
}

############################
# ADRESSFAMILIEN (var.ip_mode)
############################

locals {
  ethertypes = {
    ipv4 = ["IPv4"]
    ipv6 = ["IPv6"]
    dual = ["IPv4", "IPv6"]
  }[var.ip_mode]

  # Bei dual liegt die Hauptschnittstelle im IPv6-Netz: dessen private IPv4
  # bringt den Weg nach draussen (Paketquellen, NodeSource) ueber NAT mit.
  primary_network_id = var.ip_mode == "ipv4" ? var.network_v4_uuid : var.network_uuid

  dual = var.ip_mode == "dual"
}

# JupyterHub je Adressfamilie - eine IPv4-Regel laesst kein IPv6-Paket durch
# und umgekehrt.
resource "random_id" "secgroup" {
  byte_length = 4
}

resource "openstack_networking_secgroup_v2" "hub" {
  # Neutron erlaubt doppelte Namen; der Anhang haelt mehrere Deployments
  # im selben Projekt auseinander.
  name        = "${local.app_name}-${random_id.secgroup.hex}"
  description = "JupyterHub (${var.ip_mode})"
}

resource "openstack_networking_secgroup_rule_v2" "hub" {
  for_each = toset(local.ethertypes)

  security_group_id = openstack_networking_secgroup_v2.hub.id
  direction         = "ingress"
  ethertype         = each.key
  protocol          = "tcp"
  port_range_min    = local.hub_port
  port_range_max    = local.hub_port
  remote_ip_prefix  = each.key == "IPv4" ? var.web_source_v4 : var.web_source_v6
  description       = "JupyterHub (${each.key})"
}

resource "openstack_networking_port_v2" "primary" {
  name       = "${local.app_name}-shared"
  network_id = local.primary_network_id

  security_group_ids = [
    var.shared_secgroup_id,
    openstack_networking_secgroup_v2.hub.id,
  ]
}

# Zweite Schnittstelle fuer dual, vorab als Port angelegt: so sind MAC und
# Adresse schon bekannt, wenn cloud-init sein user-data bekommt.
resource "openstack_networking_port_v2" "v4" {
  count      = local.dual ? 1 : 0
  name       = "${local.app_name}-shared-v4"
  network_id = var.network_v4_uuid

  security_group_ids = [
    var.shared_secgroup_id,
    openstack_networking_secgroup_v2.hub.id,
  ]
}

locals {
  secondary_ipv4 = local.dual ? one([for ip in openstack_networking_port_v2.v4[0].all_fixed_ips : ip if !strcontains(ip, ":")]) : ""
  secondary_mac  = local.dual ? openstack_networking_port_v2.v4[0].mac_address : ""
}

############################
# USER MANAGEMENT (CONTRACT)
############################

locals {
  # Team -> Linux-Gruppenname. Gruppen muessen mit einem Buchstaben beginnen,
  # daher das Praefix fuer Teams, die mit einer Ziffer anfangen.
  group_names = {
    for team in keys(var.users) : team => (
      can(regex("^[a-z]", trim(replace(lower(team), "/[^a-z0-9_-]+/", "-"), "-")))
      ? trim(replace(lower(team), "/[^a-z0-9_-]+/", "-"), "-")
      : "t-${trim(replace(lower(team), "/[^a-z0-9_-]+/", "-"), "-")}"
    )
  }

  # Linux-Namen muessen mit einem Buchstaben beginnen und duerfen nur
  # wenige Zeichen enthalten - "Anna.Alt" wird so zu "annaalt".
  all_users = flatten([
    for team, members in var.users : [
      for member in members : {
        id    = "${team}-${replace(split("@", member.email)[0], ".", "-")}"
        team  = team
        email = member.email
        group = local.group_names[team]
        username = (
          can(regex("^[a-z]", lower(replace(split("@", member.email)[0], "/[^A-Za-z0-9]/", ""))))
          ? substr(lower(replace(split("@", member.email)[0], "/[^A-Za-z0-9]/", "")), 0, 30)
          : "u${substr(lower(replace(split("@", member.email)[0], "/[^A-Za-z0-9]/", "")), 0, 29)}"
        )
      }
    ]
  ])

  users_map     = { for user in local.all_users : user.id => user }
  unique_teams  = distinct([for user in local.all_users : user.team])
  unique_groups = distinct([for user in local.all_users : user.group])
}

resource "random_password" "user_passwords" {
  for_each         = local.users_map
  length           = 16
  special          = true
  override_special = "!@%^*_-+="
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
}

data "openstack_images_image_v2" "image" {
  name        = local.image_name
  most_recent = true
}

# -----------------------------------------------------------------------------
# Gemeinsame VM fuer alle Teams
# -----------------------------------------------------------------------------
resource "openstack_compute_instance_v2" "shared_vm" {
  name        = "${local.app_name}-shared"
  image_id    = local.boot_from_volume ? null : data.openstack_images_image_v2.image.id
  flavor_name = var.flavor

  # Mit gewaehlter Plattengroesse bootet die VM von einem Volume aus dem
  # Image; ohne bleibt es bei der Systemplatte des Flavors.
  dynamic "block_device" {
    for_each = local.boot_from_volume ? [1] : []
    content {
      uuid                  = data.openstack_images_image_v2.image.id
      source_type           = "image"
      destination_type      = "volume"
      volume_size           = var.disk_size_gb
      boot_index            = 0
      delete_on_termination = true
    }
  }

  timeouts {
    create = "15m"
    delete = "15m"
  }

  # Nur die Hauptschnittstelle. Die zweite bei dual haengt interface_attach
  # unten an, sonst bekaeme die VM zwei Default-Routen.
  network {
    port = openstack_networking_port_v2.primary.id
  }

  user_data = local.cloud_init

  metadata = {
    teams = join(",", local.unique_teams)
    app   = local.app_name
  }

  depends_on = [openstack_networking_secgroup_rule_v2.hub]

  lifecycle {
    precondition {
      condition     = var.ip_mode == "ipv6" || var.network_v4_uuid != ""
      error_message = "ip_mode \"${var.ip_mode}\" braucht ein IPv4-Netz in network_v4_uuid."
    }
    precondition {
      condition     = var.ip_mode == "ipv4" || var.network_uuid != ""
      error_message = "ip_mode \"${var.ip_mode}\" braucht ein IPv6-Netz in network_uuid."
    }
  }
}

resource "openstack_compute_interface_attach_v2" "v4" {
  count       = local.dual ? 1 : 0
  instance_id = openstack_compute_instance_v2.shared_vm.id
  port_id     = openstack_networking_port_v2.v4[0].id
}

############################
# ADRESSEN
############################

# Bei dual die oeffentliche IPv4 der zweiten Schnittstelle, weil sie mehr
# Heimnetze erreicht. Die IPv4 im IPv6-Netz ist eine private NAT-Adresse und
# taugt nicht als Ziel.
locals {
  ipv4_address = (
    var.ip_mode == "ipv4" ? one([for ip in openstack_networking_port_v2.primary.all_fixed_ips : ip if !strcontains(ip, ":")])
    : local.dual ? local.secondary_ipv4
    : null
  )
  ipv6_address = var.ip_mode == "ipv4" ? null : one([for ip in openstack_networking_port_v2.primary.all_fixed_ips : ip if strcontains(ip, ":")])

  access_ip = coalesce(local.ipv4_address, local.ipv6_address)
  hub_url   = strcontains(local.access_ip, ":") ? "http://[${local.access_ip}]:${local.hub_port}/" : "http://${local.access_ip}:${local.hub_port}/"
}
