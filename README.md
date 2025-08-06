# Traefik Installer Script

This is a Bash script for automated installation and removal of [Traefik](https://traefik.io/) on servers running **Debian 12** or **Ubuntu 20.04+**.

## Features
- Automatic installation of the latest Traefik version
- No Docker required — Traefik is installed and runs directly from files
- Creates user and required directories
- Generates static and dynamic configs with examples
- Dashboard setup with optional basic authentication
- Creates and starts a systemd service
- Complete removal of Traefik and all related files

## Requirements
- OS: Debian 12 or Ubuntu 20.04 and newer
- Root privileges (use `sudo`)

## Usage

1. **Install Traefik:**
   ```bash
   curl -O https://raw.githubusercontent.com/orevalord/traefik-installer/refs/heads/main/traefik.sh
   chmod +x traefik.sh
   sudo ./traefik.sh install
   ```

2. **Uninstall Traefik:**
   ```bash
   sudo ./traefik.sh uninstall
   ```

## Configuration
- **/etc/traefik/traefik.yml** — static config
- **/etc/traefik/dynamic_conf.yml** — dynamic config (examples for subdomains)
- **/etc/traefik/acme.json** — Let's Encrypt certificate storage

> **Important!** After installation, replace the domains `sub1.yourdomain.com`, `sub2.yourdomain.com`, and `traefik.yourdomain.com` in the config with your actual domains.

## Dashboard
- The dashboard is accessible only at `http://ip_or_domain/dashboard/` (note the trailing slash).
- To log in, use the username `traefik` and the password you set during installation.

## Logs
- **/etc/traefik/traefik.log** — Traefik log
- **/etc/traefik/access.log** — access log
- To view service logs:
  ```bash
  journalctl -u traefik -f
  ```