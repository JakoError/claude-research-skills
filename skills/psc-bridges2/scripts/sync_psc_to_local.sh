#!/usr/bin/env bash
#
# Author: Zhexian Zhou <zhexianz@andrew.cmu.edu>
#
# Pull PSC_WORKSPACE → LOCAL_WORKSPACE over rsync. Workspace paths come from
# .psc-config and are validated by _psc_common.sh. Default direction never
# deletes local files; pass --delete to mirror remote deletions locally.
#
# Usage:
#   ./sync_psc_to_local.sh [-y] [-n] [--delete] [-- <extra rsync args>]
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_psc_common.sh
source "$SCRIPT_DIR/_psc_common.sh"

DRY=0; DELETE=0; YES=0; EXTRA=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -y) YES=1; shift ;;
        -n) DRY=1; shift ;;
        --delete) DELETE=1; shift ;;
        --) shift; EXTRA=("$@"); break ;;
        *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
done

print_summary
echo "Direction:     PSC → LOCAL (pull)"
(( DRY )) && echo "Mode:          DRY RUN"
(( DELETE )) && echo "Delete:        YES (local will mirror remote deletions)"
(( YES )) && PSC_YES=1
confirm_or_abort

mapfile -t EXCLUDES < <(build_rsync_excludes)

RSYNC_ARGS=(-rltvz --modify-window=1 --no-perms)
(( DRY )) && RSYNC_ARGS+=(-n)
(( DELETE )) && RSYNC_ARGS+=(--delete)

rsync "${RSYNC_ARGS[@]}" \
    -e "${SSH_CMD[*]}" \
    "${EXCLUDES[@]}" \
    "${EXTRA[@]}" \
    "${PSC_USER}@${PSC_DATA_HOST}:${PSC_WORKSPACE}/" \
    "${LOCAL_WORKSPACE}/"
