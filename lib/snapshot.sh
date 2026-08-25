#!/usr/bin/env bash
# Btrfs snapshot management via snapper + bootloader-specific menu sync
# (grub-btrfs or limine-snapper-sync), per recovery-spec.md.
# Requires lib/log.sh, lib/backup.sh, lib/packages.sh, lib/btrfs.sh,
# and lib/bootloader.sh.

HTPC_SNAPPER_CONFIG="root"
HTPC_SNAPSHOT_DESCRIPTION_PREFIX="cachyos-htpc-installer"
HTPC_MKINITCPIO_CONF="/etc/mkinitcpio.conf"
HTPC_SNAPSHOTS_SUBVOL="@snapshots"

htpc_snapper_config_exists() {
    snapper --csvout --no-headers list-configs --columns config 2>/dev/null \
        | grep -qx "${HTPC_SNAPPER_CONFIG}"
}

# True when mkinitcpio HOOKS use the systemd base (needs sd-btrfs-overlayfs
# rather than btrfs-overlayfs for Limine writable snapshot boots).
htpc_mkinitcpio_hooks_use_systemd() {
    grep -qE '^HOOKS=\([^)]*\bsystemd\b' "${HTPC_MKINITCPIO_CONF}"
}

# Removes a single whole token from HOOKS=(...). Must match the full hook
# name (not a hyphenated substring -- e.g. removing btrfs-overlayfs must
# not mangle grub-btrfs-overlayfs into "grub-").
htpc_mkinitcpio_remove_hook() {
    local hook="$1" line inside new_inside=() token

    if [[ ! -f "${HTPC_MKINITCPIO_CONF}" ]]; then
        return 0
    fi
    if ! htpc_mkinitcpio_hook_present "${hook}"; then
        return 0
    fi

    line="$(grep -E '^HOOKS=' "${HTPC_MKINITCPIO_CONF}")"
    inside="${line#HOOKS=(}"
    inside="${inside%)}"
    # shellcheck disable=SC2086 # intentional word-splitting of HOOKS tokens
    for token in ${inside}; do
        if [[ "${token}" == "${hook}" ]]; then
            continue
        fi
        new_inside+=("${token}")
    done

    sed -i -E "s|^HOOKS=\([^)]*\)|HOOKS=(${new_inside[*]})|" "${HTPC_MKINITCPIO_CONF}"
    htpc_log_info "Removed mkinitcpio hook '${hook}'."
}

# True when HOOKS contains the exact hook token (space/paren delimited).
htpc_mkinitcpio_hook_present() {
    local hook="$1" line inside token

    [[ -f "${HTPC_MKINITCPIO_CONF}" ]] || return 1
    line="$(grep -E '^HOOKS=' "${HTPC_MKINITCPIO_CONF}")" || return 1
    inside="${line#HOOKS=(}"
    inside="${inside%)}"
    # shellcheck disable=SC2086
    for token in ${inside}; do
        if [[ "${token}" == "${hook}" ]]; then
            return 0
        fi
    done
    return 1
}

htpc_mkinitcpio_regenerate() {
    local bootloader="${1:-}"
    if [[ "${bootloader}" == "limine" ]] && command -v limine-mkinitcpio >/dev/null 2>&1; then
        htpc_log_info "Regenerating initramfs via limine-mkinitcpio."
        limine-mkinitcpio
    else
        htpc_log_info "Regenerating initramfs via mkinitcpio -P."
        mkinitcpio -P
    fi
}

# Ensures hook is listed in HOOKS=(...), preferring insertion right after
# the filesystems hook when present.
htpc_mkinitcpio_add_hook() {
    local hook="$1"

    if [[ ! -f "${HTPC_MKINITCPIO_CONF}" ]]; then
        htpc_log_error "${HTPC_MKINITCPIO_CONF} not found."
        return 1
    fi

    if htpc_mkinitcpio_hook_present "${hook}"; then
        htpc_log_info "mkinitcpio hook '${hook}' already present."
        return 0
    fi

    if grep -qE '^HOOKS=\([^)]*\bfilesystems\b' "${HTPC_MKINITCPIO_CONF}"; then
        sed -i -E "s/^(HOOKS=\([^)]*)\<filesystems\>/\1filesystems ${hook}/" \
            "${HTPC_MKINITCPIO_CONF}"
    else
        sed -i -E "s/^(HOOKS=\([^)]*)\)/\1 ${hook})/" "${HTPC_MKINITCPIO_CONF}"
    fi

    if ! htpc_mkinitcpio_hook_present "${hook}"; then
        htpc_log_error "Failed to add '${hook}' to ${HTPC_MKINITCPIO_CONF}."
        return 1
    fi

    htpc_log_info "Added '${hook}' to mkinitcpio HOOKS."
}

