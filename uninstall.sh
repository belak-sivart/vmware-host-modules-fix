#!/usr/bin/env bash
#
# Restore the original (unpatched) VMware vmmon/vmnet tarballs
# from the .orig backups created by install.sh, then rebuild.
#
# Run as root: sudo ./uninstall.sh

set -euo pipefail

VMWARE_SRC="/usr/lib/vmware/modules/source"

err() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; }
log() { printf '\033[36m==>\033[0m %s\n' "$*"; }

if [[ $EUID -ne 0 ]]; then
    err "must run as root (use sudo)"
    exit 1
fi

for mod in vmmon vmnet; do
    if [[ ! -f "${VMWARE_SRC}/${mod}.tar.orig" ]]; then
        err "${VMWARE_SRC}/${mod}.tar.orig not found; nothing to restore"
        err "did you run install.sh? if you patched manually, restore from the VMware bundle"
        exit 1
    fi
    log "restoring ${mod}.tar from .orig"
    cp -a "${VMWARE_SRC}/${mod}.tar.orig" "${VMWARE_SRC}/${mod}.tar"
done

log "rebuilding original modules"
vmware-modconfig --console --install-all || true

log "done. .orig backups left in place; delete them manually if no longer needed."
