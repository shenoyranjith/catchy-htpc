#!/usr/bin/env bash
# GPU vendor detection and NVIDIA merged Steam Gaming Mode helpers.
# Requires lib/log.sh. See session-lifecycle.md and session-services-spec.md.
#
# Steam Gaming Mode:
#   - AMD: dedicated htpc-steam.service (gamescope-session-cachyos)
#   - NVIDIA: same htpc-desktop.service as KDE Desktop; nested gamescope +
#     steam -steamdeck via bin/htpc-steamdeck-launch (Steam must be quit
#     first). Exclusive DRM gamescope under a system unit failed Steam's
#     userns/bwrap check on this hardware.

HTPC_GPU_VENDOR_FILE="/etc/cachyos-htpc/gpu-vendor"
HTPC_STEAM_BIGPICTURE_TMPFILES_CONF="/etc/tmpfiles.d/cachyos-htpc.conf"
HTPC_STEAM_BIGPICTURE_RUNTIME_DIR="/run/cachyos-htpc"
HTPC_STEAM_BOOT_MARKER_DEST="/usr/local/bin/htpc-steam-bigpicture-boot-marker"
HTPC_STEAM_AUTOSTART_DEST="/usr/local/bin/htpc-steam-autostart"
HTPC_STEAMDECK_LAUNCH_DEST="/usr/local/bin/htpc-steamdeck-launch"

htpc_gpu_autostart_script_source_path() {
    printf '%s\n' "$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)/htpc-steam-autostart"
}

htpc_gpu_boot_marker_source_path() {
    printf '%s\n' "$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)/htpc-steam-bigpicture-boot-marker"
}

htpc_gpu_autostart_desktop_source_path() {
    printf '%s\n' "$(cd "$(dirname "${BASH_SOURCE[0]}")/../autostart" && pwd)/htpc-steam-autostart.desktop"
}

htpc_gpu_steamdeck_launch_source_path() {
    printf '%s\n' "$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)/htpc-steamdeck-launch"
}

htpc_gpu_tmpfiles_template_path() {
    printf '%s\n' "$(cd "$(dirname "${BASH_SOURCE[0]}")/../systemd" && pwd)/cachyos-htpc-tmpfiles.conf"
}

# True if an NVIDIA GPU is present, via `lspci -k`. Captures lspci's
# output and greps it separately rather than piping directly into grep:
# under `set -o pipefail` (used throughout this project), lspci exiting
# non-zero for any reason (even while still printing valid output on
# stdout) would otherwise fail the whole pipeline and make this always
# report "not NVIDIA" regardless of the actual hardware -- confirmed live
# to be a real failure mode, not just theoretical.
htpc_gpu_is_nvidia() {
    if ! command -v lspci >/dev/null 2>&1; then
        return 1
    fi

    local output
    output="$(lspci -k 2>/dev/null)" || true
    printf '%s\n' "${output}" | grep -qi nvidia
}

# Prints "nvidia" or "amd" for the currently installed GPU. Only ever
# distinguishes these two: any non-NVIDIA GPU (AMD, Intel, or none
# detected) is treated as "amd" -- i.e. gamescope-session-cachyos Steam
# Gaming Mode, the long-standing default this project was built around.
htpc_gpu_vendor_detect() {
    if htpc_gpu_is_nvidia; then
        printf 'nvidia\n'
    else
        printf 'amd\n'
    fi
}

# Persists the detected GPU vendor to a fixed system path so htpc-switch
# (a self-contained script; see its own header) and the steam launch
# script can read it back without depending on this project's lib/ tree
# still being present. Idempotent. Prints the detected vendor either way,
# so callers can capture it in the same call.
htpc_gpu_vendor_install() {
    local vendor
    vendor="$(htpc_gpu_vendor_detect)"

    install -d -m 0755 "$(dirname "${HTPC_GPU_VENDOR_FILE}")"
    if [[ -f "${HTPC_GPU_VENDOR_FILE}" ]] && [[ "$(cat "${HTPC_GPU_VENDOR_FILE}")" == "${vendor}" ]]; then
        htpc_log_info "GPU vendor already recorded as ${vendor}."
    else
        printf '%s\n' "${vendor}" > "${HTPC_GPU_VENDOR_FILE}"
        htpc_log_info "Detected GPU vendor: ${vendor}."
    fi

    printf '%s\n' "${vendor}"
}

# Reverses htpc_gpu_vendor_install.
htpc_gpu_vendor_uninstall() {
    if [[ -f "${HTPC_GPU_VENDOR_FILE}" ]]; then
        rm -f "${HTPC_GPU_VENDOR_FILE}"
        htpc_log_info "Removed ${HTPC_GPU_VENDOR_FILE}."
    fi
}