# Installs the overlayfs hook needed for writable snapshot boots for the
# detected bootloader, removing any conflicting overlay hook left over
# from the other family (common after GRUB↔Limine migrations).
htpc_mkinitcpio_ensure_overlay_hook() {
    local bootloader="$1"
    local desired
    local -a remove=()
    local hook changed=false

    if [[ ! -f "${HTPC_MKINITCPIO_CONF}" ]]; then
        htpc_log_error "${HTPC_MKINITCPIO_CONF} not found."
        return 1
    fi

    case "${bootloader}" in
        limine)
            if htpc_mkinitcpio_hooks_use_systemd; then
                desired="sd-btrfs-overlayfs"
                remove+=(btrfs-overlayfs grub-btrfs-overlayfs)
            else
                desired="btrfs-overlayfs"
                remove+=(sd-btrfs-overlayfs grub-btrfs-overlayfs)
            fi
            ;;
        grub)
            desired="grub-btrfs-overlayfs"
            remove+=(btrfs-overlayfs sd-btrfs-overlayfs)
            ;;
        *)
            htpc_log_error "Unknown bootloader '${bootloader}'."
            return 1
            ;;
    esac

    for hook in "${remove[@]}"; do
        if htpc_mkinitcpio_hook_present "${hook}"; then
            if [[ "${changed}" == false ]]; then
                htpc_backup_file "${HTPC_MKINITCPIO_CONF}"
                changed=true
            fi
            htpc_mkinitcpio_remove_hook "${hook}"
        fi
    done

    if ! htpc_mkinitcpio_hook_present "${desired}"; then
        if [[ "${changed}" == false ]]; then
            htpc_backup_file "${HTPC_MKINITCPIO_CONF}"
            changed=true
        fi
        htpc_mkinitcpio_add_hook "${desired}" || return 1
    else
        htpc_log_info "mkinitcpio hook '${desired}' already present."
    fi

    if [[ "${changed}" == true ]]; then
        htpc_mkinitcpio_regenerate "${bootloader}"
    fi
}

# Replaces the subvol=... option in a mount options string with the given
# subvolume name, keeping every other option (compression, ssd, discard,
# etc.) exactly as the caller's, rather than hardcoding mount flags that
# may not suit every installation. Also strips any subvolid=NNN: findmnt
# reports both together for btrfs, and leaving the old numeric ID in place
# would conflict with the new subvol= path and make the mount fail.
htpc_replace_subvol_option() {
    local options="$1" subvol_name="$2"
    printf '%s' "${options}" \
        | sed -E 's/(^|,)subvolid=[0-9]+//' \
        | sed -E "s#subvol=[^,]*#subvol=/${subvol_name}#" \
        | sed -E 's/,{2,}/,/g; s/^,//; s/,$//'
}

# Removes any existing fstab entry for the given mountpoint (matched on the
# exact mountpoint field, not by text search), so this module can be safely
# re-run after a previous attempt left a bad or stale entry behind.
htpc_fstab_remove_mountpoint() {
    local mountpoint="$1" tmp
    tmp="$(mktemp)"

    awk -v mp="${mountpoint}" '$1 !~ /^#/ && $2 == mp { next } { print }' \
        /etc/fstab > "${tmp}"

    if ! cmp -s "${tmp}" /etc/fstab; then
        htpc_backup_file /etc/fstab
        cat "${tmp}" > /etc/fstab
        htpc_log_info "Removed stale fstab entry for ${mountpoint}."
    fi

    rm -f "${tmp}"
}

