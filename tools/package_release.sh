#!/usr/bin/env bash
#
# Package the tool into a distributable zip at out/mtk_imei-<version>.zip.
#
# Usage:
#   tools/package_release.sh [version]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION="${1:-$(date +%Y%m%d)}"
OUT="$ROOT/out"
ZIP="$OUT/mtk_imei-$VERSION.zip"

mkdir -p "$OUT"

# md_patcher/ ships sources only, not build artifacts.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/mtk_imei/md_patcher"
cp -f "$ROOT/md_patcher/md_patcher.c" "$ROOT/md_patcher/modulus.h" \
      "$ROOT/md_patcher/Makefile" "$tmp/mtk_imei/md_patcher/"

cp -f "$ROOT/config.txt" "$ROOT/mtk_imei.cmd" "$ROOT/mtk_imei.sh" \
      "$ROOT/README.md" "$ROOT/LICENSE" "$tmp/mtk_imei/" 2>/dev/null || true
cp -r "$ROOT/bin" "$ROOT/data" "$tmp/mtk_imei/"

( cd "$tmp" && zip -r -X -q "$ZIP" mtk_imei )
echo ">> $ZIP"
unzip -l "$ZIP" | tail -1
