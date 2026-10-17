# Maintainer handoff — MTK IMEI patcher (begonia)

This document is everything an agent (or human) needs to **update the kernel
modules when `pox-begonia-kernel` ships a new release**. Read this top to
bottom; you should not need any context beyond this repo.

---

## 1. What this repo is

A patched fork of *timjosten's* MTK IMEI restoration tool for Xiaomi Helio G
devices. It builds a TWRP-flashable `imei_repair-<device>.zip`.

The important part for maintenance is the kernel module **`md_patcher.ko`**.
It is compiled out-of-tree and must match the device kernel's `uname -r`
exactly (its Linux vermagic). A module built for one kernel will refuse to
load on another.

To avoid shipping one zip per kernel, this tool:

- bundles **every** `data/<device>/md_patcher-*.ko` into one zip, and
- picks the right one at boot:
  - Magisk/APatch/KernelSU path: `post-fs-data.sh` insmods
    `md_patcher-$(uname -r).ko`.
  - non-Magisk / RO2RW path: a generated `/vendor/etc/init/md_patcher.rc`
    lists a plain `insmod` for each bundled module; the kernel only accepts the
    one whose vermagic matches.

So the maintenance job is simply: **keep `data/begonia/md_patcher-*.ko` in sync
with pox releases.**

- Repo: `https://github.com/methylphetamine/mtk_imei`
- Upstream kernel: `https://github.com/pox-project/pox-begonia-kernel`
- Rolling release: `https://github.com/methylphetamine/mtk_imei/releases/tag/latest`

---

## 2. TL;DR (the usual update)

When pox publishes a new kernel (or you want to (re)build everything):

```bash
git clone https://github.com/methylphetamine/mtk_imei
cd mtk_imei
GH_TOKEN=<a-token> tools/build_pox_modules.sh   # builds any missing modules
tools/verify_modules.sh                          # sanity-check vermagic
tools/package_release.sh                         # -> out/mtk_imei-<date>.zip
git add data/begonia && git commit -m "modules: sync with latest pox release" && git push
gh release upload latest out/mtk_imei-*.zip --clobber
```

The daily GitHub Actions workflow (`.github/workflows/update-modules.yml`)
does exactly this automatically. You only need the manual flow if the
automation is broken or you want to force a rebuild.

---

## 3. Repo layout

```
config.txt                     user config; "kernel":"all" bundles everything
mtk_imei.cmd / mtk_imei.sh     launchers (Windows / Linux)
bin/mtk_imei.php               the tool (PHP); builds the single flashable
data/alias.txt                 device alias -> canonical name
data/<device>/nvram.bin        nvram template for that device
data/<device>/updater-script.txt
data/<device>/md_patcher-*.ko  <-- the modules we maintain
data/patch.zip                 Magisk-module base (post-fs-data.sh lives here)
md_patcher/{md_patcher.c,modulus.h,Makefile}   module source
tools/build_module.sh          build ONE module pinned to a release string
tools/build_pox_modules.sh     build ALL modules for the latest pox release
tools/verify_modules.sh        check vermagic of every bundled module
tools/package_release.sh       zip the tool for release
.github/workflows/update-modules.yml   daily auto-update
```

Only `begonia` (Redmi Note 8 Pro, MT6785) is actively maintained here.

---

## 4. How the module must match

A `.ko`'s `vermagic` must equal the kernel's:

```
<uname -r> SMP preempt mod_unload modversions aarch64
```

The module is linked with an **empty `__versions` section**, so there are no
symbol CRC checks — the vermagic string is the only gate. It imports a tiny,
stable symbol set:

```
__ioremap __iounmap arm64_const_caps_ready bcmp cpu_hwcap_keys cpu_hwcaps
emi_mpu_set_protection memcpy memstart_addr pfn_valid printk vfree vmalloc vmap
```

`emi_mpu_set_protection` is exported by
`drivers/misc/mediatek/emi/submodule/mpu_v1.c` in every pox branch.

Because only the vermagic matters, a module for any pox edition can be built
from **any** pox tree as long as `LOCALVERSION` is set to the edition's release
suffix. `tools/build_pox_modules.sh` exploits this (builds from the `onyx`
branch for every edition).

---

## 5. How the pox release encodes `uname -r`

Each release asset is named:

```
Pox-<ver>-<Edition>-<commit>-begonia.zip
```

and the corresponding `uname -r` is:

```
<base>-<asset-name-without-"-begonia.zip">
```

e.g. asset `Pox-1.0.0-Beta-Onyx-APatch-810be46-begonia.zip` on base `4.14.357`
→ `4.14.357-Pox-1.0.0-Beta-Onyx-APatch-810be46`.

