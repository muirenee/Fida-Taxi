#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${FIDA_DEPLOY_ENV_FILE:-$ROOT_DIR/.env}"
RUNTIME_ROOT="$ROOT_DIR/.runtime"
BACKEND_DIR="$RUNTIME_ROOT/fida-ride"
BACKEND_COMPOSE="$BACKEND_DIR/docker-compose.yml"

log() {
  printf '[fida-server] %s\n' "$*"
}

fail() {
  printf '[fida-server] ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: ./deploy/backend.sh <command>

Commands:
  init            Create .env and generate required local secrets.
  sync            Synchronize the authoritative Fida-Ride backend source.
  config          Validate the backend Docker Compose configuration.
  up              Start PostgreSQL/Redis, apply migrations, then start API/telemetry.
  migrate         Apply pending migrations on a fresh/managed database.
  adopt-existing  Baseline an existing pre-v12 database through v11, then migrate forward.
  restart         Restart the NestJS API and Go telemetry services.
  status          Show Docker Compose service status.
  health          Check local API and telemetry health endpoints.
  logs            Follow backend service logs.
  down            Stop the backend stack without deleting database data.
  version         Show the synchronized backend commit.
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

  FIDA_BACKEND_REPOSITORY="${FIDA_BACKEND_REPOSITORY:-https://github.com/muirenee/Fida-Ride.git}"
  FIDA_BACKEND_REF="${FIDA_BACKEND_REF:-main}"
  POSTGRES_DB="${POSTGRES_DB:-fida_ride}"
  POSTGRES_USER="${POSTGRES_USER:-fida_ride}"
  NESTJS_CORE_PORT="${NESTJS_CORE_PORT:-3000}"
  GO_TELEMETRY_PORT="${GO_TELEMETRY_PORT:-8080}"
  SERVICE_BIND_IP="${SERVICE_BIND_IP:-127.0.0.1}"
}

require_env_file() {
  [[ -f "$ENV_FILE" ]] || fail "Missing $ENV_FILE. Run ./deploy/backend.sh init first."
  load_env

  local required=(
    POSTGRES_PASSWORD
    REDIS_PASSWORD
    JWT_HS256_SECRET
    OTP_HMAC_SECRET
  )
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
  log "Created $ENV_FILE with generated server secrets."
}

sync_backend() {
  require_command git
  load_env
  mkdir -p "$RUNTIME_ROOT"

  if [[ ! -d "$BACKEND_DIR/.git" ]]; then
    log "Cloning backend into $BACKEND_DIR"
    git clone "$FIDA_BACKEND_REPOSITORY" "$BACKEND_DIR"
  fi

  git -C "$BACKEND_DIR" remote set-url origin "$FIDA_BACKEND_REPOSITORY"
  git -C "$BACKEND_DIR" fetch --prune origin

  if git -C "$BACKEND_DIR" rev-parse --verify --quiet "origin/$FIDA_BACKEND_REF" >/dev/null; then
    git -C "$BACKEND_DIR" checkout --detach "origin/$FIDA_BACKEND_REF"
  else
    git -C "$BACKEND_DIR" fetch origin "$FIDA_BACKEND_REF"
    git -C "$BACKEND_DIR" checkout --detach FETCH_HEAD
  fi

  log "Backend synchronized at $(git -C "$BACKEND_DIR" rev-parse --short HEAD)."
}

compose() {
  require_env_file
  [[ -f "$BACKEND_COMPOSE" ]] || fail "Backend source is not synchronized. Run ./deploy/backend.sh sync first."
  docker compose --env-file "$ENV_FILE" -f "$BACKEND_COMPOSE" "$@"
}

validate_config() {
  require_command docker
  docker compose version >/dev/null
  compose config --quiet
  log 'Docker Compose configuration is valid.'
}

wait_for_postgres() {
  local attempt
  for attempt in $(seq 1 60); do
    if compose exec -T postgres sh -lc 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"' >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  compose logs postgres >&2 || true
  fail 'PostgreSQL did not become ready.'
}

psql_input() {
  compose exec -T postgres sh -lc \
    'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
}

psql_scalar() {
  local sql="$1"
  printf '%s\n' "$sql" | compose exec -T postgres sh -lc \
    'psql -At -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
}

