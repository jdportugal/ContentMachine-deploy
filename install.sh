#!/usr/bin/env bash
# Brand Machine — one-shot installer for a fresh Ubuntu host.
#
# EASIEST: paste this whole file into DigitalOcean → Create Droplet → Advanced
# Options → "Add Initialization scripts (user data)". It self-deploys on first
# boot; no SSH. Or run it over SSH:  bash install.sh
#
# Self-contained: installs Docker, writes its own compose + Caddyfile, pulls the
# PUBLIC image, and serves behind Caddy with a free HTTPS URL via <ip>.sslip.io.
set -euo pipefail

IMAGE="${IMAGE:-ghcr.io/jdportugal/contentmachine:latest}"   # public GHCR image
APP_PORT="${APP_PORT:-8080}"                                 # port the image serves on
DIR="${DIR:-/opt/brand-machine}"                             # where compose lives

log()   { echo "[brand-machine] $*"; }
retry() { local n=0; until "$@"; do n=$((n+1)); [ "$n" -ge 30 ] && return 1; sleep 5; done; }

# curl is used below — present on Ubuntu, but be safe on minimal images.
command -v curl >/dev/null 2>&1 || { apt-get update -y && apt-get install -y curl; }

# ── Docker (install + start if missing) ──────────────────────────────────────
if ! command -v docker >/dev/null 2>&1; then
  log "installing Docker…"
  retry curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
  sh /tmp/get-docker.sh
fi
systemctl enable --now docker 2>/dev/null || true
log "waiting for the Docker daemon…"
retry docker info >/dev/null 2>&1

# ── Public IP → free HTTPS domain ────────────────────────────────────────────
IP=""
for _ in $(seq 1 30); do
  IP="$(curl -fsSL https://api.ipify.org 2>/dev/null || true)"; [ -n "$IP" ] && break
  IP="$(hostname -I 2>/dev/null | awk '{print $1}')";          [ -n "$IP" ] && break
  sleep 3
done
DOMAIN="${DOMAIN:-${IP}.sslip.io}"    # <ip>.sslip.io resolves to <ip>; Caddy gets a cert
log "deploying at https://${DOMAIN}"

mkdir -p "${DIR}"; cd "${DIR}"

# Keep any keys the operator already added.
[ -f .env ] || cat > .env <<'EOF'
# Offline 'fake' driver by default (no keys needed). For real generation, add
# your keys below then run:  docker compose up -d
# CLIPS_DRIVER=api
# OPENAI_API_KEY=
# ELEVENLABS_API_KEY=
# ANTHROPIC_API_KEY=
# KIE_API_KEY=
EOF

cat > docker-compose.yml <<EOF
services:
  app:
    image: ${IMAGE}
    restart: unless-stopped
    environment:
      APP_URL: https://${DOMAIN}
      ASSET_URL: https://${DOMAIN}
    env_file:
      - .env
    volumes:
      - storage:/app/storage
      - vault:/app/vault
      - db:/app/database
    expose:
      - "${APP_PORT}"

  caddy:
    image: caddy:2
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      - app

volumes:
  storage:
  vault:
  db:
  caddy_data:
  caddy_config:
EOF

cat > Caddyfile <<EOF
${DOMAIN} {
    reverse_proxy app:${APP_PORT}
}
EOF

log "pulling image…"; retry docker compose pull
log "starting…";      docker compose up -d
log "done"

cat <<EOF

✓ Brand Machine is up:  https://${DOMAIN}
  (first request takes a few seconds while Caddy fetches the certificate)

  logs:    cd ${DIR} && docker compose logs -f
  update:  cd ${DIR} && docker compose pull && docker compose up -d
  keys:    edit ${DIR}/.env then 'docker compose up -d'
EOF
