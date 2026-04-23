---
name: psc-bridges2
description: Use when working on PSC Bridges-2 — SSH/login to bridges2.psc.edu, SLURM job submission (sbatch, srun, interact), partitions (RM, RM-shared, RM-512, EM, GPU, GPU-shared, ROBO H100), GPU types (h100-80, l40s-48, v100-32, v100-16), allocations/SU accounting, Ocean/jet filesystems, $LOCAL/$RAMDISK, modules, Singularity/Apptainer containers (including Docker→SIF conversion via bundled scripts/singularity_pull_docker_local.sh + scripts/start_sif.sh), Rerun port-forwarding, AirLab (<allocation-id>) workflows, or data transfers via data.bridges2.psc.edu.
type: reference
---

# PSC Bridges-2 User Guide

Reference for running work on the Pittsburgh Supercomputing Center's Bridges-2 system. See `partitions.md`, `job-scripts.md`, `filesystems.md`, `airlab-fast-setup.md` (AirLab-specific workflow: Singularity, ROBO/H100, Rerun, `<allocation-id>`), and `docker-to-singularity.md` (running Docker images on PSC via the bundled `scripts/singularity_pull_docker_local.sh` + `scripts/start_sif.sh`).

## Connecting

- SSH: `ssh username@bridges2.psc.edu` (port 22, HPN-SSH supported)
- Web: OnDemand portal for Jupyter, RStudio, file management
- Set/reset PSC password at `apr.psc.edu` (8+ chars, 3 of 4 char groups, annual change)
- **Data transfers must use `data.bridges2.psc.edu` DTNs, not login nodes**

## Allocations and Accounting

- `projects` — list allocations, balances, IDs, Ocean usage
- `my_quotas` — check $HOME and $PROJECT quotas
- Specify allocation in SLURM: `-A <allocation-id>`
- `newgrp <group>` — temporary Unix group switch
- `change_primary_group <account-id>` — permanent default switch

**Service Unit (SU) charging:**
- RM / RM-shared / RM-512 / EM: 1 core-hour = 1 SU
- GPU V100 / L40S: 1 GPU-hour = 1 SU (8 SUs/node-hour)
- GPU H100: 1 GPU-hour = 2 SUs (16 SUs/node-hour)
- RM (full) always charges all 128 cores regardless of use

## Filesystems

| Variable | Path | Quota | Backup | Notes |
|----------|------|-------|--------|-------|
| `$HOME` | `/jet/home/<user>` | 25 GB | Daily | Scripts, source |
| `$PROJECT` | `/ocean/projects/<group>/<PSC-user>` | Per-allocation | **None** | Ocean; 6,070 inodes/GB |
| `$LOCAL` | Node-local scratch | Node-dependent | — | Fast I/O, wiped at job end |
| `$RAMDISK` | RAM-backed | Depends on memory req | — | Lost on abnormal exit |

Exceeding $PROJECT quota blocks job submission.

## Modules

- `module avail` — list available
- `module load <name>` / `module unload <name>` / `module list`
- `module spider <name>` — search
- Typing `bioinformatics` lists bio software

## Partitions (quick view)

| Partition | Node type | Cores/Node | Max nodes | Max time | Notes |
|-----------|-----------|-----------|-----------|----------|-------|
| RM | 256GB RM | 128 | 64 | 72h | Full-node; charges all 128 cores |
| RM-shared | 256GB RM | 1–64 | 1 | 72h | 2 GB/core |
| RM-512 | 512GB RM | 128 | 2 | 72h | Large memory |
| EM | 4TB EM | 96 | 1 | 120h | Request 24/48/72/96 cores; no interactive |
| GPU | h100-80/l40s-48/v100-32/v100-16 | 8 or 16 GPUs | 4 | 48h | Full-node |
| GPU-shared | same GPU types | ≤4 GPUs | 1 | 48h | Partial node |

See `partitions.md` for full specs.

## Interactive Jobs

```bash
interact                                       # RM-shared default: 1 core, 60 min
interact -p RM-shared --ntasks-per-node=32 -t 5:00:00
interact -p GPU-shared --gres=gpu:v100-32:1 -t 2:00:00
```

Options: `-p`, `-t`, `-N`, `--ntasks-per-node`, `--gres=gpu:<type>:<n>`, `-A`.

## Batch Jobs

```bash
sbatch -p RM -t 5:00:00 -N 1 script.job
squeue -u $USER
scancel <jobid>
```

Output: `slurm-<jobid>.out`. States: PD (pending), R (running), CA (cancelled), F (failed).

Interactive uses `--gres=gpu:<type>:<n>`; batch uses `--gpus=<type>:<n>` (multiple of 8 on GPU full-node).

