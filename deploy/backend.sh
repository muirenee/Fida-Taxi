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
  init      Create/repair Fida-Taxi .env with independent secrets.
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

legacy_env_file() {
  [[ -f "$ENV_FILE" ]] || return 1
  grep -Eq '^(FIDA_BACKEND_(REPOSITORY|REF|LOCAL_DIR|ENV_FILE)=|POSTGRES_DB=fida_ride$|POSTGRES_USER=fida_ride$|POSTGRES_PORT=5432$|REDIS_PORT=6379$|NESTJS_CORE_PORT=3000$|GO_TELEMETRY_PORT=8080$)' "$ENV_FILE"
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
  POSTGRES_PORT="${POSTGRES_PORT:-55432}"
  REDIS_PORT="${REDIS_PORT:-56379}"
  NESTJS_CORE_PORT="${NESTJS_CORE_PORT:-3100}"
  GO_TELEMETRY_PORT="${GO_TELEMETRY_PORT:-8180}"
  SERVICE_BIND_IP="${SERVICE_BIND_IP:-127.0.0.1}"
}

assert_isolated_env() {
  legacy_env_file && fail "Legacy Fida-Ride-coupled settings detected in $ENV_FILE. Run ./deploy/backend.sh init to back them up and create an isolated Fida-Taxi environment."

  [[ "$POSTGRES_DB" != 'fida_ride' ]] || fail 'POSTGRES_DB must not be fida_ride.'
  [[ "$POSTGRES_USER" != 'fida_ride' ]] || fail 'POSTGRES_USER must not be fida_ride.'
}

require_env_file() {
  [[ -f "$ENV_FILE" ]] || fail "Missing $ENV_FILE. Run ./deploy/backend.sh init first."
  load_env
  assert_isolated_env

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

create_isolated_env() {
  umask 077
  cp "$ROOT_DIR/.env.example" "$ENV_FILE"
  replace_env_value POSTGRES_PASSWORD "$(openssl rand -hex 32)"
  replace_env_value REDIS_PASSWORD "$(openssl rand -hex 32)"
  replace_env_value JWT_HS256_SECRET "$(openssl rand -hex 32)"
  replace_env_value OTP_HMAC_SECRET "$(openssl rand -hex 32)"
  chmod 600 "$ENV_FILE"
  log "Created isolated Fida-Taxi environment at $ENV_FILE."
}

init_env() {
  require_command openssl

  if [[ -f "$ENV_FILE" ]]; then
    if legacy_env_file; then
      local backup
      backup="${ENV_FILE}.pre-isolation-$(date -u +%Y%m%dT%H%M%SZ)"
      mv "$ENV_FILE" "$backup"
      log "Backed up legacy coupled environment to $backup."
      create_isolated_env
      return 0
    fi

    load_env
    assert_isolated_env
    log "$ENV_FILE is already an isolated Fida-Taxi environment; leaving it unchanged."
    return 0
  fi

  create_isolated_env
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
  require_env_file

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
  if [[ -f "$ENV_FILE" ]]; then
    load_env
    if legacy_env_file; then
      cat <<EOF
Fida-Taxi project root: $ROOT_DIR
Environment file: $ENV_FILE
Isolation status: LEGACY COUPLED SETTINGS DETECTED

Run: ./deploy/backend.sh init
The old file will be backed up and replaced with an isolated Fida-Taxi environment.
EOF
      return 2
    fi
    assert_isolated_env
  else
    load_env
  fi

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
PostgreSQL host port: ${POSTGRES_PORT}
Redis host port: ${REDIS_PORT}
API host port: ${NESTJS_CORE_PORT}
Telemetry host port: ${GO_TELEMETRY_PORT}
Isolation status: OK

Fida-Ride containers, volumes, environment files, and repositories are not referenced or managed by this script.
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
    health) health ;;
    logs) compose logs -f --tail=200 "$@" ;;
    down) compose down ;;
    doctor) doctor ;;
    -h|--help|help|'') usage ;;
    *) usage >&2; fail "Unknown command: $command" ;;
  esac
}

main "$@"
