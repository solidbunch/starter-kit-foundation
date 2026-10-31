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
#   db-tunnel.sh start [port]   # default port 3306, must be an integer 1-65535
#   db-tunnel.sh stop
#   db-tunnel.sh status         # reports the port actually published by the tunnel
#
# Exit code 0 on success, non-zero on failure.
set -euo pipefail
source ./sh/utils/colors.sh  # green/red helper if available

ENV_RUNTIME="./.env.runtime"
if [ ! -f "$ENV_RUNTIME" ]; then
  echo -e "${RED}[Error]${RESET} $ENV_RUNTIME not found. Run 'make env' or 'make up' first." >&2
  exit 1
fi

# Read only the two keys this script needs, with the env system's own "last occurrence wins"
# semantics. Sourcing .env.runtime would execute its values as shell.
env_value() {
  sed -n "s/^[[:space:]]*$1=\([^#[:space:]]*\).*/\1/p" "$ENV_RUNTIME" | tail -n1
}

APP_NAME="$(env_value APP_NAME)"
APP_DB_TUNNEL_IMAGE="$(env_value APP_DB_TUNNEL_IMAGE)"

if [ -z "$APP_NAME" ]; then
  echo -e "${RED}[Error]${RESET} APP_NAME is not set in $ENV_RUNTIME." >&2
  exit 1
fi

if [ -z "$APP_DB_TUNNEL_IMAGE" ]; then
  echo -e "${RED}[Error]${RESET} APP_DB_TUNNEL_IMAGE is not set in $ENV_RUNTIME." >&2
  exit 1
fi

CONTAINER_NAME="${APP_NAME}-mariadb"
TUNNEL_PORT="${2:-3306}"
TUNNEL_CONTAINER="${CONTAINER_NAME}-db-tunnel"

if ! [[ "$TUNNEL_PORT" =~ ^[1-9][0-9]{0,4}$ ]] || [ "$TUNNEL_PORT" -gt 65535 ]; then
  echo -e "${RED}[Error]${RESET} Invalid port '${TUNNEL_PORT}'. Expected an integer between 1 and 65535, without leading zeros." >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo -e "${RED}[Error]${RESET} Docker daemon is not reachable. Start Docker and retry." >&2
  exit 1
fi

# Host port actually published by a running tunnel (empty when it is not running).
published_port() {
  docker inspect "$TUNNEL_CONTAINER" \
    --format '{{with (index .HostConfig.PortBindings "3306/tcp")}}{{(index . 0).HostPort}}{{end}}' \
    2>/dev/null || true
}

tunnel_is_running() {
  [ "$(docker inspect "$TUNNEL_CONTAINER" --format '{{.State.Running}}' 2>/dev/null || true)" = "true" ]
}

cmd_start() {
  if ! docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    echo -e "${RED}[Error]${RESET} $CONTAINER_NAME is not running. Run 'make up' first." >&2
    exit 1
  fi

  if docker container inspect "$TUNNEL_CONTAINER" >/dev/null 2>&1; then
    if tunnel_is_running; then
      ACTUAL_PORT="$(published_port)"
      ACTUAL_PORT="${ACTUAL_PORT:-unknown}"
      if [ "$ACTUAL_PORT" != "$TUNNEL_PORT" ]; then
        echo "[db-tunnel] Tunnel already running on 127.0.0.1:${ACTUAL_PORT} → ${CONTAINER_NAME}:3306 (requested ${TUNNEL_PORT}). Run 'make db-tunnel stop' to change the port." >&2
      else
        echo "[db-tunnel] Tunnel already running on 127.0.0.1:${ACTUAL_PORT} → ${CONTAINER_NAME}:3306"
      fi
      return 0
    fi

    # A container in `created`/`exited` state (e.g. a previous `docker run` that failed halfway)
    # would block the name and its HostConfig still advertises the old port binding — drop it.
    docker rm -f "$TUNNEL_CONTAINER" >/dev/null 2>&1 || true
  fi

  NETWORK_NAME="$(docker inspect "$CONTAINER_NAME" --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}')"
  if [ -z "$NETWORK_NAME" ]; then
    echo -e "${RED}[Error]${RESET} Could not resolve $CONTAINER_NAME's docker network." >&2
    exit 1
  fi

  if ! RUN_OUTPUT="$(docker run --rm -d \
    --name "$TUNNEL_CONTAINER" \
    -p "127.0.0.1:${TUNNEL_PORT}:3306" \
    --network "$NETWORK_NAME" \
    "$APP_DB_TUNNEL_IMAGE" "TCP-LISTEN:3306,fork,reuseaddr" "TCP:${CONTAINER_NAME}:3306" 2>&1)"; then
    docker rm -f "$TUNNEL_CONTAINER" >/dev/null 2>&1 || true
    case "$RUN_OUTPUT" in
      *"port is already allocated"*|*"address already in use"*)
        echo -e "${RED}[Error]${RESET} 127.0.0.1:${TUNNEL_PORT} is already in use. Run 'make db-tunnel stop', or pick another port: make db-tunnel start <port>" >&2
        ;;
      *)
        echo -e "${RED}[Error]${RESET} Could not start the tunnel:" >&2
        printf '%s\n' "$RUN_OUTPUT" >&2
        ;;
    esac
    exit 1
  fi

  READY_PORT="$(published_port)"
  READY_PORT="${READY_PORT:-unknown}"
  echo -e "${GREEN}[db-tunnel]${RESET} Local tunnel ready: 127.0.0.1:${READY_PORT} → ${CONTAINER_NAME}:3306"
  echo "[db-tunnel] Connect DBeaver/HeidiSQL to 127.0.0.1:${READY_PORT}"
  echo "[db-tunnel] Stop with: make db-tunnel stop"
}

cmd_stop() {
  if ! docker container inspect "$TUNNEL_CONTAINER" >/dev/null 2>&1; then
    echo "[db-tunnel] Tunnel is not running."
    return 0
  fi

  if ! docker rm -f "$TUNNEL_CONTAINER" >/dev/null; then
    echo -e "${RED}[Error]${RESET} Failed to remove ${TUNNEL_CONTAINER}." >&2
    exit 1
  fi

  echo -e "${GREEN}[db-tunnel]${RESET} Tunnel stopped."
}

cmd_status() {
  if tunnel_is_running; then
    ACTUAL_PORT="$(published_port)"
    echo -e "${GREEN}[db-tunnel]${RESET} Tunnel running on 127.0.0.1:${ACTUAL_PORT:-unknown} → ${CONTAINER_NAME}:3306"
  elif docker container inspect "$TUNNEL_CONTAINER" >/dev/null 2>&1; then
    echo "[db-tunnel] Tunnel container exists but is not running. Run 'make db-tunnel start' to recreate it."
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
