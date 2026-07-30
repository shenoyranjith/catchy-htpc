#!/usr/bin/env bash
# Low-level Btrfs helpers shared by lib/snapshot.sh. Requires lib/log.sh.

# Prints the bare block device backing the root filesystem, stripping the
# "[/@subvolume]" suffix findmnt appends to the SOURCE field.
htpc_btrfs_root_device() {
    findmnt --noheadings --output SOURCE --target / | sed -E 's/\[.*\]//'
}

# Prints the subvolume path (e.g. "/@" or "/@/.snapshots/5/snapshot")
# currently mounted as the root filesystem.
htpc_btrfs_current_root_subvol() {
    findmnt --noheadings --output OPTIONS --target / \
        | grep -oE 'subvol=[^,]+' \
        | cut -d= -f2-
}

htpc_btrfs_snapshots_mounted_separately() {
    mountpoint -q /.snapshots
}

# Mounts the filesystem's top-level (subvolid=5) tree to a fresh temporary
# directory and prints its path. Pair with htpc_btrfs_unmount_top_level,
# ideally via a RETURN trap so it is unmounted even if the caller fails
# partway through. The trap must clear itself as its first action: in
# nested function calls, a RETURN trap keeps re-firing on every subsequent
# function return up the whole call stack, not just its own (confirmed on
# bash 3.2, which is what macOS ships), so leaving it registered would
# unmount an already-unmounted (or unrelated) path later on and can trip
# `set -e`.
#
#   top="$(htpc_btrfs_mount_top_level)"
#   trap "trap - RETURN; htpc_btrfs_unmount_top_level '${top}'" RETURN
htpc_btrfs_mount_top_level() {
    local device tmp_mount
    device="$(htpc_btrfs_root_device)"
    tmp_mount="$(mktemp -d)"
    mount -o subvolid=5 "${device}" "${tmp_mount}"
    printf '%s\n' "${tmp_mount}"
}

htpc_btrfs_unmount_top_level() {
    local tmp_mount="$1"
    umount "${tmp_mount}"
    rmdir "${tmp_mount}"
}
