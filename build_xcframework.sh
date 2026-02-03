#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="${DIST_DIR:-"$ROOT_DIR/dist"}"
MODULEMAP_TEMPLATE="${MODULEMAP_TEMPLATE:-"$ROOT_DIR/module.modulemap.template"}"
OUTPUT_PATH="${OUTPUT_PATH:-"$DIST_DIR/MsQuic.xcframework"}"
LIB_NAME="${LIB_NAME:-msquic}"
XCRUN="${XCRUN:-xcrun}"
XCODEBUILD="${XCODEBUILD:-xcodebuild}"

PLATFORMS=(ios ios-simulator macos)

run() {
  echo "+ $*"
  "$@"
}

die() {
  echo "error: $*" >&2
  exit 1
}

[ -f "$MODULEMAP_TEMPLATE" ] || die "modulemap template not found: $MODULEMAP_TEMPLATE"

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
