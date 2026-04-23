#!/usr/bin/env bash
#
# Author: Zhexian Zhou <zhexianz@andrew.cmu.edu>
#
# Push LOCAL_WORKSPACE → PSC_WORKSPACE over rsync. Workspace paths come from
# .psc-config and are validated by _psc_common.sh — refuses to run against
# $HOME, allocation roots, or anything not under the configured user's area.
#
# Usage:
#   ./sync_local_to_psc.sh [-y] [-n] [--delete] [-- <extra rsync args>]
#     -y         skip confirmation (or set PSC_YES=1)
#     -n         dry-run (rsync -n)
#     --delete   mirror deletes to remote (dangerous; off by default)
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
echo "Direction:     LOCAL → PSC (push)"
(( DRY )) && echo "Mode:          DRY RUN"
(( DELETE )) && echo "Delete:        YES (remote will mirror local deletions)"
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
    "${LOCAL_WORKSPACE}/" \
    "${PSC_USER}@${PSC_DATA_HOST}:${PSC_WORKSPACE}/"
