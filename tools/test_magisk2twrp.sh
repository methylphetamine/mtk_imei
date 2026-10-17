#!/usr/bin/env bash
#
# Self-test for tools/magisk2twrp.sh.
#
# 1. Structure tests (always): convert a fixture module zip and assert the
#    hybrid zip layout (module files kept, installer trio added, #MAGISK
#    marker, chmod lines, image list, hook).
# 2. End-to-end chroot tests (when root, e.g. CI): run the generated
#    twrp-install.sh against a fake partition tree, with mocked mount/umount,
#    covering the classic by-name path, the dynamic /dev/block/mapper path
#    and the system-as-root / non-system-as-root branches.
#
# Usage: tools/test_magisk2twrp.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
CONVERTER="$ROOT/tools/magisk2twrp.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/magisk2twrp-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

# ----------------------------------------------------------------------
# fixture module zip
# ----------------------------------------------------------------------
FIX="$TMP/fixture"
mkdir -p "$FIX/system/bin" "$FIX/system/app/Foo" "$FIX/vendor/etc/init" "$FIX/bin"
cat > "$FIX/module.prop" <<'EOF'
id=testmod
name=Test Module
version=v1.2
versionCode=3
author=tester
description=demo
EOF
printf '#!/system/bin/sh\necho hi\n' > "$FIX/post-fs-data.sh"
printf 'tool\n' > "$FIX/system/bin/tool";   chmod 755 "$FIX/system/bin/tool"
printf 'apk\n'  > "$FIX/system/app/Foo/Foo.apk"
printf 'rc\n'   > "$FIX/vendor/etc/init/foo.rc"
printf 'runner\n' > "$FIX/bin/runner";      chmod 700 "$FIX/bin/runner"
head -c 4096 /dev/urandom > "$FIX/nvdata.img"
printf 'echo hook-ran\n' > "$FIX/twrp-extra.sh"
touch "$FIX/skip_mount"
MOD="$TMP/mod.zip"
( cd "$FIX" && zip -r -X -q "$MOD" . )
pass "fixture module built"

# ----------------------------------------------------------------------
# convert
# ----------------------------------------------------------------------
OUT="$TMP/out.zip"
"$CONVERTER" "$MOD" "$OUT" >/dev/null
[ -f "$OUT" ] || fail "converter produced no output"
pass "converter produced $OUT"

zcat_member() { unzip -p "$OUT" "$1"; }

# herestring-based to avoid `unzip -Z1 | grep -q` SIGPIPE races under pipefail
LIST="$(unzip -Z1 "$OUT")"
has_member() { grep -qx "$1" <<< "$LIST"; }

# module payload must survive untouched
for m in module.prop post-fs-data.sh skip_mount system/bin/tool vendor/etc/init/foo.rc nvdata.img; do
  has_member "$m" || fail "missing module member: $m"
done
[ "$(zcat_member module.prop)" = "$(cat "$FIX/module.prop")" ] || fail "module.prop was modified"
pass "module payload preserved"

# installer trio
for m in META-INF/com/google/android/update-binary \
         META-INF/com/google/android/updater-script \
         META-INF/com/google/android/twrp-install.sh; do
  has_member "$m" || fail "missing installer member: $m"
done
[ "$(zcat_member META-INF/com/google/android/updater-script | head -n1)" = "#MAGISK" ] \
  || fail "updater-script lacks #MAGISK marker"
pass "installer files present, #MAGISK marker set"

INST="$(zcat_member META-INF/com/google/android/twrp-install.sh)"
SHIM="$(zcat_member META-INF/com/google/android/update-binary)"
printf '%s\n' "$INST" | sh -n || fail "twrp-install.sh has a syntax error"
printf '%s\n' "$SHIM" | sh -n || fail "update-binary has a syntax error"
pass "generated scripts pass sh -n"

grep -q 'install_system' <<< "$INST" || fail "no system handling"
grep -q 'install_tree vendor' <<< "$INST" || fail "no vendor handling"
grep -q '/dev/block/mapper/\$1' <<< "$INST" || fail "no dynamic mapper probing"
grep -q 'flash_image nvdata nvdata.img' <<< "$INST" || fail "no nvdata image step"
grep -q 'chmod 755 "\$T/bin/tool"' <<< "$INST" || fail "no chmod line for system/bin/tool"
grep -q 'bin/runner' <<< "$INST" && fail "bin/runner (non-partition dir) must not be extracted"
grep -q 'twrp-extra.sh' <<< "$INST" || fail "no hook execution"
pass "generated installer content checks"

# idempotency: converting the output again must not nest META-INF
OUT2="$TMP/out2.zip"
"$CONVERTER" "$OUT" "$OUT2" >/dev/null
[ "$(unzip -Z1 "$OUT2" | grep -c 'META-INF/com/google/android/update-binary')" = "1" ] \
  || fail "re-conversion duplicated installer entries"
pass "re-conversion is clean"

# ----------------------------------------------------------------------
# end-to-end chroot test (needs root)
# ----------------------------------------------------------------------
if [ "$(id -u)" != "0" ]; then
  echo "note: not root - skipping chroot end-to-end tests"
  echo "ALL TESTS PASSED (structure only)"
  exit 0
fi

command -v chroot >/dev/null 2>&1 || { echo "note: chroot unavailable - skipping"; exit 0; }

