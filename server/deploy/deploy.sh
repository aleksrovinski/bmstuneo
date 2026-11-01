#!/usr/bin/env bash
# Deploys the push server and the website to one VPS (Debian/Ubuntu, key-based root SSH).
# Usage: server/deploy/deploy.sh root@HOST APNS_KEY.p8 FCM_SERVICE_ACCOUNT.json
set -euo pipefail

HOST=$1 APNS_KEY=$2 FCM_JSON=$3
HERE=$(cd "$(dirname "$0")" && pwd)
SERVER_DIR=$(dirname "$HERE")
SITE_DIR=$(cd "$SERVER_DIR/../../website" && pwd)

ssh "$HOST" 'set -e
  export DEBIAN_FRONTEND=noninteractive
  command -v docker >/dev/null || { apt-get update -q && apt-get install -yq docker.io; }
  command -v caddy >/dev/null || { apt-get update -q && apt-get install -yq caddy; }
  systemctl enable --now docker
  install -d -m 700 /etc/bmstu-neo
  install -d /opt/bmstu-neo-push /var/www/bmstuneo'

# Secrets: readable by root and the container user only
scp -q "$APNS_KEY" "$HOST:/etc/bmstu-neo/AuthKey.p8"
scp -q "$FCM_JSON" "$HOST:/etc/bmstu-neo/fcm.json"

rsync -az --delete --exclude .dart_tool --exclude data --exclude test --exclude deploy \
  "$SERVER_DIR/" "$HOST:/opt/bmstu-neo-push/"
rsync -az --delete --exclude .git --exclude .gitignore --exclude README.md \
  "$SITE_DIR/" "$HOST:/var/www/bmstuneo/"
scp -q "$HERE/Caddyfile" "$HOST:/etc/caddy/Caddyfile"

ssh "$HOST" 'set -e
  chown -R 10001 /etc/bmstu-neo && chmod 700 /etc/bmstu-neo && chmod 400 /etc/bmstu-neo/*
  [ -f /etc/bmstu-neo/admin-token ] || (umask 077; openssl rand -hex 24 > /etc/bmstu-neo/admin-token)
  chmod -R a+rX /var/www/bmstuneo
  docker build -q -t bmstu-neo-push /opt/bmstu-neo-push
  docker rm -f push 2>/dev/null || true
  docker run -d --name push --restart unless-stopped -p 127.0.0.1:8080:8080 \
    -v push-data:/data -v /etc/bmstu-neo:/secrets:ro \
    -e APNS_KEY_FILE=/secrets/AuthKey.p8 -e APNS_KEY_ID=A78SGLKGT5 -e APNS_TEAM_ID=F72A8BN5CB \
    -e FCM_SERVICE_ACCOUNT_FILE=/secrets/fcm.json \
    -e ADMIN_TOKEN="$(cat /etc/bmstu-neo/admin-token)" bmstu-neo-push
  caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
  systemctl reload caddy || systemctl restart caddy'
echo "Deployed. Health: curl https://bmstuneo.xyz/healthz"
