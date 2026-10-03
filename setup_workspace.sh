#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

MODE="full"
if [[ $# -gt 0 ]]; then
  MODE="$1"
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "ERROR: Flutter is not installed or not available in PATH." >&2
  exit 1
fi

if ! command -v dart >/dev/null 2>&1; then
  echo "ERROR: Dart is not installed or not available in PATH." >&2
  exit 1
fi

ensure_native_shell() {
  local app_dir="$1"
  local project_name="$2"

  if [[ -d "$app_dir/android" && -d "$app_dir/ios" && -f "$app_dir/.metadata" ]]; then
    echo "Native shell already present for $project_name."
    return
  fi

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' RETURN

  echo "Generating Flutter native shell for $project_name..."

  flutter create     --no-pub     --platforms=android,ios     --org=com.fidalix     --project-name="$project_name"     "$tmp_dir/$project_name"

  if [[ ! -d "$app_dir/android" ]]; then
    cp -R "$tmp_dir/$project_name/android" "$app_dir/android"
  fi

  if [[ ! -d "$app_dir/ios" ]]; then
    cp -R "$tmp_dir/$project_name/ios" "$app_dir/ios"
  fi

  if [[ ! -f "$app_dir/.metadata" ]]; then
    cp "$tmp_dir/$project_name/.metadata" "$app_dir/.metadata"
  fi

  rm -rf "$tmp_dir"
  trap - RETURN
}

echo "Flutter toolchain:"
flutter --version
echo
echo "Dart toolchain:"
dart --version
echo

ensure_native_shell "apps/rider" "fida_taxi_rider"
ensure_native_shell "apps/driver" "fida_taxi_driver"

echo "Resolving workspace dependencies..."
flutter pub get

echo "Bootstrapping Melos workspace..."
dart run melos bootstrap

if [[ "$MODE" == "--bootstrap-only" ]]; then
  echo "Bootstrap complete."
  exit 0
fi

echo "Checking formatting..."
dart run melos run format:check --no-select

echo "Running static analysis..."
dart run melos run analyze --no-select

echo "Running pure Dart tests..."
dart run melos run test:dart --no-select

echo "Running Flutter tests..."
dart run melos run test:flutter --no-select

echo "Fida Taxi workspace validation completed successfully."
