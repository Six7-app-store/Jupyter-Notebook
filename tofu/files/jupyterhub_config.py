# JupyterHub für alle Konten der VM. Angemeldet wird über PAM, also mit dem
# Linux-Konto und dem Passwort aus den Zugangsdaten.
c = get_config()  # noqa: F821

# "[::]" lauscht auf IPv6 und IPv4 zugleich; "0.0.0.0" wäre nur IPv4.
c.JupyterHub.bind_url = "http://[::]:8000"

c.JupyterHub.spawner_class = "jupyterhub.spawner.LocalProcessSpawner"
c.Spawner.cmd = ["/opt/jupyterhub/bin/jupyterhub-singleuser"]
c.Spawner.default_url = "/lab"

# Jedes Konto mit Passwort darf sich anmelden. Das sind genau die Konten aus
# dem Deployment; der Standardnutzer des Images hat keins.
c.Authenticator.allow_all = True
c.Authenticator.admin_users = set()

c.JupyterHub.cookie_secret_file = "/var/lib/jupyterhub/jupyterhub_cookie_secret"
c.JupyterHub.db_url = "sqlite:////var/lib/jupyterhub/jupyterhub.sqlite"
