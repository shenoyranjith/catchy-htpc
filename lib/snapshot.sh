#!/usr/bin/env bash
# Btrfs snapshot management via snapper + grub-btrfs, per recovery-spec.md.
# Requires lib/log.sh, lib/backup.sh, lib/packages.sh, and lib/btrfs.sh.

HTPC_SNAPPER_CONFIG="root"
HTPC_SNAPSHOT_DESCRIPTION_PREFIX="cachyos-htpc-installer"
HTPC_MKINITCPIO_CONF="/etc/mkinitcpio.conf"
HTPC_SNAPSHOTS_SUBVOL="@snapshots"

htpc_snapper_config_exists() {
    snapper --csvout --no-headers list-configs --columns config 2>/dev/null \
        | grep -qx "${HTPC_SNAPPER_CONFIG}"
}

htpc_mkinitcpio_ensure_hook() {
    local hook="$1"

    if [[ ! -f "${HTPC_MKINITCPIO_CONF}" ]]; then
        htpc_log_error "${HTPC_MKINITCPIO_CONF} not found."
        return 1
    fi

    if grep -qE "^HOOKS=.*\<${hook}\>" "${HTPC_MKINITCPIO_CONF}"; then
        htpc_log_info "mkinitcpio hook '${hook}' already present."
        return 0
    fi

    htpc_backup_file "${HTPC_MKINITCPIO_CONF}"

    sed -i -E "s/^(HOOKS=\([^)]*)\)/\1 ${hook})/" "${HTPC_MKINITCPIO_CONF}"

    if ! grep -qE "^HOOKS=.*\<${hook}\>" "${HTPC_MKINITCPIO_CONF}"; then
        htpc_log_error "Failed to add '${hook}' to ${HTPC_MKINITCPIO_CONF}."
        return 1
    fi

    htpc_log_info "Added '${hook}' to mkinitcpio HOOKS; regenerating initramfs."
    mkinitcpio -P
}

# Replaces the subvol=... option in a mount options string, keeping every
# other option (compression, ssd, discard, etc.) exactly as the caller's,
# rather than hardcoding mount flags that may not suit every installation.
htpc_replace_subvol_option() {
    local options="$1" subvol_name="$2"
    printf '%s' "${options}" | sed -E "s#subvol=[^,]*#subvol=/${subvol_name}#"
}

# Ensures snapshots live in their own top-level subvolume (a sibling of the
# root subvolume @), not nested inside it. This is required: restoring a
# snapshot replaces the root subvolume entirely, and a nested .snapshots
# directory would be destroyed at the exact moment it is needed. See
# recovery-spec.md.
htpc_snapshot_ensure_top_level_subvolume() {
    if htpc_btrfs_snapshots_mounted_separately; then
        htpc_log_info "/.snapshots is already a separate subvolume."
        return 0
    fi

    local device uuid root_options top
    device="$(htpc_btrfs_root_device)"
    uuid="$(blkid -s UUID -o value "${device}")"
    root_options="$(findmnt --noheadings --output OPTIONS --target /)"

    if [[ -z "${uuid}" ]]; then
        htpc_log_error "Could not determine the UUID of the root btrfs device."
        return 1
    fi

    top="$(htpc_btrfs_mount_top_level)"
    # shellcheck disable=SC2064 # intentional: expand ${top} now, not at trap time
    trap "htpc_btrfs_unmount_top_level '${top}'" RETURN

    if [[ ! -d "${top}/${HTPC_SNAPSHOTS_SUBVOL}" ]]; then
        htpc_log_info "Creating top-level subvolume ${HTPC_SNAPSHOTS_SUBVOL}."
        btrfs subvolume create "${top}/${HTPC_SNAPSHOTS_SUBVOL}"
    fi

    htpc_backup_file /etc/fstab
    printf 'UUID=%s /.snapshots btrfs %s 0 0\n' \
        "${uuid}" "$(htpc_replace_subvol_option "${root_options}" "${HTPC_SNAPSHOTS_SUBVOL}")" \
        >> /etc/fstab

    mkdir -p /.snapshots
    mount /.snapshots

    htpc_log_info "Mounted a dedicated top-level subvolume at /.snapshots."
}

# Installs and configures snapper + grub-btrfs so that bootable, writable
# snapshots can be created and shown in the GRUB menu. Idempotent: safe to
# call on every installer run.
htpc_snapshot_ensure_tooling() {
    htpc_packages_install snapper grub-btrfs inotify-tools

    htpc_snapshot_ensure_top_level_subvolume

    if ! htpc_snapper_config_exists; then
        htpc_log_info "Creating snapper config '${HTPC_SNAPPER_CONFIG}'."
        snapper -c "${HTPC_SNAPPER_CONFIG}" create-config /
    fi

    htpc_mkinitcpio_ensure_hook "grub-btrfs-overlayfs"

    systemctl enable --now grub-btrfsd.service
}

