# Brand Machine — deploy

One-command install on a fresh Ubuntu host (e.g. a DigitalOcean Droplet ≥ 4 GB):

```bash
curl -fsSL https://raw.githubusercontent.com/jdportugal/ContentMachine-deploy/main/install.sh | bash
```

Installs Docker, pulls the public image, and serves the app behind Caddy at a free
HTTPS URL (`https://<ip>.sslip.io`). Data persists on Docker volumes.

- **Update:** `cd /opt/brand-machine && docker compose pull && docker compose up -d`
- **Add API keys:** edit `/opt/brand-machine/.env`, then `docker compose up -d`

The application source is private; this repo only holds the self-contained installer.