`<base>` is the kernel base version — obtain it with `make -s kernelversion`
in the pox tree (`4.14.357` at time of writing).

The script derives this automatically from the GitHub release API, so it never
needs to download the (20–40 MB) kernel zips.

> You can double-check any asset by extracting its banner:
> `unzip -p <asset>.zip Image.gz-dtb | gzip -dc | strings -a | grep -m1 "Linux version"`

---

## 6. Editable editions

`tools/build_pox_modules.sh` builds every asset **except** those matching
`EXCLUDE` (default `ReSukiSU|Kaeru`). Current included editions:

- `Onyx` (begonia_user_defconfig)
- `Onyx-APatch` (begonia_apatch_defconfig)
- `Onyx-BakaSU` (bakasu_defconfig)
- `Onyx-KSU-Next` (begonia_ksu_next_defconfig)
- `Onyx-Sultan-APatch` (begonia_sultan_apatch_defconfig)

To also maintain ReSukiSU / Kaeru, run with an empty filter:

```bash
EXCLUDE= tools/build_pox_modules.sh
```

The defconfig only affects vmlinux codegen; it does **not** change the module
vermagic. The script uses one defconfig for all editions for simplicity.

---

## 7. Manual single-module build (when you need full control)

```bash
# 1. get a pox tree + toolchain
git clone https://github.com/pox-project/pox-begonia-kernel /tmp/pox
cd /tmp/pox && git checkout onyx
bash kerdevdep/setup_kerdevdep.sh        # downloads clang-r383902 + gcc 4.9

# 2. base version
BASE=$(make -s kernelversion)            # e.g. 4.14.357

# 3. release prefix for the target asset (see section 5);
#    LOCALVERSION keeps the leading dash
LOCALVERSION="-Pox-1.0.0-Beta-Onyx-APatch-810be46"
RELEASE="${BASE}${LOCALVERSION}"         # 4.14.357-Pox-1.0.0-Beta-Onyx-APatch-810be46

# 4. build into the repo
cd /path/to/mtk_imei
POX_DIR=/tmp/pox tools/build_module.sh onyx "$LOCALVERSION" \
    begonia_user_defconfig "data/begonia/md_patcher-${RELEASE}.ko"
```

`tools/build_module.sh` does: checkout branch → defconfig → disable
`CONFIG_LLVM_POLLY`/`CONFIG_INLINE_OPTIMIZATION` (the bundled clang r383902
does not understand their `-mllvm` flags) → set `LOCALVERSION` → `olddefconfig`
→ `modules_prepare` → build the out-of-tree module.

Toolchain identity that must be used (matches the kernels):

```
Android (6443078 based on r383902) clang version 11.0.1
```

---

## 8. Verify before committing

```bash
tools/verify_modules.sh
```

It prints `OK`/`BAD` for each module. A module is good when its `vermagic`
starts with its `uname -r`. If a module is `BAD`, rebuild it (section 7).

You can also spot-check a running device with `uname -r` and compare against
the bundled filenames (`md_patcher-<uname -r>.ko`).

---

## 9. Package & publish

```bash
tools/package_release.sh                 # out/mtk_imei-<date>.zip (single file)
git add data/begonia && git commit -m "modules: sync with latest pox release"
git push                                 # the workflow republishes `latest`
```

`out/mtk_imei-<date>.zip` is the only artifact: it bundles the tool, the
module base and `mtk_imei-twrp-template.zip` (the TWRP-flashable conversion
of `data/patch.zip`). The workflow uploads it to the rolling `latest` release
after deleting the previous assets, so `latest` always holds exactly one
file. Keep that tag; do not create per-run tags unless you change the
workflow too. If you publish by hand, do the same:

```bash
gh release view latest --json assets --jq '.assets[].name' \
  | xargs -r -I{} gh release delete-asset latest {} -y
gh release upload latest out/mtk_imei-*.zip --clobber
```

---

## 10. Automation

`.github/workflows/update-modules.yml` runs daily, on manual dispatch, and on
push to `main`. It:

1. installs host deps and runs `tools/test_magisk2twrp.sh`,
2. runs `tools/build_pox_modules.sh` (builds only missing release strings),
3. commits any new `data/begonia/*.ko`,
4. packages the single tool zip and replaces the assets on the `latest`
   release with it.

It authenticates with the repo's own `GITHUB_TOKEN` (`contents: write`) — no
personal access token is stored anywhere.

---

## 11. Gotchas

