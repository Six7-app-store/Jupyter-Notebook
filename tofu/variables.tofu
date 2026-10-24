################################################
# Von der Plattform gesetzt
################################################

variable "users" {
  description = "Per-team roster — vom Worker injiziert."
  type = map(list(object({
    email = string
  })))
  default = {}
}

################################################
# Größe der VM
################################################

# Alle Personen teilen sich eine VM, jede mit eigener JupyterLab-Sitzung.
# Für mehr als eine Handvoll Personen gp1.medium oder gp1.large wählen.
variable "flavor" {
  description = "Größe der VM (CPU und Arbeitsspeicher) @openstack:flavor"
  type        = string
  default     = "gp1.small"

  validation {
    condition     = contains(["gp1.small", "gp1.medium", "gp1.large"], var.flavor)
    error_message = "flavor muss gp1.small, gp1.medium oder gp1.large sein."
  }
}

# 0 = die Systemplatte des Flavors (bei gp1 10 GB), ohne Cinder. Jeder andere
# Wert legt die Systemplatte als Cinder-Volume dieser Größe an; es wird mit
# der VM gelöscht.
variable "disk_size_gb" {
  description = "Festplatte in GB (0 = Standardgröße des Flavors)"
  type        = number
  default     = 0

  validation {
    condition     = var.disk_size_gb >= 0 && var.disk_size_gb <= 200
    error_message = "disk_size_gb muss zwischen 0 und 200 liegen."
  }

  # Das Ubuntu-Image braucht mindestens 10 GB. Bewusst als eigener Block mit
  # ">": so liest der Wizard nur den Bereich 0–200 oben als Grenzen.
  validation {
    condition     = var.disk_size_gb == 0 || var.disk_size_gb > 9
    error_message = "disk_size_gb muss 0 oder mindestens 10 sein."
  }
}

################################################
# Netz
################################################

#   ipv4  eine Schnittstelle im IPv4-Netz (network_v4_uuid)
#   ipv6  eine Schnittstelle im IPv6-Netz (network_uuid) - Standard
#   dual  IPv6-Netz als Hauptschnittstelle, dazu eine zweite im IPv4-Netz
variable "ip_mode" {
  description = "Adressfamilie: ipv4, ipv6 oder dual (beide)"
  type        = string
  default     = "ipv6"

  validation {
    condition     = contains(["ipv4", "ipv6", "dual"], var.ip_mode)
    error_message = "ip_mode muss \"ipv4\", \"ipv6\" oder \"dual\" sein."
  }
}

variable "network_uuid" {
  description = "Netz mit öffentlicher IPv6, z. B. DHBWV6 - für ipv6 und dual @openstack:network:id"
  type        = string
  default     = "9b579624-d844-4df3-b38d-89978b31d37d"
}

variable "network_v4_uuid" {
  description = "Netz mit öffentlich gerouteter IPv4, z. B. DHBWv4 - für ipv4 und dual @openstack:network:id"
  type        = string
  default     = ""
}

variable "shared_secgroup_id" {
  description = "ID der gemeinsamen Security Group für alle VMs @openstack:security_group:id"
  type        = string
  default     = "7ca4f889-e11e-4a16-83a8-73a77ebdbbe6"
}

# JupyterHub läuft über unverschlüsseltes HTTP. Über IPv4 deshalb wie bisher
# nur Campus und VPN. Für IPv6 ist das Campus-Präfix nicht hinterlegt; ohne
# Freigabe wäre die VM im Standardnetz gar nicht erreichbar.
variable "web_source_v4" {
  description = "IPv4-Präfix, das JupyterHub erreichen darf"
  type        = string
  default     = "141.72.0.0/16"
}

variable "web_source_v6" {
  description = "IPv6-Präfix, das JupyterHub erreichen darf"
  type        = string
  default     = "::/0"
}
