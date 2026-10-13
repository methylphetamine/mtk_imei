#!/usr/bin/env bash
#
# Reproducible out-of-tree build of md_patcher.ko for the begonia
# (Redmi Note 8 Pro / MT6785) kernel tree.
#
# The kernel is configured with begonia_user_defconfig and built with the
# prebuilt clang shipped inside the local TWRP source tree (clang-r416183b).
#
#   ./build.sh              # configure + modules_prepare + build the module
#   KERNEL=/path ./build.sh # override kernel tree
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

KERNEL="${KERNEL:-$HOME/begonia/kernel/xiaomi/mt6785}"
OUT="${OUT:-$HOME/begonia/md_patcher-out}"
CLANG_BIN="${CLANG_BIN:-$HOME/twrp/prebuilts/clang/host/linux-x86/clang-r416183b/bin}"
DEFCONFIG="${DEFCONFIG:-begonia_user_defconfig}"

export PATH="$CLANG_BIN:$PATH"

MAKE_ARGS=(
    ARCH=arm64
    O="$OUT"
    CC=clang
    CLANG_TRIPLE=aarch64-linux-gnu-
    CROSS_COMPILE=aarch64-linux-gnu-
    HOSTCC=clang
    HOSTCXX=clang++
    LD=ld.lld
    AR=llvm-ar
    NM=llvm-nm
    OBJCOPY=llvm-objcopy
    OBJDUMP=llvm-objdump
)

echo ">> kernel : $KERNEL"
echo ">> output : $OUT"
echo ">> clang  : $(clang --version | head -1)"

if [ ! -f "$OUT/.config" ]; then
    echo ">> configuring ($DEFCONFIG)"
    make -C "$KERNEL" "${MAKE_ARGS[@]}" "$DEFCONFIG"

    # CONFIG_LLVM_POLLY and CONFIG_INLINE_OPTIMIZATION add -mllvm flags that the
    # local clang does not understand (they target the newer clang used for the
    # released kernel).  They only tune vmlinux codegen, so drop them for the
    # module build.
    "$KERNEL/scripts/config" --file "$OUT/.config" -d LLVM_POLLY -d INLINE_OPTIMIZATION
    make -C "$KERNEL" "${MAKE_ARGS[@]}" olddefconfig
fi

# kconfig keeps the generated flex source as an intermediate and deletes it,
# so a later make run cannot rebuild scripts/kconfig/conf.  Seed it from the
# shipped copy whenever it is missing.
mkdir -p "$OUT/scripts/kconfig"
[ -f "$OUT/scripts/kconfig/zconf.lex.c" ] || \
    cp "$KERNEL/scripts/kconfig/zconf.lex.c_shipped" "$OUT/scripts/kconfig/zconf.lex.c"
[ -f "$OUT/scripts/kconfig/zconf.tab.c" ] || \
    cp "$KERNEL/scripts/kconfig/zconf.tab.c_shipped" "$OUT/scripts/kconfig/zconf.tab.c"

echo ">> modules_prepare"
make -C "$KERNEL" "${MAKE_ARGS[@]}" modules_prepare

echo ">> building md_patcher.ko"
make -C "$KERNEL" "${MAKE_ARGS[@]}" M="$HERE" modules

echo
echo ">> result:"
ls -l "$HERE/md_patcher.ko"
llvm-nm -u "$HERE/md_patcher.ko"
