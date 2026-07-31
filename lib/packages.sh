#!/usr/bin/env bash
# Helpers for installing packages via pacman. Requires lib/log.sh.

htpc_package_installed() {
    local package="$1"
    pacman -Qi -- "${package}" >/dev/null 2>&1
}

# Prints, one per line and with no other output, which of the given
# packages are not currently installed. Used by the installer to record
# only the packages it actually adds (as opposed to ones already present),
# so the uninstaller only offers to remove what it installed.
htpc_packages_missing() {
    local package
    for package in "$@"; do
        if ! htpc_package_installed "${package}"; then
            printf '%s\n' "${package}"
        fi
    done
}

htpc_packages_install() {
    local packages=("$@")
    local missing=()
    local package

    for package in "${packages[@]}"; do
        if ! htpc_package_installed "${package}"; then
            missing+=("${package}")
        fi
    done

    if [[ "${#missing[@]}" -eq 0 ]]; then
        htpc_log_info "All required packages already installed: ${packages[*]}"
        return 0
    fi

    htpc_log_info "Installing packages: ${missing[*]}"
    pacman -S --needed --noconfirm -- "${missing[@]}"
}
