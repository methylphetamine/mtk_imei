# MTK IMEI patcher for Xiaomi phones with Helio G Series SoC
A script that recreates the NVRAM partition and makes a private TWRP flashable for your phone

## Supported devices
- Redmi Note 8 Pro
- Redmi Note 10S / Redmi Note 11 SE / POCO M5s
- Redmi Note 12S
- Redmi 10 / Redmi 10 2022 / Redmi 10 Prime / Redmi 10 Prime 2022 / Redmi Note 11 4G
- Redmi 12C / POCO C55
- Redmi 12
- Redmi 9

## [Guide](https://graph.org/IMEI-Restoration-05-04)

## Usage
1. Fill in your values in `config.txt` and run `mtk_imei.cmd`. A flashable `imei_repair-<device>.zip` will be generated in the `out` folder.
2. Backup NVRAM and NVDATA partitions.
3. Flash `imei_repair-<device>.zip` in TWRP and reboot your phone.

The generated zip bundles the `md_patcher.ko` module for **every** supported
kernel and picks the right one automatically at boot (`uname -r`), so a single
flashable works no matter which of the supported kernels you run. Leave
`"kernel": "all"` in `config.txt` for this behaviour, or set it to a specific
release string to bundle only that module.

## Uninstall
1. Restore NVRAM and NVDATA partitions from backup.
2. Mount Vendor partition and delete `/vendor/etc/init/md_patcher.rc` and
   the `/vendor/lib/modules/md_patcher-*.ko` files.

## Making a Magisk module TWRP-flashable
`tools/magisk2twrp.sh` converts any Magisk module zip (including the
`imei_repair-*.zip`s built here) into a hybrid zip that

- still installs as a normal Magisk module from the Magisk app, and
- can be flashed in TWRP: it extracts the module's partition trees
  (`system/`, `system_ext/`, `product/`, `vendor/`, `odm/`) into the real
  partitions and writes root-level `nvram.img` / `nvdata.img` to theirs.

```sh
tools/magisk2twrp.sh my_module.zip                  # -> out/<module-id>-twrp.zip
tools/magisk2twrp.sh my_module.zip out/custom.zip
```

Dynamic ("super") partitions are handled automatically: the generated
installer probes `/dev/block/mapper/<part>` (where TWRP maps logical
partitions) before the `by-name` paths, and reports a clear error instead of
half-flashing when a partition cannot be mounted read-write (use RO2RW).

Stored file modes are preserved from the source zip. If a module needs extra
steps on a specific device (e.g. `chmod`/`chcon` a helper), ship a
`twrp-extra.sh` at the zip root — the recovery installer runs it after the
extraction.

Release tool zips ship a ready-made `mtk_imei-twrp-template.zip` — the
bundled module base (`data/patch.zip`) converted with this tool.

## Supported pox kernels (Redmi Note 8 Pro)
The `data/begonia` folder ships prebuilt `md_patcher.ko` modules matching the
released `pox-begonia-kernel` builds, including `Onyx`, `Onyx-APatch`,
`Onyx-BakaSU`, `Onyx-KSU-Next` and `Onyx-Sultan-APatch`.

Modules are rebuilt automatically from the latest pox release by
`tools/build_pox_modules.sh` (see `.github/workflows/update-modules.yml`).
Maintainers/agents updating this repo should read **[HANDOFF.md](HANDOFF.md)**.

## Notes
- The bootloader cannot be locked if you use this.
- The generated zip is also a Magisk module. It is installed automatically for devices with read-only dynamic partitions. Make sure your recovery can mount the internal storage before flashing the zip.
- If you don't want to use Magisk, make sure your system partitions can be mounted read-write (use RO2RW for devices with dynamic partitions).
- The flashable supports both stock and custom ROMs. You have to flash it again after you clean flash or update your ROM.
- If nothing works, try setting *imei_1* to *000000000000000* (use *imei_2* for your real IMEI).

## Prerequisites
[Visual C++ Redistributable for Visual Studio 2015-2022](https://aka.ms/vs/17/release/vc_redist.x64.exe) (x64)
