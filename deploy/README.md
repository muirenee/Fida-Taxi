# Fida Taxi Server Operations

This directory makes `Fida-Taxi` the operational entry point for the server while preserving `muirenee/Fida-Ride` as the authoritative backend source repository.

The wrapper synchronizes the backend under `.runtime/fida-ride/`. That directory is ignored by Git and may contain the PostgreSQL data directory used by the backend Compose stack.

## First start

From `~/docker/Fida-Taxi`:

```bash
./deploy/backend.sh init
./deploy/backend.sh up
./deploy/backend.sh health
```

`init` creates the root `.env` with independent generated PostgreSQL, Redis, JWT, and OTP secrets. It never overwrites an existing `.env`.

`up` performs these operations in order:

1. Synchronizes the configured Fida-Ride backend ref.
2. Validates Docker Compose.
3. Starts PostgreSQL/PostGIS and Redis.
4. Applies tracked database migrations.
5. Builds and starts the NestJS Core API and Go telemetry service.

## Existing Fida-Ride database

If the PostgreSQL data already contains the old Fida-Ride schema but does not yet have the deployment migration ledger, `up` stops rather than guessing which migrations were previously executed.

For the current pre-v12 deployment, use the one-time adoption command:

```bash
./deploy/backend.sh adopt-existing
./deploy/backend.sh up
```

The adoption command records schema migrations v1-v11 as the existing baseline and then applies v12 and any later migrations.

## Day-to-day commands

```bash
./deploy/backend.sh status
./deploy/backend.sh health
./deploy/backend.sh logs
./deploy/backend.sh restart
./deploy/backend.sh down
./deploy/backend.sh version
```

`down` stops containers but does not delete PostgreSQL data.

## Network exposure

By default `.env.example` sets `SERVICE_BIND_IP=127.0.0.1`, so the API and telemetry services are deliberately private to the server host. Put an HTTPS reverse proxy in front of the NestJS API for real phones.

After the public API hostname is configured, set for example:

```text
FIDA_API_PUBLIC_URL=https://api.example.com/api/v1
```

Then `./deploy/backend.sh health` checks both the local Core API and the configured public URL.

The Rider and Driver APKs must also be built with that same public API URL. `10.0.2.2` is only an Android emulator development address.
