#!/usr/bin/env bash
set -euo pipefail

# Syncs the local working tree (including uncommitted changes) to the
# CachyOS test machine over SSH, via rsync. The remote copy is disposable:
# it exists only for testing and is never a source of truth. If the test
# machine gets rolled back to a snapshot, just re-run this script.
#
# Setup:
#   cp dev/.env.example dev/.env
#   edit dev/.env with your test machine's SSH details
#
# Usage:
#   dev/sync.sh

script_dir() {
    cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

load_env() {
    local env_file="$1"
    if [[ -f "${env_file}" ]]; then
        # shellcheck source=/dev/null
        source "${env_file}"
    fi
}

require_host() {
    : "${HTPC_DEV_HOST:?Set HTPC_DEV_HOST in dev/.env or the environment, e.g. user@catchyos.local}"
}

main() {
    local script_directory repo_root
    script_directory="$(script_dir)"
    repo_root="$(cd "${script_directory}/.." && pwd)"

    load_env "${script_directory}/.env"
    require_host

    local dev_path="${HTPC_DEV_PATH:-catchy-htpc-dev}"

    rsync -avz --delete \
        --exclude='.git' \
        --exclude='dev/.env' \
        --exclude='.ruff_cache' \
        --exclude='__pycache__' \
        "${repo_root}/" "${HTPC_DEV_HOST}:${dev_path}/"

    echo "Synced to ${HTPC_DEV_HOST}:${dev_path}"
}

main "$@"
