#!/usr/bin/env bash
#
# Build one md_patcher.ko pinned to a specific kernel release string.
#
# Usage:
#   build_module.sh <branch> <localversion> <defconfig> <output.ko>
#
# Example:
#   POX_DIR=/path/to/pox-begonia-kernel \
#     build_module.sh onyx -Pox-1.0.0-Beta-Onyx-3888146 begonia_user_defconfig \
#       data/begonia/md_patcher-4.14.357-Pox-1.0.0-Beta-Onyx-3888146.ko
#
# <localversion> is the suffix appended to the kernel base version, e.g.
# "-Pox-1.0.0-Beta-Onyx-3888146" yields "4.14.357-Pox-1.0.0-Beta-Onyx-3888146".
#
# Environment:
#   POX_DIR   path to a pox-begonia-kernel checkout (required)
#   WORK      scratch directory (default: $POX_DIR/_module-build)
#
set -euo pipefail

BRANCH="${1:?usage: build_module.sh <branch> <localversion> <defconfig> <output.ko>}"
LOCALVERSION="${2:?missing localversion}"
DEFCONFIG="${3:?missing defconfig}"
OUT="${4:?missing output path}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

POX_DIR="${POX_DIR:?set POX_DIR to a pox-begonia-kernel checkout}"
WORK="${WORK:-$POX_DIR/_module-build}"
OBJ="$WORK/out"
MODSRC="$WORK/module-src"

log() { printf '[build_module] %s\n' "$*"; }

if [ ! -x "$POX_DIR/kerdevdep/clang/bin/clang" ]; then
    log "bootstrapping kerdevdep in $POX_DIR/kerdevdep"
    bash "$POX_DIR/kerdevdep/setup_kerdevdep.sh"
fi
# shellcheck disable=SC1091
source "$POX_DIR/kerdevdep/env.sh"

export ARCH=arm64
export CC=clang
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE=aarch64-linux-android-

mkdir -p "$MODSRC"
cp -f "$ROOT/md_patcher/md_patcher.c" \
      "$ROOT/md_patcher/modulus.h" \
      "$ROOT/md_patcher/Makefile" "$MODSRC/"

cd "$POX_DIR"
log "checkout $BRANCH"
git checkout -q -f "refs/heads/$BRANCH"

log "configure $DEFCONFIG"
rm -rf "$OBJ"
mkdir -p "$OBJ"
make O="$OBJ" ARCH="$ARCH" CC="$CC" CLANG_TRIPLE="$CLANG_TRIPLE" \
    CROSS_COMPILE="$CROSS_COMPILE" "$DEFCONFIG" >/dev/null

# CONFIG_LLVM_POLLY / CONFIG_INLINE_OPTIMIZATION emit -mllvm flags the bundled
# clang (r383902) does not understand. They only tune vmlinux codegen, so drop
# them for the out-of-tree module build.
TEST_SRC="$OBJ/.tc-test.c"
printf 'int x;\n' > "$TEST_SRC"
if ! clang --target=aarch64-linux-gnu -mllvm -polly -c "$TEST_SRC" -o /dev/null 2>/dev/null; then
    log "disabling CONFIG_LLVM_POLLY"
    "$POX_DIR/scripts/config" --file "$OBJ/.config" --disable LLVM_POLLY
fi
if ! clang --target=aarch64-linux-gnu -mllvm -unroll-threshold=1000 \
        -mllvm -inline-threshold=1500 -c "$TEST_SRC" -o /dev/null 2>/dev/null; then
    log "disabling CONFIG_INLINE_OPTIMIZATION"
    "$POX_DIR/scripts/config" --file "$OBJ/.config" --disable INLINE_OPTIMIZATION
fi
rm -f "$TEST_SRC"

log "LOCALVERSION=$LOCALVERSION"
"$POX_DIR/scripts/config" --file "$OBJ/.config" --set-str LOCALVERSION "$LOCALVERSION"
make O="$OBJ" ARCH="$ARCH" CC="$CC" CLANG_TRIPLE="$CLANG_TRIPLE" \
    CROSS_COMPILE="$CROSS_COMPILE" olddefconfig >/dev/null

rm -f "$OBJ/include/config/kernel.release" \
      "$OBJ/include/generated/utsrelease.h" \
      "$OBJ/include/generated/compile.h" \
      "$OBJ/init/version.o"

log "modules_prepare"
make O="$OBJ" ARCH="$ARCH" CC="$CC" CLANG_TRIPLE="$CLANG_TRIPLE" \
    CROSS_COMPILE="$CROSS_COMPILE" modules_prepare >/dev/null

log "building md_patcher.ko"
make O="$OBJ" ARCH="$ARCH" CC="$CC" CLANG_TRIPLE="$CLANG_TRIPLE" \
    CROSS_COMPILE="$CROSS_COMPILE" M="$MODSRC" modules >/dev/null

mkdir -p "$(dirname "$OUT")"
cp -f "$MODSRC/md_patcher.ko" "$OUT"
log "wrote $OUT"
strings -a "$OUT" | grep -m1 '^vermagic='