copy_bin() { # copy_bin <path>  (dereferences symlinks)
  local bin="$1" lib real
  real="$(readlink -f "$bin")"
  mkdir -p "$R$(dirname "$bin")"
  cp -a "$real" "$R$bin"
  while read -r lib; do
    [ -n "$lib" ] || continue
    real="$(readlink -f "$lib")"
    mkdir -p "$R$(dirname "$lib")"
    cp -a "$real" "$R$lib" 2>/dev/null || true
  done < <(ldd "$bin" 2>/dev/null | grep -oE '(/[^ ]+\.so[^ ]*|/lib[^ ]*ld-[^ ]*)')
}

make_rootfs() { # make_rootfs <dir>
  R="$1"
  mkdir -p "$R"/bin "$R"/sbin "$R"/usr/bin "$R"/tmp "$R"/proc \
           "$R"/dev/block/mapper "$R"/dev/block/by-name \
           "$R"/dev/block/platform/bootdevice/by-name
  copy_bin /bin/sh
  ln -sf /bin/sh "$R/sbin/sh"
  for b in /usr/bin/unzip /usr/bin/mkdir /usr/bin/touch /usr/bin/rm \
           /usr/bin/grep /usr/bin/chmod /usr/bin/sync; do
    copy_bin "$b"
  done
  cat > "$R/sbin/mount" <<'EOF'
#!/bin/sh
echo "MOUNT $*" >> /tmp/mount.log
exit 0
EOF
  cat > "$R/sbin/umount" <<'EOF'
#!/bin/sh
echo "UMOUNT $*" >> /tmp/mount.log
exit 0
EOF
  chmod 755 "$R/sbin/mount" "$R/sbin/umount"
  : > "$R/proc/mounts"
  cp "$OUT" "$R/payload.zip"
  mkdir -p "$R/installer"
  ( cd "$R/installer" && unzip -oq "$R/payload.zip" META-INF/com/google/android/twrp-install.sh )
}

run_installer() { # run_installer <rootfs>
  R="$1"
  cp "$R/installer/META-INF/com/google/android/twrp-install.sh" "$R/twrp-install.sh"
  chroot "$R" /bin/sh /twrp-install.sh 3 42 /payload.zip
}

assert_check() { # assert_check <desc> <cmd...>
  local desc="$1"; shift
  "$@" || fail "$desc"
  pass "$desc"
}

# --- variant 1: dynamic layout (mapper), non-system-as-root system ---
R1="$TMP/rootfs1"
make_rootfs "$R1"
: > "$R1/dev/block/mapper/system"
: > "$R1/dev/block/mapper/vendor"
: > "$R1/dev/block/platform/bootdevice/by-name/nvdata"   # classic path for the image only
run_installer "$R1" > "$TMP/run1.log" || { cat "$TMP/run1.log"; cat "$R1/tmp/mount.log" 2>/dev/null; fail "variant1: installer exited nonzero"; }
[ "$(cat "$R1/system/bin/tool")" = "tool" ] || fail "variant1: system file not extracted"
[ "$(stat -c %a "$R1/system/bin/tool")" = "755" ] || fail "variant1: chmod not applied"
[ "$(cat "$R1/vendor/etc/init/foo.rc")" = "rc" ] || fail "variant1: vendor file not extracted"
cmp -s "$R1/dev/block/platform/bootdevice/by-name/nvdata" "$FIX/nvdata.img" || fail "variant1: nvdata image wrong"
grep -q "MOUNT -o rw -t ext4 /dev/block/mapper/vendor /vendor" "$R1/tmp/mount.log" || fail "variant1: vendor not mounted from mapper"
grep -q "MOUNT -o rw -t ext4 /dev/block/platform/bootdevice/by-name/nvdata" "$R1/tmp/mount.log" && fail "variant1: image written over mount"
grep -q "hook-ran" "$TMP/run1.log" || fail "variant1: twrp-extra.sh did not run"
pass "variant 1 (dynamic mapper paths, non-sar system, by-name image)"

# --- variant 2: system-as-root ---
R2="$TMP/rootfs2"
make_rootfs "$R2"
: > "$R2/dev/block/by-name/system"        # only the generic by-name path
: > "$R2/dev/block/mapper/vendor"
: > "$R2/dev/block/by-name/nvdata"
mkdir -p "$R2/system_root/system"
: > "$R2/system_root/system/build.prop"   # pre-existing sar marker
run_installer "$R2" > "$TMP/run2.log" || { cat "$TMP/run2.log"; fail "variant2: installer exited nonzero"; }
[ "$(cat "$R2/system_root/system/bin/tool")" = "tool" ] || fail "variant2: sar system file not extracted"
[ "$(cat "$R2/vendor/etc/init/foo.rc")" = "rc" ] || fail "variant2: vendor file not extracted"
cmp -s "$R2/dev/block/by-name/nvdata" "$FIX/nvdata.img" || fail "variant2: nvdata image wrong"
grep -q "MOUNT -o rw -t ext4 /dev/block/by-name/system /system_root" "$R2/tmp/mount.log" || fail "variant2: system not mounted from by-name"
pass "variant 2 (system-as-root, generic by-name paths)"

# --- variant 3: unmountable partition -> clean failure ---
R3="$TMP/rootfs3"
make_rootfs "$R3"
: > "$R3/dev/block/mapper/system"
: > "$R3/dev/block/by-name/nvdata"
# no vendor device node anywhere
if run_installer "$R3" > "$TMP/run3.log" 2>&1; then
  cat "$TMP/run3.log"; fail "variant3: installer should have failed"
fi
grep -q "cannot mount /vendor" "$TMP/run3.log" || { cat "$TMP/run3.log"; fail "variant3: missing failure message"; }
pass "variant 3 (missing partition fails with clear message)"

echo "ALL TESTS PASSED"
