# Fida Taxi Server Operations

`Fida-Taxi` is a completely independent project from `Fida-Ride`.

It has its own backend source, database, Redis instance, telemetry service, Docker network, volumes, secrets, container names, and host ports. This deployment must never start, stop, migrate, reuse, or modify any `fida-ride-*` container or Fida-Ride data directory.

## Fida-Taxi services

From `~/docker/Fida-Taxi`, the stack manages only:

- `fida-taxi-postgres`
- `fida-taxi-redis`
- `fida-taxi-api`
- `fida-taxi-telemetry`

Persistent storage uses Docker volumes:

- `fida-taxi-postgres-data`
- `fida-taxi-redis-data`

The default host ports are intentionally different from Fida-Ride:

- PostgreSQL: `55432`
- Redis: `56379`
- NestJS API: `3100`
- Go telemetry: `8180`

## First start

```bash
cd ~/docker/Fida-Taxi
./deploy/backend.sh init
./deploy/backend.sh doctor
./deploy/backend.sh config
./deploy/backend.sh up
./deploy/backend.sh health
```

`init` creates `~/docker/Fida-Taxi/.env` with independent PostgreSQL, Redis, JWT, and OTP secrets. It does not read or reuse `~/docker/Fida-Ride/.env`.

## Day-to-day commands

```bash
./deploy/backend.sh doctor
./deploy/backend.sh status
./deploy/backend.sh health
./deploy/backend.sh logs
./deploy/backend.sh restart
./deploy/backend.sh down
```

`down` stops only the Fida-Taxi Compose project. It does not remove the Fida-Taxi named volumes and does not touch Fida-Ride.

## API

The local Core API health endpoint is:

```text
http://127.0.0.1:3100/api/v1/healthz
```

The local telemetry health endpoint is:

```text
http://127.0.0.1:8180/healthz
```

For real phones, put the Fida-Taxi API behind its own HTTPS hostname and set:

```text
FIDA_API_PUBLIC_URL=https://taxi-api.example.com/api/v1
```

The Rider and Driver APKs must be built with the same public API URL using `FIDA_API_BASE_URL`. The emulator-only default `10.0.2.2` must not be used for device testing.
