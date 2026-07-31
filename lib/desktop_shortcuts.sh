#!/usr/bin/env bash
# Installs the KDE Desktop shortcuts that call htpc-switch, so KDE Desktop
# has a way back to Kodi/Steam the same way Kodi's own add-ons and Steam's
# "Switch to Desktop" button do. See "Desktop Application Shortcuts" in
# session-services-spec.md. Requires lib/log.sh.
#
# Installed in two places:
#   - ~/.local/share/applications/: shows up in Plasma's application
#     launcher (Kickoff/KRunner). Desktop entries here don't need to be
#     marked executable; they're registered launchers, not files a user
#     double-clicks directly.
#   - The user's actual Desktop folder (resolved via xdg-user-dir, falling
#     back to ~/Desktop): real desktop icons. These *are* files a user
#     double-clicks directly, so KDE requires the executable bit to be set
#     for Plasma to treat them as trusted and launch them without an
#     interstitial "this file has not been marked as trusted" prompt.

HTPC_DESKTOP_SHORTCUTS=(htpc-kodi.desktop htpc-steam.desktop)

htpc_desktop_shortcuts_source_dir() {
    cd "$(dirname "${BASH_SOURCE[0]}")/../desktop-shortcuts" && pwd
}

# Resolves the target user's actual Desktop directory, honoring a custom
# xdg-user-dirs configuration (e.g. a renamed or relocated Desktop folder)
# when present.
htpc_desktop_shortcuts_desktop_dir() {
    local target_user="$1" home="$2" dir
    dir="$(runuser -u "${target_user}" -- xdg-user-dir DESKTOP 2>/dev/null)"
    if [[ -n "${dir}" && "${dir}" != "${home}" ]]; then
        printf '%s\n' "${dir}"
    else
        printf '%s\n' "${home}/Desktop"
    fi
}

# Installs the shortcuts into the target user's application launcher and
# onto their Desktop. Always re-copies (project-managed files), then fixes
# ownership and permissions. Idempotent.
htpc_desktop_shortcuts_install() {
    local target_user="$1"
    local home apps_dir desktop_dir source_dir name

    home="$(getent passwd "${target_user}" | cut -d: -f6)"
    if [[ -z "${home}" ]]; then
        htpc_log_error "Could not determine home directory for user ${target_user}."
        return 1
    fi

    apps_dir="${home}/.local/share/applications"
    desktop_dir="$(htpc_desktop_shortcuts_desktop_dir "${target_user}" "${home}")"
    source_dir="$(htpc_desktop_shortcuts_source_dir)"

    install -d -o "${target_user}" -g "${target_user}" -m 0755 \
        "${home}/.local" "${home}/.local/share" "${apps_dir}" "${desktop_dir}"

    for name in "${HTPC_DESKTOP_SHORTCUTS[@]}"; do
        if [[ ! -f "${source_dir}/${name}" ]]; then
            htpc_log_error "No desktop shortcut source found at ${source_dir}/${name}."
            return 1
        fi
        install -o "${target_user}" -g "${target_user}" -m 0644 \
            "${source_dir}/${name}" "${apps_dir}/${name}"
        install -o "${target_user}" -g "${target_user}" -m 0755 \
            "${source_dir}/${name}" "${desktop_dir}/${name}"
    done

    htpc_log_info "Installed desktop shortcuts (launcher + Desktop icons) for ${target_user}."
}
