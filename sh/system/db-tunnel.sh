#!/bin/bash
# db-tunnel.sh — Create or stop a local TCP tunnel to an instance's MariaDB.
#
# Used by: make db-tunnel start|stop|status
#
# mariadb never binds a host port directly (docker-compose.yml has no `ports:` for it, in
# either single- or multi-instance mode) — the DB isn't reachable from the host by default.
# This script bridges that gap during local development by spinning up an ephemeral socat
# sidecar on the same compose network, forwarding a published host port to the mariadb
# container's 3306 (a container can't both join another container's netns with `--network
# container:x` and publish its own ports — Docker rejects that combination — so the sidecar
# joins the shared bridge network instead and reaches mariadb by its container DNS name).
#
# Usage:
#   db-tunnel.sh start [port]   # default port 3306
#   db-tunnel.sh stop
#   db-tunnel.sh status
#
# Exit code 0 on success, non-zero on failure.
set -euo pipefail
source ./sh/utils/colors.sh  # green/red helper if available

ENV_RUNTIME="./.env.runtime"
if [ ! -f "$ENV_RUNTIME" ]; then
  echo -e "${RED}[Error]${RESET} $ENV_RUNTIME not found. Run 'make env' or 'make up' first." >&2
  exit 1
fi

# Source only APP_NAME (safe, no secrets leaked).
APP_NAME="$(sed -n 's/^[[:space:]]*APP_NAME=//p' "$ENV_RUNTIME" | tail -n1)"

if [ -z "$APP_NAME" ]; then
  echo -e "${RED}[Error]${RESET} APP_NAME is not set in $ENV_RUNTIME." >&2
  exit 1
fi

CONTAINER_NAME="${APP_NAME}-mariadb"
TUNNEL_PORT="${2:-3306}"
TUNNEL_CONTAINER="${CONTAINER_NAME}-db-tunnel"

cmd_start() {
  if ! docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    echo -e "${RED}[Error]${RESET} $CONTAINER_NAME is not running. Run 'make up' first." >&2
    exit 1
  fi

  if docker container inspect "$TUNNEL_CONTAINER" >/dev/null 2>&1; then
    echo "[db-tunnel] Tunnel already running on 127.0.0.1:${TUNNEL_PORT} → ${CONTAINER_NAME}:3306"
    return 0
  fi

  NETWORK_NAME="$(docker inspect "$CONTAINER_NAME" --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}')"
  if [ -z "$NETWORK_NAME" ]; then
    echo -e "${RED}[Error]${RESET} Could not resolve $CONTAINER_NAME's docker network." >&2
    exit 1
  fi

  docker run --rm -d \
    --name "$TUNNEL_CONTAINER" \
    -p "127.0.0.1:${TUNNEL_PORT}:3306" \
    --network "$NETWORK_NAME" \
    alpine/socat "TCP-LISTEN:3306,fork,reuseaddr" "TCP:${CONTAINER_NAME}:3306"

  echo -e "${GREEN}[db-tunnel]${RESET} Local tunnel ready: 127.0.0.1:${TUNNEL_PORT} → ${CONTAINER_NAME}:3306"
  echo "[db-tunnel] Connect DBeaver/HeidiSQL to 127.0.0.1:${TUNNEL_PORT}"
  echo "[db-tunnel] Stop with: make db-tunnel stop"
}

cmd_stop() {
  docker rm -f "$TUNNEL_CONTAINER" 2>/dev/null || true
  echo -e "${GREEN}[db-tunnel]${RESET} Tunnel stopped."
}

cmd_status() {
  if docker container inspect "$TUNNEL_CONTAINER" >/dev/null 2>&1; then
    echo -e "${GREEN}[db-tunnel]${RESET} Tunnel running on 127.0.0.1:${TUNNEL_PORT} → ${CONTAINER_NAME}:3306"
  else
    echo "[db-tunnel] Tunnel is stopped."
  fi
}

case "${1:-}" in
  start)   cmd_start ;;
  stop)    cmd_stop ;;
  status)  cmd_status ;;
  "")
    echo "Usage: db-tunnel.sh <start|stop|status> [port]" >&2
    exit 1
    ;;
  *)
    echo "Usage: db-tunnel.sh <start|stop|status> [port]" >&2
    exit 1
    ;;
esac
