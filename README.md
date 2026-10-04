# Fida Taxi

Fida Taxi is a clean-architecture ride-hailing platform under active development.

## Workspace

- `apps/rider` — Flutter rider application
- `apps/driver` — Flutter driver application
- `packages/fida_core` — pure Dart domain layer
- `packages/fida_api` — typed transport client for the Fida-Ride backend
- `packages/fida_app_auth` — shared phone authentication UI/application layer
- `packages/fida_design_system` — shared Flutter design system
- `deploy` — server operations from the Fida-Taxi working directory

The mobile clients are deliberately non-authoritative for ride lifecycle, fares, dispatch, payments, and earnings. The authoritative NestJS, PostgreSQL/PostGIS, Redis, and Go telemetry backend source remains in `muirenee/Fida-Ride` and is synchronized automatically by the deployment wrapper.

## Mobile workspace bootstrap

```bash
chmod +x setup_workspace.sh
./setup_workspace.sh
```

## Server first start

From the Fida-Taxi repository root:

```bash
./deploy/backend.sh init
./deploy/backend.sh up
./deploy/backend.sh health
```

You do not need to manually clone or change directory into Fida-Ride. The wrapper maintains the backend checkout under `.runtime/fida-ride`.

For server status and logs:

```bash
./deploy/backend.sh status
./deploy/backend.sh logs
```

See `deploy/README.md` for migration handling, existing-database adoption, and public HTTPS/API configuration.

## Validation

```bash
dart run melos run format:check --no-select
dart run melos run analyze --no-select
dart run melos run test:dart --no-select
dart run melos run test:flutter --no-select
bash -n deploy/backend.sh
```