# Reads back the persisted GPU vendor, defaulting to "amd" if never recorded.
htpc_gpu_vendor_get() {
    if [[ -r "${HTPC_GPU_VENDOR_FILE}" ]]; then
        cat "${HTPC_GPU_VENDOR_FILE}"
    else
        printf 'amd\n'
    fi
}

# Resolves a session name (kodi/steam/desktop) to the systemd unit that
# backs it. On NVIDIA, "steam" is htpc-desktop.service (nested Deck UI).
htpc_session_unit_for() {
    local target="$1"
    if [[ "${target}" == "steam" ]] && [[ "$(htpc_gpu_vendor_get)" == "nvidia" ]]; then
        printf 'htpc-desktop.service\n'
    else
        printf 'htpc-%s.service\n' "${target}"
    fi
}

# --- NVIDIA Plasma session helpers (Gaming Mode marker / autostart) ---

# Installs the tmpfiles.d drop-in that creates /run/cachyos-htpc (owned by
# the target user) on every boot, before any htpc-*.service unit starts.
# This is where HTPC_STEAM_BIGPICTURE lives (see htpc-switch and
# bin/htpc-steam-bigpicture-boot-marker).
#
# /run rather than the user's own home directory or XDG_RUNTIME_DIR: it
# needs to exist and be user-writable regardless of PAM/session timing
# (XDG_RUNTIME_DIR is not guaranteed to exist yet when a unit's
# ExecStartPre runs -- ExecStartPre does not wait on PAMName= session
# setup, only the unit's own main ExecStart does), and it must be reliably
# cleared exactly once per real reboot (unlike a file under the user's
# home directory), so a stale value from a previous boot never leaks into
# htpc-desktop.service's own ExecStartPre logic.
htpc_steam_bigpicture_runtime_dir_install() {
    local target_user="$1"
    local template dest tmp

    template="$(htpc_gpu_tmpfiles_template_path)"
    dest="${HTPC_STEAM_BIGPICTURE_TMPFILES_CONF}"

    if [[ ! -f "${template}" ]]; then
        htpc_log_error "No tmpfiles.d template found at ${template}."
        return 1
    fi

    tmp="$(mktemp)"
    sed "s/__HTPC_USER__/${target_user}/g" "${template}" > "${tmp}"

    if [[ -f "${dest}" ]] && cmp -s "${tmp}" "${dest}"; then
        rm -f "${tmp}"
        htpc_log_info "${dest} already installed and up to date."
    else
        install -m 0644 "${tmp}" "${dest}"
        rm -f "${tmp}"
        htpc_log_info "Installed ${dest}."
    fi

    if systemd-tmpfiles --create "${dest}" >/dev/null 2>&1; then
        htpc_log_info "Created ${HTPC_STEAM_BIGPICTURE_RUNTIME_DIR}."
    else
        htpc_log_warn "Could not create ${HTPC_STEAM_BIGPICTURE_RUNTIME_DIR} immediately; it will be created on next boot instead."
    fi
}

# Reverses htpc_steam_bigpicture_runtime_dir_install.
htpc_steam_bigpicture_runtime_dir_uninstall() {
    if [[ -f "${HTPC_STEAM_BIGPICTURE_TMPFILES_CONF}" ]]; then
        rm -f "${HTPC_STEAM_BIGPICTURE_TMPFILES_CONF}"
        htpc_log_info "Removed ${HTPC_STEAM_BIGPICTURE_TMPFILES_CONF}."
    fi
    rm -rf "${HTPC_STEAM_BIGPICTURE_RUNTIME_DIR}"
}

# Installs bin/htpc-steam-bigpicture-boot-marker, run as
# htpc-desktop.service's own ExecStartPre so a cold boot into Steam Gaming
# Mode (NVIDIA only; see "Boot Configuration" in installer-spec.md) opens
# Big Picture immediately rather than landing on a plain desktop.
# Idempotent.
htpc_steam_bigpicture_boot_marker_install() {
    local script dest
    script="$(htpc_gpu_boot_marker_source_path)"
    dest="${HTPC_STEAM_BOOT_MARKER_DEST}"

    if [[ ! -f "${script}" ]]; then
        htpc_log_error "htpc-steam-bigpicture-boot-marker script not found at ${script}."
        return 1
    fi

    if [[ -f "${dest}" ]] && cmp -s "${script}" "${dest}"; then
        htpc_log_info "htpc-steam-bigpicture-boot-marker already installed and up to date."
        return 0
    fi

    install -m 0755 "${script}" "${dest}"
    htpc_log_info "Installed htpc-steam-bigpicture-boot-marker to ${dest}."
}