# Ensures snapshots live in their own top-level subvolume (a sibling of the
# root subvolume @), not nested inside it. This is required: restoring a
# snapshot replaces the root subvolume entirely, and a nested .snapshots
# directory would be destroyed at the exact moment it is needed. See
# recovery-spec.md.
#
# CachyOS ships with snapper already configured by default, using the
# standard nested layout (.snapshots as a subvolume inside the root
# subvolume), often with real history already in it (pacman pre/post
# snapshots, an install-time baseline, etc.). If found, it is *moved* to
# become the top-level subvolume rather than recreated from scratch. Within
# the same btrfs filesystem this is a metadata-only rename: no snapshot
# data is copied or touched, so all existing history is preserved exactly
# as-is, just relocated to a safer location.
htpc_snapshot_ensure_top_level_subvolume() {
    if htpc_btrfs_snapshots_mounted_separately; then
        htpc_log_info "/.snapshots is already a separate subvolume."
        return 0
    fi

    local device uuid root_options current_subvol top nested_snapshots
    device="$(htpc_btrfs_root_device)"
    uuid="$(blkid -s UUID -o value "${device}")"
    root_options="$(findmnt --noheadings --output OPTIONS --target /)"
    current_subvol="$(htpc_btrfs_current_root_subvol)"

    if [[ -z "${uuid}" ]]; then
        htpc_log_error "Could not determine the UUID of the root btrfs device."
        return 1
    fi

    top="$(htpc_btrfs_mount_top_level)"
    # shellcheck disable=SC2064 # intentional: expand ${top} now, not at trap time
    trap "trap - RETURN; htpc_btrfs_unmount_top_level '${top}'" RETURN

    nested_snapshots="${top}${current_subvol}/.snapshots"

    if [[ -d "${top}/${HTPC_SNAPSHOTS_SUBVOL}" ]]; then
        htpc_log_info "Top-level subvolume ${HTPC_SNAPSHOTS_SUBVOL} already exists."
    elif [[ -d "${nested_snapshots}" ]]; then
        htpc_log_warn "Found an existing .snapshots subvolume nested inside ${current_subvol} (likely CachyOS's default snapper setup)."
        htpc_log_warn "Moving it to a top-level ${HTPC_SNAPSHOTS_SUBVOL} subvolume. This preserves all existing snapshots; no data is copied or deleted."
        mv "${nested_snapshots}" "${top}/${HTPC_SNAPSHOTS_SUBVOL}"
    else
        htpc_log_info "Creating top-level subvolume ${HTPC_SNAPSHOTS_SUBVOL}."
        btrfs subvolume create "${top}/${HTPC_SNAPSHOTS_SUBVOL}"
    fi

    htpc_backup_file /etc/fstab
    htpc_fstab_remove_mountpoint "/.snapshots"
    printf 'UUID=%s /.snapshots btrfs %s 0 0\n' \
        "${uuid}" "$(htpc_replace_subvol_option "${root_options}" "${HTPC_SNAPSHOTS_SUBVOL}")" \
        >> /etc/fstab

    mkdir -p /.snapshots
    mount /.snapshots

    htpc_log_info "Mounted a dedicated top-level subvolume at /.snapshots."
}

htpc_snapshot_ensure_tooling_grub() {
    htpc_packages_install grub-btrfs

    htpc_mkinitcpio_ensure_overlay_hook grub

    if systemctl cat limine-snapper-sync.service >/dev/null 2>&1; then
        systemctl disable --now limine-snapper-sync.service 2>/dev/null || true
        htpc_log_info "Disabled limine-snapper-sync.service (active bootloader is GRUB)."
    fi

    systemctl enable grub-btrfsd.service
    # Restarted rather than just started, so it re-establishes its watch
    # cleanly if /.snapshots was just moved to a new mount by
    # htpc_snapshot_ensure_top_level_subvolume.
    systemctl restart grub-btrfsd.service
}

htpc_snapshot_ensure_tooling_limine() {
    htpc_packages_install limine-snapper-sync limine-mkinitcpio-hook

    htpc_mkinitcpio_ensure_overlay_hook limine

    if systemctl cat grub-btrfsd.service >/dev/null 2>&1; then
        systemctl disable --now grub-btrfsd.service 2>/dev/null || true
        htpc_log_info "Disabled grub-btrfsd.service (active bootloader is Limine)."
    fi

    systemctl enable limine-snapper-sync.service
    systemctl restart limine-snapper-sync.service
    # Refresh snapshot boot entries now that /.snapshots / overlay hooks
    # may have changed.
    if command -v limine-snapper-sync >/dev/null 2>&1; then
        limine-snapper-sync \
            || htpc_log_warn "limine-snapper-sync failed; snapshot boot entries may be stale until the next sync."
    fi
}

