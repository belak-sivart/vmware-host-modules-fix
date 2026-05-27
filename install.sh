#!/usr/bin/env bash
#
# Build and install patched VMware vmmon/vmnet modules for
# VMware Workstation 17.6.0 on Linux kernel 6.11.x - 6.13.x.
#
# Run as root: sudo ./install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_DIR="${SCRIPT_DIR}/patches"
VMWARE_SRC="/usr/lib/vmware/modules/source"
WORK_DIR="$(mktemp -d -t vmware-host-modules-fix.XXXXXX)"
trap 'rm -rf "${WORK_DIR}"' EXIT

SUPPORTED_VMWARE="17.6.0"
MIN_KERNEL_MAJOR=6
MIN_KERNEL_MINOR=11
MAX_KERNEL_MINOR=13

err() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; }
log() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33mwarn:\033[0m %s\n' "$*" >&2; }

require_root() {
    if [[ $EUID -ne 0 ]]; then
        err "must run as root (use sudo)"
        exit 1
    fi
}

check_vmware_version() {
    if ! command -v vmware >/dev/null; then
        err "vmware command not found; is VMware Workstation installed?"
        exit 1
    fi
    local version
    version="$(vmware -v 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    if [[ "${version}" != "${SUPPORTED_VMWARE}" ]]; then
        err "VMware Workstation ${SUPPORTED_VMWARE} required, found ${version}"
        err "this patch set targets ${SUPPORTED_VMWARE} only"
        exit 1
    fi
    log "VMware Workstation ${version} detected"
}

check_kernel_version() {
    local krelease major minor
    krelease="$(uname -r)"
    major="$(echo "${krelease}" | cut -d. -f1)"
    minor="$(echo "${krelease}" | cut -d. -f2)"
    if [[ "${major}" -ne "${MIN_KERNEL_MAJOR}" ]] \
       || [[ "${minor}" -lt "${MIN_KERNEL_MINOR}" ]] \
       || [[ "${minor}" -gt "${MAX_KERNEL_MINOR}" ]]; then
        err "kernel ${MIN_KERNEL_MAJOR}.${MIN_KERNEL_MINOR}-${MIN_KERNEL_MAJOR}.${MAX_KERNEL_MINOR} required, found ${krelease}"
        exit 1
    fi
    log "kernel ${krelease} detected"
}

check_build_prereqs() {
    local missing=()
    command -v make >/dev/null || missing+=("make")
    command -v gcc >/dev/null  || missing+=("gcc")
    [[ -d "/lib/modules/$(uname -r)/build" ]] \
        || missing+=("linux-headers-$(uname -r)")
    if (( ${#missing[@]} )); then
        err "missing build prerequisites: ${missing[*]}"
        err "install with: apt install build-essential linux-headers-\$(uname -r)"
        exit 1
    fi
}

backup_originals() {
    for mod in vmmon vmnet; do
        local src="${VMWARE_SRC}/${mod}.tar"
        local bak="${VMWARE_SRC}/${mod}.tar.orig"
        if [[ ! -f "${src}" ]]; then
            err "${src} not found; VMware install looks incomplete"
            exit 1
        fi
        if [[ ! -f "${bak}" ]]; then
            log "backing up ${mod}.tar -> ${mod}.tar.orig"
            cp -a "${src}" "${bak}"
        else
            warn "${mod}.tar.orig already exists; keeping existing backup"
        fi
    done
}

apply_patches() {
    log "extracting sources to ${WORK_DIR}"
    (cd "${WORK_DIR}" && tar xf "${VMWARE_SRC}/vmmon.tar.orig" \
                       && tar xf "${VMWARE_SRC}/vmnet.tar.orig")
    log "applying patches"
    for p in "${PATCH_DIR}"/*.patch; do
        log "  $(basename "${p}")"
        patch -d "${WORK_DIR}" -p1 --no-backup-if-mismatch < "${p}"
    done
}

repack_and_install() {
    log "repacking tarballs"
    (cd "${WORK_DIR}" && tar cf vmmon.tar vmmon-only \
                       && tar cf vmnet.tar vmnet-only)
    log "installing patched tarballs"
    cp -a "${WORK_DIR}/vmmon.tar" "${VMWARE_SRC}/vmmon.tar"
    cp -a "${WORK_DIR}/vmnet.tar" "${VMWARE_SRC}/vmnet.tar"
}

rebuild_and_load() {
    log "running vmware-modconfig --console --install-all"
    vmware-modconfig --console --install-all
}

verify() {
    log "verifying modules loaded"
    local out
    out="$(lsmod | awk '$1 == "vmmon" || $1 == "vmnet" { print $1 }' | sort -u)"
    if [[ "${out}" != *"vmmon"* ]] || [[ "${out}" != *"vmnet"* ]]; then
        err "modules did not load; check /tmp/vmware-*/vmware-*.log for build errors"
        exit 1
    fi
    log "vmmon and vmnet loaded successfully"
}

main() {
    require_root
    check_vmware_version
    check_kernel_version
    check_build_prereqs
    backup_originals
    apply_patches
    repack_and_install
    rebuild_and_load
    verify
    log "done. you can start VMware Workstation."
}

main "$@"
