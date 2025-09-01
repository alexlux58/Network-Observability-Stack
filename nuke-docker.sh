#!/usr/bin/env bash
set -Eeuo pipefail

# Nuke all containers & images (keep volumes). Supports snap-docker.
# Usage: ./nuke-docker.sh [--bounce-snap] [--remove-networks]
#   --bounce-snap     : restart the snap docker daemon first (helps when stop/rm says "permission denied")
#   --remove-networks : also remove custom docker networks (non-default)

REMOVE_NETWORKS=0
BOUNCE_SNAP=0
for arg in "$@"; do
  case "$arg" in
    --remove-networks) REMOVE_NETWORKS=1 ;;
    --bounce-snap)     BOUNCE_SNAP=1 ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done

log(){ printf "\033[1;36m==> %s\033[0m\n" "$*"; }
warn(){ printf "\033[1;33m[!] %s\033[0m\n" "$*"; }
err(){  printf "\033[1;31m[✗] %s\033[0m\n" "$*"; }

detect_socket() {
  if [ -S /var/run/docker.sock ]; then
    export DOCKER_HOST=unix:///var/run/docker.sock
    return 0
  elif [ -S /var/snap/docker/common/run/docker.sock ]; then
    export DOCKER_HOST=unix:///var/snap/docker/common/run/docker.sock
    return 0
  fi
  return 1
}

ensure_docker() {
  if [ "$BOUNCE_SNAP" -eq 1 ]; then
    log "Bouncing snap docker daemon"
    sudo snap restart docker || {
      warn "snap restart failed; trying start"
      sudo snap start docker || true
    }
    sleep 3
  fi

  detect_socket || true

  DOCKER="docker"
  if ! $DOCKER info >/dev/null 2>&1; then
    DOCKER="sudo docker"
  fi

  if ! $DOCKER info >/dev/null 2>&1; then
    if [ -S /var/snap/docker/common/run/docker.sock ] && [ ! -S /var/run/docker.sock ]; then
      log "Linking snap socket to /var/run/docker.sock"
      sudo ln -sf /var/snap/docker/common/run/docker.sock /var/run/docker.sock || true
      unset DOCKER_HOST
    fi
  fi

  if ! $DOCKER info >/dev/null 2>&1; then
    err "Cannot connect to the Docker daemon. Try: sudo snap logs docker -n 200"
    exit 1
  fi

  echo "$DOCKER"
}

main() {
  DOCKER="$(ensure_docker)"
  DOCKER="${DOCKER# }"

  log "Disabling restart policies (to prevent respawn)"
  ids="$($DOCKER ps -aq || true)"
  if [ -n "${ids}" ]; then
    $DOCKER update --restart=no $ids || true
  else
    warn "No containers found."
  fi

  log "Stopping containers"
  if [ -n "${ids}" ]; then
    $DOCKER stop $ids || true
  fi

  log "Removing containers"
  if [ -n "${ids}" ]; then
    $DOCKER rm -f $ids || true
  fi

  log "Removing images"
  imgs="$($DOCKER images -q || true)"
  if [ -n "${imgs}" ]; then
    $DOCKER rmi -f $imgs || true
  else
    warn "No images found."
  fi

  if [ "$REMOVE_NETWORKS" -eq 1 ]; then
    log "Removing custom networks"
    nets="$($DOCKER network ls --format '{{.Name}}' | grep -Ev '^(bridge|host|none)$' || true)"
    if [ -n "${nets}" ]; then
      for n in ${nets}; do
        $DOCKER network rm "$n" || true
      done
    else
      warn "No custom networks to remove."
    fi
  else
    warn "Custom networks preserved (use --remove-networks to delete)."
  fi

  log "Pruning caches (keeping volumes)"
  $DOCKER system prune -f --volumes=false || true

  echo
  log "Post-clean status"
  $DOCKER ps -a || true
  $DOCKER images || true

  echo
  warn "Named/anonymous Docker VOLUMES were NOT removed (your ./data/* bind mounts are safe)."
  warn "If you truly want volumes gone too, run:  $DOCKER volume prune  (DANGEROUS: removes ALL volumes!)"
}

main "$@"
