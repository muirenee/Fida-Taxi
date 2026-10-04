# Fida Taxi

Fida Taxi is a clean-architecture ride-hailing platform under active development.

## Workspace

- `apps/rider` — Flutter rider application
- `apps/driver` — Flutter driver application
- `packages/fida_core` — pure Dart domain layer
- `packages/fida_api` — typed transport client for the Fida-Taxi backend
- `packages/fida_app_auth` — shared phone authentication UI/application layer
- `packages/fida_design_system` — shared Flutter design system
- `services/backend` — NestJS business API for Fida-Taxi
- `services/telemetry` — Go telemetry service for Fida-Taxi
- `deploy` — isolated Fida-Taxi Docker deployment

The mobile clients are deliberately non-authoritative for ride lifecycle, fares, dispatch, payments, and earnings. The authoritative Fida-Taxi backend lives in this repository.

`Fida-Ride` is a different project. Fida-Taxi does not clone, reuse, start, stop, migrate, or share databases/Redis/containers/secrets with Fida-Ride.

## Mobile workspace bootstrap

```bash
chmod +x setup_workspace.sh
./setup_workspace.sh
```

## Server first start

From the Fida-Taxi repository root:

```bash
./deploy/backend.sh init
./deploy/backend.sh doctor
./deploy/backend.sh config
./deploy/backend.sh up
./deploy/backend.sh health
```

For server status and logs:

```bash
./deploy/backend.sh status
./deploy/backend.sh logs
```

See `deploy/README.md` for service names, isolated ports, storage, and public HTTPS/API configuration.

## Validation

CI validates:

- deployment script syntax
- Docker Compose isolation
- NestJS typecheck and production build
- Go telemetry build/tests
- Dart formatting/static analysis/tests
- Flutter tests
- Rider and Driver Android debug APK builds
