#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${FIDA_DEPLOY_ENV_FILE:-$ROOT_DIR/.env}"
COMPOSE_FILE="$ROOT_DIR/deploy/docker-compose.yml"

log() {
  printf '[fida-taxi] %s\n' "$*"
}

fail() {
  printf '[fida-taxi] ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: ./deploy/backend.sh <command>

Commands:
  init      Create Fida-Taxi .env with independent secrets.
  config    Validate the Fida-Taxi Docker Compose configuration.
  up        Start the isolated Fida-Taxi backend stack.
  restart   Restart Fida-Taxi API and telemetry services.
  status    Show only Fida-Taxi service status.
  health    Check Fida-Taxi API and telemetry health endpoints.
  logs      Follow Fida-Taxi service logs.
  down      Stop only the Fida-Taxi backend stack.
  doctor    Show Fida-Taxi container/data isolation details.
EOF
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

load_env() {
  if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
  fi

  POSTGRES_DB="${POSTGRES_DB:-fida_taxi}"
  POSTGRES_USER="${POSTGRES_USER:-fida_taxi}"
  NESTJS_CORE_PORT="${NESTJS_CORE_PORT:-3100}"
  GO_TELEMETRY_PORT="${GO_TELEMETRY_PORT:-8180}"
  SERVICE_BIND_IP="${SERVICE_BIND_IP:-127.0.0.1}"
}

require_env_file() {
  [[ -f "$ENV_FILE" ]] || fail "Missing $ENV_FILE. Run ./deploy/backend.sh init first."
  load_env

  local required=(POSTGRES_PASSWORD REDIS_PASSWORD JWT_HS256_SECRET OTP_HMAC_SECRET)
  local key
  for key in "${required[@]}"; do
    [[ -n "${!key:-}" ]] || fail "$key is empty in $ENV_FILE"
  done
}

replace_env_value() {
  local key="$1"
  local value="$2"
  sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
}

init_env() {
  require_command openssl
  if [[ -f "$ENV_FILE" ]]; then
    log "$ENV_FILE already exists; leaving it unchanged."
    return 0
  fi

  umask 077
  cp "$ROOT_DIR/.env.example" "$ENV_FILE"
  replace_env_value POSTGRES_PASSWORD "$(openssl rand -hex 32)"
  replace_env_value REDIS_PASSWORD "$(openssl rand -hex 32)"
  replace_env_value JWT_HS256_SECRET "$(openssl rand -hex 32)"
  replace_env_value OTP_HMAC_SECRET "$(openssl rand -hex 32)"
  chmod 600 "$ENV_FILE"
  log "Created isolated Fida-Taxi environment at $ENV_FILE."
}

compose() {
  require_env_file
  docker compose --project-name fida-taxi --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
}

validate_config() {
  require_command docker
  docker compose version >/dev/null
  compose config --quiet
  log 'Fida-Taxi Docker Compose configuration is valid.'
}

start_stack() {
  validate_config
  compose up -d --build
  compose ps
}

health() {
  require_command curl
  load_env

  local health_host="$SERVICE_BIND_IP"
  if [[ "$health_host" == '0.0.0.0' || "$health_host" == '::' ]]; then
    health_host='127.0.0.1'
  fi

  log "Checking Fida-Taxi API on http://${health_host}:${NESTJS_CORE_PORT}/api/v1/healthz"
  curl --fail --silent --show-error "http://${health_host}:${NESTJS_CORE_PORT}/api/v1/healthz"
  printf '\n'

  log "Checking Fida-Taxi telemetry on http://${health_host}:${GO_TELEMETRY_PORT}/healthz"
  curl --fail --silent --show-error "http://${health_host}:${GO_TELEMETRY_PORT}/healthz"
  printf '\n'

  if [[ -n "${FIDA_API_PUBLIC_URL:-}" ]]; then
    log "Checking public Fida-Taxi API at ${FIDA_API_PUBLIC_URL%/}/healthz"
    curl --fail --silent --show-error "${FIDA_API_PUBLIC_URL%/}/healthz"
    printf '\n'
  fi
}

doctor() {
  load_env
  cat <<EOF
Fida-Taxi project root: $ROOT_DIR
Compose project: fida-taxi
Compose file: $COMPOSE_FILE
Environment file: $ENV_FILE
PostgreSQL container: fida-taxi-postgres
Redis container: fida-taxi-redis
API container: fida-taxi-api
Telemetry container: fida-taxi-telemetry
PostgreSQL data volume: fida-taxi-postgres-data
Redis data volume: fida-taxi-redis-data
API port: ${NESTJS_CORE_PORT}
Telemetry port: ${GO_TELEMETRY_PORT}

Fida-Ride containers are intentionally not referenced or managed by this script.
EOF
}

main() {
  local command="${1:-}"
  shift || true

  case "$command" in
    init) init_env ;;
    config) validate_config ;;
    up) start_stack ;;
    restart) compose restart api telemetry ;;
    status) compose ps ;;
    health) require_env_file; health ;;
    logs) compose logs -f --tail=200 "$@" ;;
    down) compose down ;;
    doctor) doctor ;;
    -h|--help|help|'') usage ;;
    *) usage >&2; fail "Unknown command: $command" ;;
  esac
}

main "$@"
