#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTROL_ENV_FILE="${FIDA_DEPLOY_ENV_FILE:-$ROOT_DIR/.env}"
RUNTIME_ROOT="$ROOT_DIR/.runtime"
SIBLING_BACKEND_DIR="$(cd "$ROOT_DIR/.." && pwd)/Fida-Ride"
MANAGED_BACKEND_DIR="$RUNTIME_ROOT/fida-ride"
BACKEND_DIR=''
BACKEND_COMPOSE=''
BACKEND_ENV_FILE=''
BACKEND_MODE=''

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
  init            Initialize deployment settings without replacing an existing Fida-Ride environment.
  sync            Safely synchronize the selected Fida-Ride checkout.
  config          Validate the selected backend Docker Compose configuration.
  doctor          Show which Fida-Ride checkout/data directory the containers use.
  up              Start/reuse PostgreSQL/Redis, apply migrations, then start API/telemetry.
  migrate         Apply pending migrations on a fresh/managed database.
  adopt-existing  Baseline an existing pre-v12 database through v11, then migrate forward.
  restart         Restart the NestJS API and Go telemetry services.
  status          Show Docker Compose service status.
  health          Check local API and telemetry health endpoints.
  logs            Follow backend service logs.
  down            Stop the selected backend stack without deleting database data.
  version         Show the selected backend commit.
EOF
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

