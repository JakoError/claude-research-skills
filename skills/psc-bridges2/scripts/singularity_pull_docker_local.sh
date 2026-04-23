#!/usr/bin/env bash
#
# Author: Zhexian Zhou <zhexianz@andrew.cmu.edu>
#
# Pull a Docker image and convert it to a Singularity/Apptainer .sif, using
# $LOCAL (node-local fast scratch) for the cache/tmp/build dirs, then copy the
# finished .sif into the current working directory. Must be run inside a PSC
# allocation where $LOCAL is set (interact / sbatch / srun).
#
set -e

# Check arguments
if [[ -z "$1" ]]; then
    echo "Usage: $0 <docker-image>"
    echo "Example: $0 nvcr.io/nvidia/pytorch:24.01-py3"
    exit 1
fi

# Ensure LOCAL is set
if [[ -z "$LOCAL" ]]; then
    echo "ERROR: The environment variable \$LOCAL is not set."
    echo "Please set it to a local scratch directory."
    exit 1
fi

# Create directories
export APPTAINER_CACHEDIR="$LOCAL/singularity/cache"
export APPTAINER_TMPDIR="$LOCAL/singularity/tmp"
export APPTAINER_BUILDDIR="$LOCAL/singularity/build"

mkdir -p "$APPTAINER_CACHEDIR" "$APPTAINER_TMPDIR" "$APPTAINER_BUILDDIR"

echo "Cache Directory: $APPTAINER_CACHEDIR"
echo "Temp Directory:  $APPTAINER_TMPDIR"
echo "Build Directory: $APPTAINER_BUILDDIR"

# Generate SIF filename
image_name="${1#*/}"
singularity_file_name="${image_name}.sif"

# Ask user to confirm filename
read -p "Confirm SIF file name: $singularity_file_name correct? (y/n): " confirm
if [[ "$confirm" != "y" ]]; then
    read -p "Enter new file name (with or without .sif): " new_file_name
    [[ "$new_file_name" != *.sif ]] && new_file_name="${new_file_name}.sif"
    singularity_file_name="$new_file_name"
fi

# Build path in LOCAL (fast disk)
local_sif_path="$APPTAINER_BUILDDIR/$singularity_file_name"
final_sif_path="$(pwd)/$singularity_file_name"

# If already exists in local build, ask to overwrite
if [[ -f "$local_sif_path" ]]; then
    echo "Local build file '$local_sif_path' already exists."
    read -p "Overwrite it? (y/n): " overwrite
    if [[ "$overwrite" != "y" ]]; then
        echo "Skipping pull — using existing local build."
    else
        rm -f "$local_sif_path"
    fi
fi

# Pull
if [[ ! -f "$local_sif_path" ]]; then
    echo "Building SIF in LOCAL directory:"
    echo "Running: singularity pull $local_sif_path docker://$1"
    singularity -d pull "$local_sif_path" "docker://$1"
fi

# Copy to working directory
echo "Copying SIF to current directory..."
cp "$local_sif_path" "$final_sif_path"
echo "Created: $final_sif_path"

echo "Done."
