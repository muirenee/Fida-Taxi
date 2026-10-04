# Fida Taxi Server Operations

`Fida-Taxi` is the product/mobile repository. `Fida-Ride` remains the authoritative backend repository.

## Existing sibling Fida-Ride is preferred

If this path exists:

```text
~/docker/Fida-Ride
```

then `deploy/backend.sh` automatically reuses that exact checkout, its `docker-compose.yml`, its `.env`, and its `.data/postgres` directory.

It does **not** clone another backend under `.runtime/fida-ride` in that case.

The `.runtime/fida-ride` checkout is only a fallback for hosts that do not already have a local Fida-Ride checkout.

You may override detection explicitly with:

```text
FIDA_BACKEND_LOCAL_DIR=/absolute/path/to/Fida-Ride
FIDA_BACKEND_ENV_FILE=/absolute/path/to/Fida-Ride/.env
```

## Safety check

Before starting or stopping the stack, the wrapper verifies the bind mount of the existing `fida-ride-postgres` container.

Run:

```bash
./deploy/backend.sh doctor
```

It shows:

- selected Fida-Ride checkout
- selected backend `.env`
- expected PostgreSQL data directory
- PostgreSQL data directory currently mounted into the running container

If they differ, `up`, `migrate`, `adopt-existing`, `restart`, and `down` refuse to proceed. This prevents a second checkout from silently recreating the same named container against a different database directory.

## Existing Fida-Ride deployment

For a host that already runs Fida-Ride:

```bash
cd ~/docker/Fida-Taxi
./deploy/backend.sh doctor
./deploy/backend.sh status
./deploy/backend.sh health
```

`init` does not generate new PostgreSQL/Redis/JWT/OTP secrets when an existing sibling Fida-Ride checkout is detected. It reuses the existing Fida-Ride `.env`.

To synchronize the existing backend safely:

```bash
./deploy/backend.sh sync
```

If the Fida-Ride checkout is on the configured branch (normally `main`) and clean, this performs a fast-forward-only update. It refuses to overwrite local changes.

## Starting/updating the existing stack

After `doctor` confirms the existing PostgreSQL container points to `~/docker/Fida-Ride/.data/postgres`:

```bash
./deploy/backend.sh up
./deploy/backend.sh health
```

`up` performs these operations in order:

1. Safely synchronizes the selected Fida-Ride checkout.
2. Validates its Docker Compose configuration.
3. Verifies that an existing PostgreSQL container uses the selected checkout's data directory.
4. Starts/reuses PostgreSQL/PostGIS and Redis.
5. Applies tracked database migrations.
6. Builds/starts the NestJS Core API and Go telemetry service.

## Existing pre-v12 database

If the PostgreSQL data already contains the old Fida-Ride schema but does not yet have the deployment migration ledger, `up` stops rather than guessing which migrations were previously executed.

For the current pre-v12 deployment, use the one-time adoption command:

```bash
./deploy/backend.sh adopt-existing
./deploy/backend.sh up
```

The adoption command records schema migrations v1-v11 as the existing baseline and then applies v12 and any later migrations.

## Day-to-day commands

```bash
./deploy/backend.sh doctor
./deploy/backend.sh status
./deploy/backend.sh health
./deploy/backend.sh logs
./deploy/backend.sh restart
./deploy/backend.sh down
./deploy/backend.sh version
```

`down` stops containers but never deletes PostgreSQL data.

## Network exposure

By default the API and telemetry services should stay private on `127.0.0.1` behind an HTTPS reverse proxy.

After the public API hostname is configured, set for example:

```text
FIDA_API_PUBLIC_URL=https://api.example.com/api/v1
```

Then `./deploy/backend.sh health` checks both the local Core API and the configured public URL.

The Rider and Driver APKs must be built with that same public API URL. `10.0.2.2` is only an Android emulator development address.
