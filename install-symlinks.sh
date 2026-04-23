#!/usr/bin/env bash
# install-symlinks.sh
# Symlink each skill from this repo's skills/ into the parent skills directory
# (e.g. ~/.claude/skills/ or ~/.agents/skills/).
#
# Usage:
#   ./install-symlinks.sh                 # default: parent of this repo
#   ./install-symlinks.sh ~/.claude/skills

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_root="$repo_root/skills"

if [[ ! -d "$source_root" ]]; then
    echo "skills/ not found inside repo: $source_root" >&2
    exit 1
fi

target="${1:-$(dirname "$repo_root")}"
target="$(cd "$target" && pwd)"

echo "Source: $source_root"
echo "Target: $target"
echo

for src in "$source_root"/*/; do
    name="$(basename "$src")"
    link="$target/$name"

    if [[ -L "$link" ]]; then
        echo "skip (already linked): $name"
        continue
    fi
    if [[ -e "$link" ]]; then
        echo "WARN: exists and is NOT a symlink, skipping: $link" >&2
        continue
    fi

    ln -s "$src" "$link"
    echo "linked: $name  ->  $src"
done