# Installs and configures snapper + the matching bootloader snapshot
# integration so bootable, writable snapshots appear in the boot menu.
# Idempotent: safe to call on every installer run.
htpc_snapshot_ensure_tooling() {
    local bootloader menu

    bootloader="$(htpc_bootloader_detect)"
    menu="$(htpc_bootloader_menu_name "${bootloader}")"
    htpc_log_info "Detected bootloader: ${menu}."

    # Shared packages first: top-level subvolume layout and snapper config
    # both need snapper / btrfs tooling available.
    htpc_packages_install snapper inotify-tools

    htpc_snapshot_ensure_top_level_subvolume

    if ! htpc_snapper_config_exists; then
        htpc_log_info "Creating snapper config '${HTPC_SNAPPER_CONFIG}'."
        snapper -c "${HTPC_SNAPPER_CONFIG}" create-config /
    fi

    case "${bootloader}" in
        limine) htpc_snapshot_ensure_tooling_limine ;;
        grub)   htpc_snapshot_ensure_tooling_grub ;;
    esac
}

# Prints the number of the most recent installer-created snapshot, if any.
htpc_snapshot_find_previous() {
    snapper --csvout --no-headers -c "${HTPC_SNAPPER_CONFIG}" \
        list --columns number,description 2>/dev/null \
        | awk -F, -v prefix="${HTPC_SNAPSHOT_DESCRIPTION_PREFIX}" \
              'index($2, prefix) == 1 { print $1 }' \
        | tail -n 1
}

# Lists snapper snapshots (what restore <number> accepts). Distinct from
# htpc_snapshot_list_backups, which only shows @.broken-* leftovers from
# a prior restore.
htpc_snapshot_list() {
    if ! htpc_snapper_config_exists; then
        htpc_log_error "Snapper config '${HTPC_SNAPPER_CONFIG}' not found. Run 'htpc-recovery setup' first."
        return 1
    fi

    snapper -c "${HTPC_SNAPPER_CONFIG}" list
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

# Regenerates bootloader config after a restore from a normal (non-snapshot)
# boot. From within a snapshot boot, /boot is typically not writable and
# regeneration is unnecessary: the normal entry boots by subvolume name (@).
htpc_snapshot_regenerate_bootloader() {
    local bootloader="$1"

    case "${bootloader}" in
        grub)
            if command -v grub-mkconfig >/dev/null 2>&1; then
                grub-mkconfig -o /boot/grub/grub.cfg \
                    || htpc_log_warn "grub-mkconfig failed; you may need to regenerate the GRUB menu manually."
            else
                htpc_log_warn "grub-mkconfig not found; skipping GRUB regeneration."
            fi
            ;;
        limine)
            if command -v limine-snapper-sync >/dev/null 2>&1; then
                limine-snapper-sync \
                    || htpc_log_warn "limine-snapper-sync failed; you may need to refresh Limine snapshot entries manually."
            elif command -v limine-update >/dev/null 2>&1; then
                limine-update \
                    || htpc_log_warn "limine-update failed; you may need to refresh Limine entries manually."
            else
                htpc_log_warn "Neither limine-snapper-sync nor limine-update found; skipping Limine regeneration."
            fi
            ;;
    esac
}

