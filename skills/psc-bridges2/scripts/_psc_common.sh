#!/usr/bin/env bash
#
# Author: Zhexian Zhou <zhexianz@andrew.cmu.edu>
#
# Shared loader + safety checks for the PSC remote-workspace scripts.
# Sourced by sync_local_to_psc.sh / sync_psc_to_local.sh / submit_psc.sh.
# Refuses to proceed if .psc-config is missing or workspace paths are unsafe.
#
set -euo pipefail

# Resolve config: explicit PSC_CONFIG, else nearest .psc-config walking up
# from the caller's directory. Fail if none found.
_find_config() {
    if [[ -n "${PSC_CONFIG:-}" ]]; then
        [[ -f "$PSC_CONFIG" ]] || { echo "ERROR: PSC_CONFIG=$PSC_CONFIG does not exist." >&2; exit 1; }
        printf '%s\n' "$PSC_CONFIG"
        return
    fi
    local d="$PWD"
    while [[ "$d" != "/" && "$d" != "" ]]; do
        if [[ -f "$d/.psc-config" ]]; then printf '%s\n' "$d/.psc-config"; return; fi
        d="$(dirname "$d")"
    done
    echo "ERROR: no .psc-config found. Copy scripts/psc-config.template to .psc-config in your project root and fill it in." >&2
    exit 1
}

PSC_CONFIG_PATH="$(_find_config)"
PSC_CONFIG_DIR="$(cd "$(dirname "$PSC_CONFIG_PATH")" && pwd)"

# shellcheck disable=SC1090
source "$PSC_CONFIG_PATH"

: "${PSC_USER:?PSC_USER not set in $PSC_CONFIG_PATH}"
: "${PSC_WORKSPACE:?PSC_WORKSPACE not set in $PSC_CONFIG_PATH}"
PSC_LOGIN_HOST="${PSC_LOGIN_HOST:-bridges2.psc.edu}"
PSC_DATA_HOST="${PSC_DATA_HOST:-data.bridges2.psc.edu}"
PSC_SSH_KEY="${PSC_SSH_KEY:-}"
LOCAL_WORKSPACE="${LOCAL_WORKSPACE:-$PSC_CONFIG_DIR}"

# --- Safety: PSC_WORKSPACE must be absolute, inside a known root, and deep enough ---

_fail_unsafe_remote() {
    echo "ERROR: PSC_WORKSPACE='$PSC_WORKSPACE' is unsafe." >&2
    echo "       Must be absolute and at least one of:" >&2
    echo "         /jet/home/$PSC_USER/<subdir>/...      (>= 2 levels under /jet/home/$PSC_USER)" >&2
    echo "         /ocean/projects/<grp>/$PSC_USER/<subdir>/..." >&2
    echo "       Rejected: \$HOME roots, allocation roots, other users' dirs, shared roots." >&2
    exit 1
}

case "$PSC_WORKSPACE" in
    /*) : ;;
    *) _fail_unsafe_remote ;;
esac

# Normalize trailing slash off for checks
_ws="${PSC_WORKSPACE%/}"

# Reject dangerous exact matches
for bad in "/" "/jet" "/jet/home" "/jet/home/$PSC_USER" \
           "/ocean" "/ocean/projects" ; do
    [[ "$_ws" == "$bad" ]] && _fail_unsafe_remote
done

# Must live inside one of these roots, AND be deeper than the root itself
_in_root=0
if [[ "$_ws" == "/jet/home/$PSC_USER/"* ]]; then
    # need at least one extra path component beyond /jet/home/<user>/
    rest="${_ws#/jet/home/$PSC_USER/}"
    [[ -n "$rest" && "$rest" != "." && "$rest" != ".." ]] && _in_root=1
elif [[ "$_ws" == "/ocean/projects/"* ]]; then
    rest="${_ws#/ocean/projects/}"
    # must be <grp>/<user>/<subdir>... — i.e. at least 3 path components
    IFS='/' read -r -a parts <<< "$rest"
    if (( ${#parts[@]} >= 3 )) && [[ "${parts[1]}" == "$PSC_USER" ]]; then
        _in_root=1
    else
        echo "ERROR: for /ocean/projects, workspace must be /ocean/projects/<grp>/$PSC_USER/<subdir>/..." >&2
        exit 1
    fi
fi
(( _in_root )) || _fail_unsafe_remote

# --- Safety: LOCAL_WORKSPACE must be a real dir, not $HOME or / ---

[[ -d "$LOCAL_WORKSPACE" ]] || { echo "ERROR: LOCAL_WORKSPACE='$LOCAL_WORKSPACE' is not a directory." >&2; exit 1; }
_lw="$(cd "$LOCAL_WORKSPACE" && pwd)"
case "$_lw" in
    "/"|"$HOME"|"${HOME%/}") echo "ERROR: LOCAL_WORKSPACE must not be / or \$HOME ($_lw)." >&2; exit 1 ;;
esac
LOCAL_WORKSPACE="$_lw"

# --- ssh / rsync assembly ---

if [[ -n "$PSC_SSH_KEY" ]]; then
    SSH_CMD=(ssh -i "${PSC_SSH_KEY/#\~/$HOME}")
else
    SSH_CMD=(ssh)
fi

_STD_EXCLUDES=(
    '.git' '__pycache__' '.idea' '.vscode' '.cursor' '*cache*'
    'node_modules' '.venv' 'venv' '.env' '.env.*' '*.sif'
    'checkpoints' 'data' 'logs' 'results'
    '.psc-config' 'sync*.bash' 'sync*.sh'
)

build_rsync_excludes() {
    local -a out=()
    for p in "${_STD_EXCLUDES[@]}"; do out+=(--exclude="$p"); done
    if declare -p EXTRA_EXCLUDES >/dev/null 2>&1; then
        for p in "${EXTRA_EXCLUDES[@]:-}"; do [[ -n "$p" ]] && out+=(--exclude="$p"); done
    fi
    printf '%s\n' "${out[@]}"
}

print_summary() {
    echo "PSC config:    $PSC_CONFIG_PATH"
    echo "Local dir:     $LOCAL_WORKSPACE"
    echo "Remote:        ${PSC_USER}@${PSC_DATA_HOST}:${PSC_WORKSPACE}"
    [[ -n "$PSC_SSH_KEY" ]] && echo "SSH key:       $PSC_SSH_KEY"
}

confirm_or_abort() {
    if [[ "${PSC_YES:-0}" == "1" || "${1:-}" == "-y" ]]; then return 0; fi
    read -r -p "Proceed? (y/n): " ans
    [[ "$ans" == "y" || "$ans" == "Y" ]] || { echo "Aborted."; exit 0; }
}