ensure_migration_ledger() {
  cat <<'SQL' | psql_input >/dev/null
CREATE TABLE IF NOT EXISTS public.fida_schema_migrations (
    filename TEXT PRIMARY KEY,
    sha256 CHAR(64) NOT NULL,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
SQL
}

migration_files() {
  printf '%s\n' "$BACKEND_DIR"/database/migrations/schema-v*.sql | sort -V
}

record_migration() {
  local file="$1"
  local checksum="$2"
  local filename
  filename="$(basename "$file")"
  printf "INSERT INTO public.fida_schema_migrations (filename, sha256) VALUES ('%s', '%s') ON CONFLICT (filename) DO NOTHING;\n" \
    "$filename" "$checksum" | psql_input >/dev/null
}

apply_pending_migrations() {
  ensure_migration_ledger

  local file filename checksum recorded
  while IFS= read -r file; do
    [[ -f "$file" ]] || continue
    filename="$(basename "$file")"
    checksum="$(sha256sum "$file" | awk '{print $1}')"
    recorded="$(psql_scalar "SELECT sha256 FROM public.fida_schema_migrations WHERE filename = '$filename';")"

    if [[ -n "$recorded" ]]; then
      [[ "$recorded" == "$checksum" ]] || fail "Migration checksum changed after apply: $filename"
      log "Migration already applied: $filename"
      continue
    fi

    log "Applying migration: $filename"
    psql_input < "$file" >/dev/null
    record_migration "$file" "$checksum"
  done < <(migration_files)
}

migrate() {
  require_command sha256sum
  sync_backend
  require_env_file
  compose up -d postgres redis
  wait_for_postgres

  psql_input < "$BACKEND_DIR/init-db.sql" >/dev/null

  local ledger_exists core_exists
  ledger_exists="$(psql_scalar "SELECT to_regclass('public.fida_schema_migrations') IS NOT NULL;")"
  core_exists="$(psql_scalar "SELECT to_regclass('core.users') IS NOT NULL;")"

  if [[ "$core_exists" == 't' && "$ledger_exists" != 't' ]]; then
    fail "Existing Fida-Ride schema detected without migration history. Run ./deploy/backend.sh adopt-existing once, then ./deploy/backend.sh up."
  fi

  apply_pending_migrations
  log 'Database migrations are current.'
}

adopt_existing() {
  require_command sha256sum
  sync_backend
  require_env_file
  compose up -d postgres redis
  wait_for_postgres

  local core_exists
  core_exists="$(psql_scalar "SELECT to_regclass('core.users') IS NOT NULL;")"
  [[ "$core_exists" == 't' ]] || fail 'No existing core.users table found. Use ./deploy/backend.sh migrate instead.'

  ensure_migration_ledger

  local file filename version checksum
  while IFS= read -r file; do
    [[ -f "$file" ]] || continue
    filename="$(basename "$file")"
    if [[ "$filename" =~ ^schema-v([0-9]+) ]]; then
      version="${BASH_REMATCH[1]}"
      if (( version <= 11 )); then
        checksum="$(sha256sum "$file" | awk '{print $1}')"
        record_migration "$file" "$checksum"
        log "Baselined existing migration: $filename"
      fi
    fi
  done < <(migration_files)

  apply_pending_migrations
  log 'Existing database adopted and migrated forward.'
}

start_stack() {
  require_command docker
  docker compose version >/dev/null
  sync_backend
  require_env_file
  validate_config

  compose up -d postgres redis
  wait_for_postgres

  local ledger_exists core_exists
  psql_input < "$BACKEND_DIR/init-db.sql" >/dev/null
  ledger_exists="$(psql_scalar "SELECT to_regclass('public.fida_schema_migrations') IS NOT NULL;")"
  core_exists="$(psql_scalar "SELECT to_regclass('core.users') IS NOT NULL;")"
  if [[ "$core_exists" == 't' && "$ledger_exists" != 't' ]]; then
    fail "Existing database needs one-time adoption. Run ./deploy/backend.sh adopt-existing, then ./deploy/backend.sh up."
  fi
  apply_pending_migrations

  log 'Building and starting NestJS API and Go telemetry services.'
  compose up -d --build nestjs-core-api go-telemetry-service
  compose ps
}

health() {
  require_command curl
  load_env

  local health_host="$SERVICE_BIND_IP"
  if [[ "$health_host" == '0.0.0.0' || "$health_host" == '::' ]]; then
    health_host='127.0.0.1'
  fi

  log "Checking NestJS API on http://${health_host}:${NESTJS_CORE_PORT}/api/v1/healthz"
  curl --fail --silent --show-error \
    "http://${health_host}:${NESTJS_CORE_PORT}/api/v1/healthz"
  printf '\n'

  log "Checking Go telemetry on http://${health_host}:${GO_TELEMETRY_PORT}/healthz"
  curl --fail --silent --show-error \
    "http://${health_host}:${GO_TELEMETRY_PORT}/healthz"
  printf '\n'

  if [[ -n "${FIDA_API_PUBLIC_URL:-}" ]]; then
    log "Checking public API at ${FIDA_API_PUBLIC_URL%/}/healthz"
    curl --fail --silent --show-error "${FIDA_API_PUBLIC_URL%/}/healthz"
    printf '\n'
  fi
}

show_version() {
  sync_backend
  git -C "$BACKEND_DIR" show -s --format='backend %H%ncommit date: %cI%nsubject: %s' HEAD
}

main() {
  local command="${1:-}"
  shift || true

  case "$command" in
    init)
      init_env
      ;;
    sync)
      sync_backend
      ;;
    config)
      sync_backend
      validate_config
      ;;
    up)
      start_stack
      ;;
    migrate)
      migrate
      ;;
    adopt-existing)
      adopt_existing
      ;;
    restart)
      sync_backend
      compose restart nestjs-core-api go-telemetry-service
      ;;
    status)
      sync_backend
      compose ps
      ;;
    health)
      require_env_file
      health
      ;;
    logs)
      sync_backend
      compose logs -f --tail=200 "$@"
      ;;
    down)
      sync_backend
      compose down
      ;;
    version)
      show_version
      ;;
    -h|--help|help|'')
      usage
      ;;
    *)
      usage >&2
      fail "Unknown command: $command"
      ;;
  esac
}

main "$@"
