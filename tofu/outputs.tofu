############################
# [CONTRACT] User Accounts Output
############################

# Schluessel "<team>-<lokaler Teil der E-Mail>", wie vom App Store fuer die
# Zuordnung zu den Mitgliedern verlangt. Aus ip und port baut die Oberflaeche
# den Link zu JupyterHub.
output "user_accounts" {
  description = "[CONTRACT] User accounts mit Login-Informationen"
  sensitive   = true
  value = {
    for uid, user in local.users_map : uid => {
      type     = "password"
      protocol = "web"
      ip       = local.access_ip
      port     = local.hub_port
      username = user.username
      auth     = random_password.user_passwords[uid].result
      email    = user.email
      team     = user.team
    }
  }
}

############################
# VM Details
############################

# Ein Eintrag je Team, alle auf dieselbe VM: die Oberflaeche ordnet den Link
# ueber den Teamnamen zu.
output "team_vms" {
  description = "Details der gemeinsamen VM, je Team"
  value = {
    for team in local.unique_teams : team => {
      instance_id   = openstack_compute_instance_v2.shared_vm.id
      instance_name = openstack_compute_instance_v2.shared_vm.name
      ip_mode       = var.ip_mode
      fixed_ip_v4   = local.ipv4_address
      fixed_ip_v6   = local.ipv6_address
      url           = local.hub_url
    }
  }
}

output "teams_summary" {
  description = "Übersicht: Teams und User-Anzahl"
  value = {
    for team in local.unique_teams : team => length([for u in local.all_users : u if u.team == team])
  }
}
