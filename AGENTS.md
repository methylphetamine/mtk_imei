# AGENTS.md

This repository is the **MTK IMEI patcher (begonia)** tool. It builds a single
TWRP-flashable `imei_repair-begonia.zip` that bundles an `md_patcher.ko` for
every supported `pox-begonia-kernel` release and autodetects the running kernel
at boot.

It also ships `tools/magisk2twrp.sh`, which converts any Magisk module zip into
a hybrid TWRP-flashable zip (self-test: `tools/test_magisk2twrp.sh`).

## If you are here to update it for a new pox kernel

Read **`HANDOFF.md`** — it is the complete runbook. The short version:

```bash
GH_TOKEN=<token> tools/build_pox_modules.sh   # build any missing modules
tools/verify_modules.sh                        # check vermagic
tools/package_release.sh                       # out/mtk_imei-<date>.zip (single file)
git add data/begonia && git commit -m "modules: sync with latest pox release" && git push
# the push triggers the workflow, which republishes the single asset on `latest`
```

## Rules

- The one thing that matters: each `data/begonia/md_patcher-*.ko` filename must
  equal `<kernel's uname -r>` and its `vermagic` must be
  `<uname -r> SMP preempt mod_unload modversions aarch64`.
- Only touch `data/begonia/`, `tools/`, and docs unless a change is required.
- Never commit secrets (tokens/keys) or build output (`out/`, `.work/`).
- Do not add per-run release tags; the workflow uses the rolling `latest` tag.
- Verify with `tools/verify_modules.sh` before committing.

See `HANDOFF.md` for the build recipe, toolchain details, excluded editions
(ReSukiSU/Kaeru), and known gotchas.