# Reverses htpc_steam_bigpicture_boot_marker_install.
htpc_steam_bigpicture_boot_marker_uninstall() {
    if [[ -f "${HTPC_STEAM_BOOT_MARKER_DEST}" ]]; then
        rm -f "${HTPC_STEAM_BOOT_MARKER_DEST}"
        htpc_log_info "Removed ${HTPC_STEAM_BOOT_MARKER_DEST}."
    fi
}

# Installs bin/htpc-steam-autostart as a KDE autostart entry for the
# target user's own Plasma session (~/.config/autostart, the same place
# KDE's own System Settings "Autostart" page manages, so the user can see
# or disable it there too). NVIDIA only: see this file's own header for
# why Steam autostarts unconditionally with KDE Desktop there instead of
# running under its own gamescope session. Idempotent.
htpc_steam_autostart_install() {
    local target_user="$1"
    local script script_dest home autostart_dir desktop_source desktop_dest

    script="$(htpc_gpu_autostart_script_source_path)"
    script_dest="${HTPC_STEAM_AUTOSTART_DEST}"
    if [[ ! -f "${script}" ]]; then
        htpc_log_error "htpc-steam-autostart script not found at ${script}."
        return 1
    fi
    if [[ -f "${script_dest}" ]] && cmp -s "${script}" "${script_dest}"; then
        htpc_log_info "htpc-steam-autostart already installed and up to date."
    else
        install -m 0755 "${script}" "${script_dest}"
        htpc_log_info "Installed htpc-steam-autostart to ${script_dest}."
    fi

    home="$(getent passwd "${target_user}" | cut -d: -f6)"
    if [[ -z "${home}" ]]; then
        htpc_log_error "Could not determine home directory for user ${target_user}."
        return 1
    fi
    autostart_dir="${home}/.config/autostart"
    desktop_source="$(htpc_gpu_autostart_desktop_source_path)"
    desktop_dest="${autostart_dir}/htpc-steam-autostart.desktop"

    if [[ ! -f "${desktop_source}" ]]; then
        htpc_log_error "htpc-steam-autostart.desktop not found at ${desktop_source}."
        return 1
    fi

    if [[ -f "${desktop_dest}" ]] && cmp -s "${desktop_source}" "${desktop_dest}"; then
        htpc_log_info "htpc-steam-autostart.desktop already installed and up to date."
        return 0
    fi

    install -d -o "${target_user}" -g "${target_user}" -m 0755 \
        "${home}/.config" "${autostart_dir}"
    install -o "${target_user}" -g "${target_user}" -m 0644 "${desktop_source}" "${desktop_dest}"
    htpc_log_info "Installed ${desktop_dest} for ${target_user}."
}

# Reverses htpc_steam_autostart_install.
htpc_steam_autostart_uninstall() {
    local target_user="$1"
    local home desktop_dest

    if [[ -f "${HTPC_STEAM_AUTOSTART_DEST}" ]]; then
        rm -f "${HTPC_STEAM_AUTOSTART_DEST}"
        htpc_log_info "Removed ${HTPC_STEAM_AUTOSTART_DEST}."
    fi

    home="$(getent passwd "${target_user}" | cut -d: -f6 2>/dev/null || true)"
    if [[ -z "${home}" ]]; then
        return 0
    fi
    desktop_dest="${home}/.config/autostart/htpc-steam-autostart.desktop"
    if [[ -f "${desktop_dest}" ]]; then
        rm -f "${desktop_dest}"
        htpc_log_info "Removed ${desktop_dest}."
    fi
}

# Installs bin/htpc-steamdeck-launch (nested gamescope Deck UI). NVIDIA only.
htpc_steamdeck_launch_install() {
    local script dest
    script="$(htpc_gpu_steamdeck_launch_source_path)"
    dest="${HTPC_STEAMDECK_LAUNCH_DEST}"

    if [[ ! -f "${script}" ]]; then
        htpc_log_error "htpc-steamdeck-launch not found at ${script}."
        return 1
    fi
    if [[ -f "${dest}" ]] && cmp -s "${script}" "${dest}"; then
        htpc_log_info "htpc-steamdeck-launch already installed and up to date."
        return 0
    fi
    install -m 0755 "${script}" "${dest}"
    htpc_log_info "Installed htpc-steamdeck-launch to ${dest}."
}

htpc_steamdeck_launch_uninstall() {
    if [[ -f "${HTPC_STEAMDECK_LAUNCH_DEST}" ]]; then
        rm -f "${HTPC_STEAMDECK_LAUNCH_DEST}"
        htpc_log_info "Removed ${HTPC_STEAMDECK_LAUNCH_DEST}."
    fi
}
