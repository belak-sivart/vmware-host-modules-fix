# vmware-host-modules-fix

Patches and an install script that make VMware Workstation **17.6.0**'s
`vmmon` and `vmnet` kernel modules build on Linux kernels **6.11.x – 6.13.x**.

Tested on a Linux kernel 6.12.x system.

## What's broken in 17.6.0 on these kernels

VMware ships stale module source. Three things changed in recent kernels that
the bundled `vmmon.tar` / `vmnet.tar` don't account for:

| # | Kernel change                                                       | Where it breaks                           |
|---|---------------------------------------------------------------------|-------------------------------------------|
| 1 | `pgd_large`/`p4d_large`/`pud_large`/`pmd_large` renamed to `*_leaf` (6.11) | `vmmon-only/include/pgtbl.h`, `compat_pgtable.h` |
| 2 | `dev_base_lock` removed (6.12)                                      | `vmnet-only/vmnetInt.h`, used by `bridge.c` |
| 3 | Kernel now defines `MAX()` in `<linux/minmax.h>` (6.11)             | `vmnet-only/vnetInt.h` (redefinition warning, fatal with `-Werror`) |

Result: `sudo vmware-modconfig --console --install-all` fails with
`implicit declaration of function 'pgd_large'` and `'dev_base_lock' undeclared`.

## What this repo does

Three small unified-diff patches:

- `patches/0001-vmmon-pgtable-leaf-shims.patch` — adds `*_large → *_leaf` compat
  shims in `compat_pgtable.h`, version-gated to kernel 6.11+
- `patches/0002-vmnet-dev_base_lock-to-rtnl_lock.patch` — swaps
  `dev_base_lock` for `rtnl_lock()` on kernel 6.12+, adds missing includes
- `patches/0003-vmnet-undef-MAX.patch` — `#undef MAX` before the local
  redefinition in `vnetInt.h`

Plus `install.sh` and `uninstall.sh` to apply/revert them safely.

## Prerequisites

On Debian/Ubuntu-derived distributions:

```bash
sudo apt install build-essential linux-headers-$(uname -r)
```

On Fedora/RHEL: `sudo dnf install gcc make kernel-devel-$(uname -r)`.
On Arch: `sudo pacman -S base-devel linux-headers`.

You also need VMware Workstation 17.6.0 already installed.

## Install

```bash
git clone https://github.com/belak-sivart/vmware-host-modules-fix.git
cd vmware-host-modules-fix
sudo ./install.sh
```

The script:

1. Refuses to run unless VMware is **17.6.0** and kernel is **6.11–6.13**.
2. Backs up `/usr/lib/vmware/modules/source/{vmmon,vmnet}.tar` to `*.orig`
   (only on first run — won't clobber an existing backup).
3. Extracts, patches, repacks, installs.
4. Runs `vmware-modconfig --console --install-all`.
5. Verifies both modules show up in `lsmod`.

## Uninstall

```bash
sudo ./uninstall.sh
```

Restores the `.orig` tarballs and rebuilds the stock (unpatched) modules.

## Manual application

If you don't want to run the script, the patches apply with standard
`patch`:

```bash
cd /usr/lib/vmware/modules/source
sudo cp vmmon.tar vmmon.tar.orig
sudo cp vmnet.tar vmnet.tar.orig
WORK=$(mktemp -d) && cd "$WORK"
tar xf /usr/lib/vmware/modules/source/vmmon.tar
tar xf /usr/lib/vmware/modules/source/vmnet.tar
for p in /path/to/this/repo/patches/*.patch; do patch -p1 < "$p"; done
tar cf vmmon.tar vmmon-only
tar cf vmnet.tar vmnet-only
sudo cp vmmon.tar vmnet.tar /usr/lib/vmware/modules/source/
sudo vmware-modconfig --console --install-all
```

## Verifying it worked

```bash
lsmod | grep -E 'vmmon|vmnet'
# vmnet    73728  13
# vmmon   167936   0
```

If you see both modules, VMware Workstation is ready to run.

If the build fails, the log is at `/tmp/vmware-<your-user>/vmware-*.log`.
Look for lines containing `error:`.

## Scope and non-goals

- **Targets one combination on purpose**: VMware 17.6.0 + kernel 6.11–6.13.
  Patches are version-gated internally too, so they're inert outside that range.
- **Does not** try to handle every VMware/kernel combination. If you're on
  a different VMware version or a kernel ≥ 6.14, fork this repo or check
  the upstream community forks for an appropriate branch.
- **Does not** fix objtool/UACCESS warnings about `csum_partial_copy_nocheck`.
  Those are warnings, not build errors, and don't block module load.

## License

GPL-2.0 — matches the license of the VMware module sources being patched.
See `LICENSE`.

## Acknowledgements

The general approach (community-maintained patches against stale VMware
module sources) follows the long tradition of forks like
[mkubecek/vmware-host-modules](https://github.com/mkubecek/vmware-host-modules)
and its successors. This repo is narrower in scope — one VMware version,
one kernel range, three patches — so it's easy to read end to end and
debug if something changes.
