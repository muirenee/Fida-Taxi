# Fida Taxi

Fida Taxi is a clean-architecture ride-hailing platform under active development.

## Workspace

- `apps/rider` — Flutter rider application
- `apps/driver` — Flutter driver application
- `packages/fida_core` — pure Dart domain layer
- `packages/fida_design_system` — shared Flutter design system

The mobile clients are deliberately non-authoritative for ride lifecycle, fares, dispatch, payments, and earnings. Those responsibilities will live in the backend services added in the next phases.

## Bootstrap

```bash
chmod +x setup_workspace.sh
./setup_workspace.sh
```

## Validation

```bash
dart run melos run format:check --no-select
dart run melos run analyze --no-select
dart run melos run test:dart --no-select
dart run melos run test:flutter --no-select
```