- **`chip_id` length.** Even for begonia (`"patch_cert": 1`, RSA-only), the tool
  requires a 34-char `chip_id` or it aborts with "Incorrect values". Fill
  `config.txt` with `"0x"` + 32 hex chars (any value; it is unused for the RSA
  path). This is pre-existing upstream behaviour.
- **Never force-load the wrong module.** `insmod -f` bypasses the vermagic
  check. Only the Magisk `post-fs-data.sh` may force, and only after selecting
  the exact `uname -r` match. The generated vendor rc uses plain `insmod`.
- **Do not commit secrets.** No tokens, keys, or `out/`/`.work/` contents.
- **Large files.** The `nvram.bin` templates are 64 MB; git warns but accepts
  them. Avoid adding more large binaries.
- **Version string, not commit.** Two different commits can produce the same
  release string only if the suffix is identical; filenames are keyed on the
  release string, which is what matters.
- **Non-begonia devices** (`earth`, `fire`, `rosemary`, `sea`, `selene`) are
  legacy and not rebuilt by the automation.
- **Legacy begonia modules** (`md_patcher-4.14.94.ko`, `-4.14.141.ko`,
  `-4.14.186.ko`, `-4.14.356-...`) have filenames that are NOT the full
  `uname -r` (e.g. `4.14.94+`, `4.14.141-g4e3bb1f-dirty`). Do not rename them:
  they are loaded through the vermagic-checked vendor rc, not the exact-name
  lookup. `tools/verify_modules.sh` reports them as `LEG` (informational only).
- **Mode preservation in the converter.** `tools/magisk2twrp.sh` preserves the
  modes stored in the source zip. `data/patch.zip` stores `system/bin/toybox2`
  and `bin/*` as `0644` (the legacy updater-scripts `chmod`/`chown`/`chcon`
  them at flash time); ship a `twrp-extra.sh` in a module that needs that.

---

## 12. Magisk-to-TWRP converter (`tools/magisk2twrp.sh`)

Turns any Magisk module zip into a hybrid zip that flashes in TWRP and still
installs as a Magisk module. The output zip contains:

```
module payload        unchanged (module.prop, post-fs-data.sh, system/, ...)
META-INF/com/google/android/update-binary     hybrid shim (same trick as
                                              data/patch.zip: BOOTMODE ->
                                              install_module, recovery ->
                                              the installer below)
META-INF/com/google/android/twrp-install.sh   generated recovery installer
META-INF/com/google/android/updater-script    carries the #MAGISK marker only
```

Recovery behaviour:

- probes `/dev/block/mapper/<part>` first — TWRP maps super logical partitions
  there at boot and symlinks them under
  `/dev/block/platform/bootdevice/by-name/` — then the `mtk-msdc.0` and
  generic `by-name` paths;
- `system` is mounted at `/system_root` and detected as system-as-root
  (`/system_root/system`) before falling back to `/system`;
- rejects read-only mounts (erofs / unmapped dynamic partitions) with a clear
  message instead of half-flashing (RO2RW case);
- writes root-level `nvram.img` / `nvdata.img` to their partitions, refusing
  while the partition is still mounted;
- preserves stored file modes; runs a `twrp-extra.sh` from the zip (if
  present) after extraction for device-specific `chmod`/`chown`/`chcon`.

Who calls it:

- users: `tools/magisk2twrp.sh <module.zip> [out.zip]`
- CI: `.github/workflows/update-modules.yml` runs
  `tools/test_magisk2twrp.sh` (structure + chroot end-to-end tests, needs
  root for the latter); `tools/package_release.sh` converts `data/patch.zip`
  and bundles the result as `mtk_imei-twrp-template.zip` inside the tool zip
  — the single asset on the rolling `latest` release.

The converter is self-contained shell (bash + zip/unzip); it never ships
`update-binary2`, so the output zip is a few KB smaller than the original.

---

## 13. Quick reference commands

```bash
# Build/refresh all begonia modules for the latest pox release
GH_TOKEN=<token> tools/build_pox_modules.sh

# Build one module for a specific release string
POX_DIR=/tmp/pox tools/build_module.sh onyx -Pox-1.0.0-Beta-Onyx-<hash> \
    begonia_user_defconfig data/begonia/md_patcher-4.14.357-Pox-1.0.0-Beta-Onyx-<hash>.ko

# Verify every bundled module
tools/verify_modules.sh

# Convert a Magisk module zip into a hybrid TWRP-flashable zip
tools/magisk2twrp.sh my_module.zip
tools/test_magisk2twrp.sh

# Package (bundles mtk_imei-twrp-template.zip); push triggers publishing
tools/package_release.sh
```
