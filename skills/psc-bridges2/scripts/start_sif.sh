#!/usr/bin/env bash
#
# Author: Zhexian Zhou <zhexianz@andrew.cmu.edu>
#
# Locate a .sif in a directory by fuzzy keyword match, start a Singularity
# instance with --nv and /local:/mnt/local bind, then either exec a command
# inside or open an interactive shell.
#
set -euo pipefail

# Usage:
#   start_sif.sh <query> [sif-directory] [-n] [-y] [-- <command...>]
#
# Examples:
#   start_sif.sh "cuda 12.4 ubuntu22"
#   start_sif.sh "cuda 12.4 ubuntu22" -n
#   start_sif.sh "cuda 12.4 ubuntu22" -y
#   start_sif.sh "cuda 12.4 ubuntu22" -n -y
#   start_sif.sh "vila-awq" -y -- PYTHONPATH=./ python3 foo.py
#   start_sif.sh "vila-awq" -n -y -- PYTHONPATH=./ python3 foo.py
#   start_sif.sh "vila-awq" -y -- cd proj && PYTHONPATH=./ python3 bar.py
#
# - <query>        : keywords to match .sif filename
# - [sif-directory] : optional directory, default: $PROJECT/data/singularity
# - -n             : make instance name unique by appending a UUID suffix
# - -y             : auto-confirm
# - -- <command>   : any shell command you want to run INSIDE the container
#                    it will be executed as: bash -lc "<command>"

AUTO_Y=0
UNIQUE_NAME=0
QUERY_RAW=""
SIF_DIR=""
CMD_STR=""

# --- Parse args: <query> [sif-dir] [-n] [-y] [-- <command...>] ---

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n)
            UNIQUE_NAME=1
            shift
            ;;
        -y)
            AUTO_Y=1
            shift
            ;;
        --)
            shift
            # Everything after -- becomes one command string for bash -lc
            CMD_STR="$*"
            break
            ;;
        *)
            if [[ -z "$QUERY_RAW" ]]; then
                QUERY_RAW="$1"
            elif [[ -z "$SIF_DIR" ]]; then
                SIF_DIR="$1"
            else
                echo "Unexpected argument: $1"
                echo "Usage: $0 <query> [sif-directory] [-n] [-y] [-- <command...>]"
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$QUERY_RAW" ]]; then
    echo "Usage: $0 <query> [sif-directory] [-n] [-y] [-- <command...>]"
    echo "Example: $0 \"vila-awq\" -n -y -- PYTHONPATH=./ python3 script.py"
    exit 1
fi

SIF_DIR="${SIF_DIR:-${PROJECT:-}/data/singularity}"

if [[ -z "$SIF_DIR" ]]; then
    echo "ERROR: SIF directory is not set."
    echo "Either pass it explicitly: $0 \"<query>\" /path/to/sifs"
    echo "or set PROJECT so that \$PROJECT/data/singularity exists."
    exit 1
fi

if [[ ! -d "$SIF_DIR" ]]; then
    echo "ERROR: SIF directory does not exist:"
    echo "  $SIF_DIR"
    exit 1
fi

echo "SIF directory: $SIF_DIR"
echo "Query:         $QUERY_RAW"
echo

# --- Build tokens from query (advanced matching) ---

query="${QUERY_RAW,,}"
query="${query//\// }"
query="${query//:/ }"
query="${query//_/ }"
query="${query//-/ }"

tokens=()
for t in $query; do
    [[ -n "$t" ]] && tokens+=("$t")
done

if [[ ${#tokens[@]} -eq 0 ]]; then
    echo "ERROR: No valid tokens extracted from query."
    exit 1
fi

echo "Tokens:"
for t in "${tokens[@]}"; do
    echo "  - $t"
done
echo

# --- Gather all .sif files in directory ---

mapfile -t all_sifs < <(find "$SIF_DIR" -maxdepth 1 -type f -name '*.sif' | sort)

if [[ ${#all_sifs[@]} -eq 0 ]]; then
    echo "ERROR: No .sif files found in directory:"
    echo "  $SIF_DIR"
    exit 1
fi

# --- Filter by "all tokens must be substrings" rule ---

matches=()

for f in "${all_sifs[@]}"; do
    lname="$(basename "$f" | tr '[:upper:]' '[:lower:]')"

    ok=1
    for tok in "${tokens[@]}"; do
        if [[ "$lname" != *"$tok"* ]]; then
            ok=0
            break
        fi
    done

    (( ok )) && matches+=("$f")
done

if [[ ${#matches[@]} -eq 0 ]]; then
    echo "ERROR: No .sif files matched all tokens in:"
    echo "  $SIF_DIR"
    exit 1
elif [[ ${#matches[@]} -gt 1 ]]; then
    echo "Multiple matches found:"
    i=1
    for f in "${matches[@]}"; do
        echo "  [$i] $(basename "$f")"
        ((i++))
    done
    echo
    read -p "Select a file by number: " choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || ((choice < 1 || choice > ${#matches[@]})); then
        echo "Invalid selection."
        exit 1
    fi
    SIF_PATH="${matches[choice-1]}"
else
    SIF_PATH="${matches[0]}"
fi

IMAGE_NAME="$(basename "$SIF_PATH" .sif)"
INSTANCE_NAME=$(echo "$IMAGE_NAME" | tr '/: ' '_' )

# --- Unique instance name (-n) ---
if [[ $UNIQUE_NAME -eq 1 ]]; then
    # Prefer uuidgen, then /proc, then python fallback.
    uuid="$(
        uuidgen 2>/dev/null \
        || cat /proc/sys/kernel/random/uuid 2>/dev/null \
        || python3 - <<'PY'
import uuid
print(uuid.uuid4())
PY
    )"
    uuid="${uuid,,}"
    uuid="${uuid//-/}"
    uuid_short="${uuid:0:8}"
    INSTANCE_NAME="${INSTANCE_NAME}_${uuid_short}"
fi

echo
echo "SELECTED SIF:   $SIF_PATH"
echo "IMAGE NAME:     $IMAGE_NAME"
echo "INSTANCE NAME:  $INSTANCE_NAME"
echo

# --- Confirmation ---

if [[ $AUTO_Y -eq 0 ]]; then
    read -p "Proceed with starting container instance? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        echo "Operation cancelled."
        exit 0
    fi
else
    echo "Auto-confirm enabled (-y). Proceeding..."
fi

echo "Stopping any existing instance with same name..."
singularity instance stop "$INSTANCE_NAME" 2>/dev/null || true

echo "Starting instance $INSTANCE_NAME"
singularity instance start --bind /local:/mnt/local --nv "$SIF_PATH" "$INSTANCE_NAME"

# --- Exec or shell inside container ---

if [[ -n "$CMD_STR" ]]; then
    echo "Executing inside container (bash -lc):"
    echo "  $CMD_STR"
    exec singularity exec --bind /local:/mnt/local --nv instance://"$INSTANCE_NAME" bash -lc "$CMD_STR"
else
    echo "No command provided after '--', starting interactive shell inside container..."
    # exec singularity shell --nv instance://"$INSTANCE_NAME"
    singularity exec --bind /local:/mnt/local --nv instance://"$INSTANCE_NAME" /bin/bash
fi
