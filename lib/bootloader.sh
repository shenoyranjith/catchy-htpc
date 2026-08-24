#!/usr/bin/env bash
# Detects the active bootloader (GRUB vs Limine) so recovery/snapshot
# tooling can install the matching snapper integration. Requires lib/log.sh.
#
# CachyOS installs often leave both families of packages present after a
# migration; the *currently running* bootloader is the source of truth.

# Prints "limine" or "grub". Exits non-zero (via htpc_log_error) if neither
# can be determined with confidence.
htpc_bootloader_detect() {
    local product entry current conf

    if command -v bootctl >/dev/null 2>&1; then
        product="$(bootctl status 2>/dev/null \
            | awk '
                /^Current Boot Loader:/ { in_loader = 1; next }
                in_loader && /^[[:space:]]*Product:/ {
                    sub(/^[[:space:]]*Product:[[:space:]]*/, "")
                    print
                    exit
                }
            ')"
        if [[ "${product}" =~ [Ll]imine ]]; then
            printf 'limine\n'
            return 0
        fi
        if [[ "${product}" =~ [Gg][Rr][Uu][Bb] ]]; then
            printf 'grub\n'
            return 0
        fi
    fi

    if command -v efibootmgr >/dev/null 2>&1; then
        current="$(efibootmgr 2>/dev/null | sed -n 's/^BootCurrent:[[:space:]]*//p')"
        if [[ -n "${current}" ]]; then
            entry="$(efibootmgr 2>/dev/null | grep -E "^Boot${current}" || true)"
            if [[ "${entry}" =~ [Ll]imine ]]; then
                printf 'limine\n'
                return 0
            fi
            if [[ "${entry}" =~ [Gg][Rr][Uu][Bb] ]]; then
                printf 'grub\n'
                return 0
            fi
        fi
    fi

    for conf in /boot/limine.conf /efi/limine.conf /boot/EFI/limine/limine.conf; do
        if [[ -f "${conf}" ]]; then
            printf 'limine\n'
            return 0
        fi
    done

    if [[ -f /boot/grub/grub.cfg ]] || [[ -d /boot/grub ]]; then
        printf 'grub\n'
        return 0
    fi

    htpc_log_error "Could not detect bootloader (expected Limine or GRUB). Set up the bootloader first, then re-run."
    return 1
}

# Human-readable boot menu name for messages ("Limine" / "GRUB").
htpc_bootloader_menu_name() {
    case "${1:-}" in
        limine) printf 'Limine\n' ;;
        grub)   printf 'GRUB\n' ;;
        *)      printf 'bootloader\n' ;;
    esac
}

# Snapshot-integration packages for the given bootloader (one per line).
# snapper + inotify-tools are shared and listed by the installer separately.
htpc_bootloader_snapshot_packages() {
    case "${1:-}" in
        limine)
            printf '%s\n' limine-snapper-sync limine-mkinitcpio-hook
            ;;
        grub)
            printf '%s\n' grub-btrfs
            ;;
        *)
            htpc_log_error "Unknown bootloader '${1:-}'."
            return 1
            ;;
    esac
}