# Prints the number of the most recent installer-created snapshot, if any.
htpc_snapshot_find_previous() {
    snapper --csvout --no-headers -c "${HTPC_SNAPPER_CONFIG}" \
        list --columns number,description 2>/dev/null \
        | awk -F, -v prefix="${HTPC_SNAPSHOT_DESCRIPTION_PREFIX}" \
              'index($2, prefix) == 1 { print $1 }' \
        | tail -n 1
}

htpc_snapshot_delete() {
    local number="$1"
    htpc_log_info "Removing previous installer snapshot #${number}."
    snapper -c "${HTPC_SNAPPER_CONFIG}" delete "${number}"
}

# Creates a new installer snapshot and prints its number.
htpc_snapshot_create() {
    local description number
    description="${HTPC_SNAPSHOT_DESCRIPTION_PREFIX} $(date --iso-8601=seconds)"

    number="$(snapper -c "${HTPC_SNAPPER_CONFIG}" create \
        --type single --print-number --description "${description}")"

    htpc_log_info "Created snapshot #${number}: ${description}"
    printf '%s\n' "${number}"
}

# Makes an existing snapshot the new, permanent root subvolume, replacing
# the current one. snapper's own "rollback" command only changes the Btrfs
# default subvolume, which has no effect here: /etc/fstab mounts root using
# an explicit subvol=/@ name, and that name always wins at boot. So this
# performs the subvolume swap directly instead. See recovery-spec.md.
#
# The previous root subvolume is renamed to "@.broken-<timestamp>" rather
# than deleted, so it can still be inspected or recovered from afterward.
htpc_snapshot_restore() {
    local number="$1"

    if [[ ! "${number}" =~ ^[0-9]+$ ]]; then
        htpc_log_error "Usage: htpc-recovery restore <snapshot-number>"
        return 1
    fi

    if ! htpc_btrfs_snapshots_mounted_separately; then
        htpc_log_error "/.snapshots is not a separate subvolume. Run 'htpc-recovery setup' first."
        return 1
    fi

    if [[ "$(htpc_btrfs_current_root_subvol)" == "/@" ]]; then
        local reply
        htpc_log_warn "You appear to be booted into the normal system, not a snapshot."
        htpc_log_warn "It is safer to reboot, select the snapshot from the GRUB menu, and run this from there."
        read -r -p "Continue anyway? [y/N] " reply
        if [[ ! "${reply}" =~ ^[Yy]$ ]]; then
            htpc_log_info "Aborted."
            return 1
        fi
    fi

    local top backup_name
    top="$(htpc_btrfs_mount_top_level)"
    # shellcheck disable=SC2064 # intentional: expand ${top} now, not at trap time
    trap "htpc_btrfs_unmount_top_level '${top}'" RETURN

    if [[ ! -d "${top}/.snapshots/${number}/snapshot" ]]; then
        htpc_log_error "Snapshot #${number} not found at /.snapshots/${number}/snapshot."
        return 1
    fi

    backup_name="@.broken-$(date +%Y%m%d-%H%M%S)"

    if [[ -d "${top}/@" ]]; then
        htpc_log_warn "Renaming the current root subvolume to ${backup_name}."
        mv "${top}/@" "${top}/${backup_name}"
    fi

    htpc_log_info "Restoring snapshot #${number} as the new root subvolume."
    btrfs subvolume snapshot "${top}/.snapshots/${number}/snapshot" "${top}/@"

    if command -v grub-mkconfig >/dev/null 2>&1; then
        grub-mkconfig -o /boot/grub/grub.cfg \
            || htpc_log_warn "grub-mkconfig failed; you may need to regenerate the GRUB menu manually."
    fi

    htpc_log_info "Restore complete. The previous root is preserved as ${backup_name}."
    htpc_log_info "Reboot and select the normal boot entry."
    htpc_log_info "Once you have confirmed the system is stable, remove it with: htpc-recovery delete-backup ${backup_name}"
}

# Lists "@.broken-*" subvolumes left behind by htpc_snapshot_restore.
htpc_snapshot_list_backups() {
    local top
    top="$(htpc_btrfs_mount_top_level)"
    # shellcheck disable=SC2064 # intentional: expand ${top} now, not at trap time
    trap "htpc_btrfs_unmount_top_level '${top}'" RETURN

    find "${top}" -mindepth 1 -maxdepth 1 -name '@.broken-*' -printf '%f\n'
}

# Deletes a "@.broken-*" backup subvolume left behind by
# htpc_snapshot_restore, to reclaim disk space.
htpc_snapshot_delete_backup() {
    local name="$1"

    if [[ "${name}" != @.broken-* ]]; then
        htpc_log_error "Refusing to delete '${name}': not a backup created by 'htpc-recovery restore'."
        return 1
    fi

    local top
    top="$(htpc_btrfs_mount_top_level)"
    # shellcheck disable=SC2064 # intentional: expand ${top} now, not at trap time
    trap "htpc_btrfs_unmount_top_level '${top}'" RETURN

    if [[ ! -d "${top}/${name}" ]]; then
        htpc_log_error "No such backup subvolume: ${name}"
        return 1
    fi

    btrfs subvolume delete "${top}/${name}"
    htpc_log_info "Deleted backup subvolume ${name}."
}