See `job-scripts.md` for ready-to-adapt templates (RM, RM-shared, EM, GPU, GPU-shared, MPI, OpenMP).

## Compilers and MPI

| Compiler | Module | C / C++ / Fortran | OpenMP flag |
|----------|--------|------------------|-------------|
| Intel Classic | `intel` | icc / icpc / ifort | `-qopenmp` |
| Intel LLVM | `intel-oneapi` | icx / icpx / ifx | `-fopenmp` |
| GNU | `gcc` | gcc / g++ / gfortran | `-fopenmp` |
| AMD | `aocc` | clang / clang++ / flang | `-fopenmp` |
| NVIDIA | `nvhpc` | nvcc / nvc++ / nvfortran | `-mp` |

MPI implementations: MVAPICH2, OpenMPI, Intel MPI. Load compiler module + MPI module, then use `mpicc` / `mpicxx` / `mpifort`.

## Data Transfer (from your local machine)

```bash
# rsync (recommended: faster MAC)
rsync -rltDvp -oMACS=umac-64@openssh.com source/ user@data.bridges2.psc.edu:/ocean/projects/<group>/<PSC-user>/dest/

# scp
scp file user@data.bridges2.psc.edu:/ocean/projects/<group>/<PSC-user>/

# sftp
sftp user@data.bridges2.psc.edu
```

**Globus:** endpoint `PSC Bridges-2 /ocean and /jet filesystems`. Best for large/resumable transfers.

## Software

- Anaconda-based AI/ML/Big Data environments curated by PSC
- Singularity/Apptainer containers supported; `singularity exec --nv -B /ocean:/ocean <img.sif> <cmd>`
- Pre-built NGC images at `/ocean/containers/ngc`
- Set `APPTAINER_CACHEDIR` / `APPTAINER_TMPDIR` under `$PROJECT` before pulling/building
- **Docker → Singularity bridge:** the skill ships two helper scripts at `scripts/singularity_pull_docker_local.sh` (pull a Docker image on an allocated node using `$LOCAL` scratch, then save the `.sif` to the working dir) and `scripts/start_sif.sh` (fuzzy-match a `.sif` by keyword and start/exec it with `--nv` + `/local` bind). Full usage in `docker-to-singularity.md`. For a bare Docker-on-PSC workflow, copy those two scripts to the cluster — nothing else is required.
- Install requests: `help@psc.edu`

For lab-standard container workflows, tmux-pinning to a login node, job arrays, and Rerun visualization, see `airlab-fast-setup.md`.

## Common Mistakes

- Running transfers from login nodes — **use `data.bridges2.psc.edu`**.
- Submitting tiny jobs to `RM` — you pay for all 128 cores. Use `RM-shared`.
- EM with non-multiple-of-24 core counts — will reject.
- GPU batch with `--gres=gpu:...` — batch uses `--gpus=<type>:<n>`.
- Forgetting `-A <allocation>` when multiple allocations exist.
- Storing important files in `$LOCAL`/`$RAMDISK` — wiped at job end.
- Filling $PROJECT — blocks further submissions until under quota.

## Support

- Email: `help@psc.edu`
- Phone: 412-268-4960

## Useful Links

**Official PSC Bridges-2**
- User Guide: https://www.psc.edu/resources/bridges-2/user-guide/
- Getting Started with HPC: https://www.psc.edu/resources/bridges-2/getting-started-with-hpc/
- Introduction to Unix: https://www.psc.edu/resources/introduction-to-unix/
- Glossary: https://www.psc.edu/resources/glossary/
- Password utility (APR): https://apr.psc.edu
- OnDemand portal: https://ondemand.bridges2.psc.edu/pun/sys/dashboard
- Login host: `bridges2.psc.edu`
- Data transfer host: `data.bridges2.psc.edu`

**Access / allocations**
- ACCESS-CI identity: https://identity.access-ci.org
- ACCESS allocations: https://allocations.access-ci.org

**Tooling**
- SLURM docs: https://slurm.schedmd.com/documentation.html
- Apptainer (Singularity) docs: https://apptainer.org/docs/user/latest/
- Sylabs Cloud (remote builds): https://cloud.sylabs.io
- NVIDIA NGC catalog: https://catalog.ngc.nvidia.com
- Globus: https://www.globus.org — endpoint name "PSC Bridges-2 /ocean and /jet filesystems"
- Weights & Biases: https://wandb.ai
- Rerun docs: https://www.rerun.io/docs/getting-started/data-in/python

**AirLab**
- Cloud repo template: https://github.com/castacks/Cloud-Computing-Repository-Template
- Private container registry: `airlab-storage.andrew.cmu.edu:5001`
- Fast Setup doc (source): https://airlab.slite.page/p/-1w-EGD7QgqnQO/Fast-Setup-on-PSC