load_control_env() {
  if [[ -f "$CONTROL_ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$CONTROL_ENV_FILE"
    set +a
  fi

  FIDA_BACKEND_REPOSITORY="${FIDA_BACKEND_REPOSITORY:-https://github.com/muirenee/Fida-Ride.git}"
  FIDA_BACKEND_REF="${FIDA_BACKEND_REF:-main}"
}

resolve_backend() {
  load_control_env

  if [[ -n "${FIDA_BACKEND_LOCAL_DIR:-}" ]]; then
    BACKEND_DIR="${FIDA_BACKEND_LOCAL_DIR/#\~/$HOME}"
    BACKEND_MODE='existing'
  elif [[ -d "$SIBLING_BACKEND_DIR/.git" && -f "$SIBLING_BACKEND_DIR/docker-compose.yml" ]]; then
    BACKEND_DIR="$SIBLING_BACKEND_DIR"
    BACKEND_MODE='existing'
  else
    BACKEND_DIR="$MANAGED_BACKEND_DIR"
    BACKEND_MODE='managed'
  fi

  BACKEND_COMPOSE="$BACKEND_DIR/docker-compose.yml"

  if [[ -n "${FIDA_BACKEND_ENV_FILE:-}" ]]; then
    BACKEND_ENV_FILE="${FIDA_BACKEND_ENV_FILE/#\~/$HOME}"
  elif [[ "$BACKEND_MODE" == 'existing' ]]; then
    BACKEND_ENV_FILE="$BACKEND_DIR/.env"
  else
    BACKEND_ENV_FILE="$CONTROL_ENV_FILE"
  fi
}

load_backend_env() {
  resolve_backend
  [[ -f "$BACKEND_ENV_FILE" ]] || {
    if [[ "$BACKEND_MODE" == 'existing' ]]; then
      fail "Existing Fida-Ride checkout detected at $BACKEND_DIR but $BACKEND_ENV_FILE is missing. Configure the backend in Fida-Ride; do not generate a second database environment from Fida-Taxi."
    fi
    fail "Missing $BACKEND_ENV_FILE. Run ./deploy/backend.sh init first."
  }

  set -a
  # shellcheck disable=SC1090
  source "$BACKEND_ENV_FILE"
  set +a

  POSTGRES_DB="${POSTGRES_DB:-fida_ride}"
  POSTGRES_USER="${POSTGRES_USER:-fida_ride}"
  NESTJS_CORE_PORT="${NESTJS_CORE_PORT:-3000}"
  GO_TELEMETRY_PORT="${GO_TELEMETRY_PORT:-8080}"
  SERVICE_BIND_IP="${SERVICE_BIND_IP:-127.0.0.1}"

  local required=(
    POSTGRES_PASSWORD
    REDIS_PASSWORD
    JWT_HS256_SECRET
    OTP_HMAC_SECRET
  )
  local key
  for key in "${required[@]}"; do
    [[ -n "${!key:-}" ]] || fail "$key is empty in $BACKEND_ENV_FILE"
  done
}

replace_env_value() {
  local key="$1"
  local value="$2"
  sed -i "s|^${key}=.*|${key}=${value}|" "$CONTROL_ENV_FILE"
}

init_env() {
  require_command openssl
  resolve_backend

  if [[ "$BACKEND_MODE" == 'existing' ]]; then
    log "Existing Fida-Ride checkout detected at $BACKEND_DIR."
    if [[ -f "$BACKEND_ENV_FILE" ]]; then
      log "Using its existing environment: $BACKEND_ENV_FILE"
      log 'No PostgreSQL/Redis/JWT/OTP secrets were generated or replaced.'
      return 0
    fi
    fail "The existing backend has no $BACKEND_ENV_FILE. Configure Fida-Ride first; Fida-Taxi will not create a parallel database environment."
  fi

  if [[ -f "$CONTROL_ENV_FILE" ]]; then
    log "$CONTROL_ENV_FILE already exists; leaving it unchanged."
    return 0
  fi

  umask 077
  cp "$ROOT_DIR/.env.example" "$CONTROL_ENV_FILE"
  replace_env_value POSTGRES_PASSWORD "$(openssl rand -hex 32)"
  replace_env_value REDIS_PASSWORD "$(openssl rand -hex 32)"
  replace_env_value JWT_HS256_SECRET "$(openssl rand -hex 32)"
  replace_env_value OTP_HMAC_SECRET "$(openssl rand -hex 32)"
  chmod 600 "$CONTROL_ENV_FILE"
  log "Created $CONTROL_ENV_FILE with generated server secrets for managed-backend mode."
}

sync_backend() {
  require_command git
  resolve_backend

  if [[ "$BACKEND_MODE" == 'existing' ]]; then
    [[ -d "$BACKEND_DIR/.git" ]] || fail "Configured Fida-Ride checkout is not a Git repository: $BACKEND_DIR"
    [[ -f "$BACKEND_COMPOSE" ]] || fail "Missing $BACKEND_COMPOSE"

    local branch
    branch="$(git -C "$BACKEND_DIR" symbolic-ref --quiet --short HEAD || true)"
    if [[ "$branch" == "$FIDA_BACKEND_REF" ]]; then
      if ! git -C "$BACKEND_DIR" diff --quiet || ! git -C "$BACKEND_DIR" diff --cached --quiet; then
        fail "Existing Fida-Ride checkout has uncommitted changes. Commit/stash them before synchronization."
      fi
      git -C "$BACKEND_DIR" fetch --prune origin "$FIDA_BACKEND_REF"
      git -C "$BACKEND_DIR" merge --ff-only "origin/$FIDA_BACKEND_REF"
    else
      log "Using existing Fida-Ride checkout on branch ${branch:-detached}; not switching it automatically."
    fi

    log "Using existing backend at $BACKEND_DIR ($(git -C "$BACKEND_DIR" rev-parse --short HEAD))."
    return 0
  fi

  mkdir -p "$RUNTIME_ROOT"
  if [[ ! -d "$BACKEND_DIR/.git" ]]; then
    log "No sibling Fida-Ride checkout found; cloning fallback backend into $BACKEND_DIR"
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

  log "Fallback backend synchronized at $(git -C "$BACKEND_DIR" rev-parse --short HEAD)."
}

compose() {
  load_backend_env
  [[ -f "$BACKEND_COMPOSE" ]] || fail "Backend Compose file not found: $BACKEND_COMPOSE"
  docker compose --env-file "$BACKEND_ENV_FILE" -f "$BACKEND_COMPOSE" "$@"
}

expected_postgres_data_dir() {
  resolve_backend
  readlink -m "$BACKEND_DIR/.data/postgres"
}

current_postgres_data_dir() {
  docker inspect fida-ride-postgres \
    --format '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql/data"}}{{.Source}}{{end}}{{end}}' \
    2>/dev/null || true
}

assert_postgres_mount_safe() {
  require_command docker
  resolve_backend

  local actual expected
  actual="$(current_postgres_data_dir)"
  [[ -z "$actual" ]] && return 0

  expected="$(expected_postgres_data_dir)"
  actual="$(readlink -m "$actual")"

  if [[ "$actual" != "$expected" ]]; then
    fail "Existing fida-ride-postgres uses $actual, but the selected Fida-Ride checkout expects $expected. Refusing to recreate or repoint the database container. Run ./deploy/backend.sh doctor and inspect both data directories before continuing."
  fi
}

validate_config() {
  require_command docker
  docker compose version >/dev/null
  compose config --quiet
  log "Docker Compose configuration is valid for $BACKEND_DIR."
}

doctor() {
  require_command docker
  resolve_backend

  log "Backend mode: $BACKEND_MODE"
  log "Backend checkout: $BACKEND_DIR"
  log "Backend Compose: $BACKEND_COMPOSE"
  log "Backend environment: $BACKEND_ENV_FILE"
  log "Expected PostgreSQL data: $(expected_postgres_data_dir)"

  local actual
  actual="$(current_postgres_data_dir)"
  if [[ -z "$actual" ]]; then
    log 'fida-ride-postgres does not currently exist.'
    return 0
  fi

  log "Current fida-ride-postgres data: $(readlink -m "$actual")"
  assert_postgres_mount_safe
  log 'PostgreSQL container mount matches the selected Fida-Ride checkout.'
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
  resolve_backend
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
  load_backend_env
  assert_postgres_mount_safe
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
  load_backend_env
  assert_postgres_mount_safe
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
  load_backend_env
  validate_config
  assert_postgres_mount_safe

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
  load_control_env
  load_backend_env

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

show_status() {
  resolve_backend
  log "Using backend checkout: $BACKEND_DIR"
  compose ps
}

show_version() {
  resolve_backend
  [[ -d "$BACKEND_DIR/.git" ]] || fail "Backend source not found: $BACKEND_DIR"
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
      resolve_backend
      validate_config
      ;;
    doctor)
      doctor
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
      resolve_backend
      assert_postgres_mount_safe
      compose restart nestjs-core-api go-telemetry-service
      ;;
    status)
      show_status
      ;;
    health)
      health
      ;;
    logs)
      resolve_backend
      compose logs -f --tail=200 "$@"
      ;;
    down)
      resolve_backend
      assert_postgres_mount_safe
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