# Makes an existing snapshot the new, permanent root subvolume, replacing
# the current one. snapper's own "rollback" command only changes the Btrfs
# default subvolume, which has no effect here: /etc/fstab mounts root using
# an explicit subvol=/@ name, and that name always wins at boot. So this
# performs the subvolume swap directly instead. See recovery-spec.md.
#
# The previous root subvolume is renamed to "@.broken-<timestamp>" rather
# than deleted, so it can still be inspected or recovered from afterward.
#
# The bootloader menu is only regenerated when run from a normal boot. From
# within a snapshot boot (the recommended way to run this), /boot is not
# writable, and it is not needed anyway: the normal boot entry boots by
# subvolume name (@), not a hardcoded path, so it picks up the restored
# content on its own once rebooted.
htpc_snapshot_restore() {
    local number="$1"
    local bootloader menu

    if [[ ! "${number}" =~ ^[0-9]+$ ]]; then
        htpc_log_error "Usage: htpc-recovery restore <snapshot-number>"
        return 1
    fi

    if ! htpc_btrfs_snapshots_mounted_separately; then
        htpc_log_error "/.snapshots is not a separate subvolume. Run 'htpc-recovery setup' first."
        return 1
    fi

    bootloader="$(htpc_bootloader_detect)"
    menu="$(htpc_bootloader_menu_name "${bootloader}")"

    local booted_from_snapshot=true
    if [[ "$(htpc_btrfs_current_root_subvol)" == "/@" ]]; then
        local reply
        booted_from_snapshot=false
        htpc_log_warn "You appear to be booted into the normal system, not a snapshot."
        htpc_log_warn "It is safer to reboot, select the snapshot from the ${menu} menu, and run this from there."
        read -r -p "Continue anyway? [y/N] " reply
        if [[ ! "${reply}" =~ ^[Yy]$ ]]; then
            htpc_log_info "Aborted."
            return 1
        fi
    fi

    local top backup_name
    top="$(htpc_btrfs_mount_top_level)"
    # shellcheck disable=SC2064 # intentional: expand ${top} now, not at trap time
    trap "trap - RETURN; htpc_btrfs_unmount_top_level '${top}'" RETURN

    if [[ ! -d "${top}/${HTPC_SNAPSHOTS_SUBVOL}/${number}/snapshot" ]]; then
        htpc_log_error "Snapshot #${number} not found at /.snapshots/${number}/snapshot."
        return 1
    fi

    backup_name="@.broken-$(date +%Y%m%d-%H%M%S)"

    if [[ -d "${top}/@" ]]; then
        htpc_log_warn "Renaming the current root subvolume to ${backup_name}."
        mv "${top}/@" "${top}/${backup_name}"
    fi

    htpc_log_info "Restoring snapshot #${number} as the new root subvolume."
    btrfs subvolume snapshot "${top}/${HTPC_SNAPSHOTS_SUBVOL}/${number}/snapshot" "${top}/@"

    if [[ "${booted_from_snapshot}" == true ]]; then
        htpc_log_info "Skipping ${menu} regeneration: /boot is not writable from within a snapshot boot session."
        htpc_log_info "This is not required: the normal boot entry boots by subvolume name (@), not a hardcoded path, so it will pick up the restored content automatically."
    else
        htpc_snapshot_regenerate_bootloader "${bootloader}"
    fi

    htpc_log_info "Restore complete. The previous root is preserved as ${backup_name}."
    htpc_log_info "Reboot and select the normal boot entry."
    htpc_log_info "Once you have confirmed the system is stable, remove it with: htpc-recovery delete-backup ${backup_name}"
}

# Lists "@.broken-*" subvolumes left behind by htpc_snapshot_restore.
htpc_snapshot_list_backups() {
    local top
    local -a backups=()

    top="$(htpc_btrfs_mount_top_level)"
    # shellcheck disable=SC2064 # intentional: expand ${top} now, not at trap time
    trap "trap - RETURN; htpc_btrfs_unmount_top_level '${top}'" RETURN

    mapfile -t backups < <(find "${top}" -mindepth 1 -maxdepth 1 -name '@.broken-*' -printf '%f\n' | sort)

    if [[ "${#backups[@]}" -eq 0 ]]; then
        htpc_log_info "No @.broken-* restore leftovers found."
        htpc_log_info "Snapper snapshots (for 'htpc-recovery restore <number>') are listed with: htpc-recovery list"
        return 0
    fi

    printf '%s\n' "${backups[@]}"
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
    trap "trap - RETURN; htpc_btrfs_unmount_top_level '${top}'" RETURN

    if [[ ! -d "${top}/${name}" ]]; then
        htpc_log_error "No such backup subvolume: ${name}"
        return 1
    fi

    btrfs subvolume delete "${top}/${name}"
    htpc_log_info "Deleted backup subvolume ${name}."
}
