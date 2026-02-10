#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGURATION="${CONFIGURATION:-Release}"
DIST_DIR="${DIST_DIR:-}"
MODULEMAP_TEMPLATE="${MODULEMAP_TEMPLATE:-"$ROOT_DIR/module.modulemap.template"}"
OUTPUT_PATH="${OUTPUT_PATH:-}"
LIB_NAME="${LIB_NAME:-msquic}"
XCRUN="${XCRUN:-xcrun}"
XCODEBUILD="${XCODEBUILD:-xcodebuild}"
SEVEN_Z="${SEVEN_Z:-7z}"

PLATFORMS=(ios ios-simulator macos)

run() {
  echo "+ $*"
  "$@"
}

die() {
  echo "error: $*" >&2
  exit 1
}

resolve_msquic_tag() {
  local raw_tag

  raw_tag="$(git -C "$ROOT_DIR/dependencies/msquic" describe --tags --exact-match 2>/dev/null || true)"
  if [ -z "$raw_tag" ]; then
    raw_tag="$(git -C "$ROOT_DIR/dependencies/msquic" describe --tags --abbrev=0 2>/dev/null || true)"
  fi
  if [ -z "$raw_tag" ]; then
    raw_tag="$(git -C "$ROOT_DIR/dependencies/msquic" rev-parse --short HEAD)"
  fi

  printf "%s" "${raw_tag#v}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --configuration)
      [ $# -ge 2 ] || die "missing value for --configuration"
      CONFIGURATION="$2"
      shift 2
      ;;
    --dist-dir)
      [ $# -ge 2 ] || die "missing value for --dist-dir"
      DIST_DIR="$2"
      shift 2
      ;;
    --output)
      [ $# -ge 2 ] || die "missing value for --output"
      OUTPUT_PATH="$2"
      shift 2
      ;;
    --help|-h)
      cat <<EOF
Usage: $(basename "$0") [--configuration Release|Debug] [--dist-dir PATH] [--output PATH]
EOF
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

case "$CONFIGURATION" in
  Debug|debug)
    CONFIGURATION="Debug"
    [ -n "$DIST_DIR" ] || DIST_DIR="$ROOT_DIR/dist_debug"
    ;;
  Release|release)
    CONFIGURATION="Release"
    [ -n "$DIST_DIR" ] || DIST_DIR="$ROOT_DIR/dist"
    ;;
  *)
    die "unsupported configuration: $CONFIGURATION (expected Release or Debug)"
    ;;
esac

[ -n "$OUTPUT_PATH" ] || OUTPUT_PATH="$DIST_DIR/MsQuic.xcframework"
[ -f "$MODULEMAP_TEMPLATE" ] || die "modulemap template not found: $MODULEMAP_TEMPLATE"
[ -e "$ROOT_DIR/dependencies/msquic/.git" ] || die "msquic git repository not found: $ROOT_DIR/dependencies/msquic"
command -v swift >/dev/null 2>&1 || die "swift command not found"
if ! command -v "$SEVEN_Z" >/dev/null 2>&1; then
  if command -v 7zz >/dev/null 2>&1; then
    SEVEN_Z="7zz"
  else
    die "7z command not found (install 7z/7zz or set SEVEN_Z)"
  fi
fi

args=()
for platform in "${PLATFORMS[@]}"; do
  headers="$DIST_DIR/$platform/include"
  lib="$DIST_DIR/$platform/lib/lib${LIB_NAME}.a"
  [ -d "$headers" ] || die "missing headers: $headers"
  [ -f "$lib" ] || die "missing library: $lib"
  cp "$MODULEMAP_TEMPLATE" "$headers/module.modulemap"
  args+=( -library "$lib" -headers "$headers" )
done

if [ -e "$OUTPUT_PATH" ]; then
  rm -rf "$OUTPUT_PATH"
fi

run "$XCRUN" "$XCODEBUILD" -create-xcframework "${args[@]}" -output "$OUTPUT_PATH"

OUTPUT_DIR="$(cd "$(dirname "$OUTPUT_PATH")" && pwd)"
OUTPUT_NAME="$(basename "$OUTPUT_PATH")"
TAG="$(resolve_msquic_tag)"
CONFIG_LABEL="$(printf "%s" "$CONFIGURATION" | tr "[:lower:]" "[:upper:]")"
ARCHIVE_NAME="MsQuic-${TAG}-${CONFIG_LABEL}-darwin-multiarch-static-unsigned.zip"
CHECKSUM_NAME="${ARCHIVE_NAME}.swiftsum"
CHECKSUM_LEGACY_NAME="MsQuic-${TAG}-${CONFIG_LABEL}-darwin-multiarch-static-unsigned.zip.swiftsum"

(
  cd "$OUTPUT_DIR"
  [ -d "$OUTPUT_NAME" ] || die "missing xcframework for packaging: $OUTPUT_NAME"

  rm -f "$ARCHIVE_NAME" "$CHECKSUM_NAME" "$CHECKSUM_LEGACY_NAME"
  run "$SEVEN_Z" a "$ARCHIVE_NAME" "$OUTPUT_NAME"

  echo "+ swift package compute-checksum $ARCHIVE_NAME"
  checksum="$(swift package compute-checksum "$ARCHIVE_NAME")"
  printf "%s\n" "$checksum" > "$CHECKSUM_NAME"
  printf "%s\n" "$checksum" > "$CHECKSUM_LEGACY_NAME"
)
