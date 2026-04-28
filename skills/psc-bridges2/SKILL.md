---
name: psc-bridges2
description: Use when working on PSC Bridges-2 — SSH/login to bridges2.psc.edu, SLURM job submission (sbatch, srun, interact), partitions (RM, RM-shared, RM-512, EM, GPU, GPU-shared, ROBO H100), GPU types (h100-80, l40s-48, v100-32, v100-16), allocations/SU accounting, parallel-allocation racing to cut queue wait (submit to multiple allocations/partitions, cancel losers on first start), Ocean/jet filesystems, $LOCAL/$RAMDISK, modules, Singularity/Apptainer containers (Docker→SIF via bundled scripts/singularity_pull_docker_local.sh + scripts/start_sif.sh), pinned-workspace rsync bridge via scripts/sync_local_to_psc.sh + scripts/sync_psc_to_local.sh (driven by .psc-config, safety-checked), Rerun port-forwarding, AirLab (<allocation-id>) workflows, or data transfers via data.bridges2.psc.edu.
type: reference
---

# PSC Bridges-2 User Guide

Reference for running work on the Pittsburgh Supercomputing Center's Bridges-2 system. See `partitions.md`, `job-scripts.md`, `filesystems.md`, `airlab-fast-setup.md` (AirLab-specific workflow: Singularity, ROBO/H100, Rerun, `<allocation-id>`), `docker-to-singularity.md` (running Docker images on PSC via the bundled `scripts/singularity_pull_docker_local.sh` + `scripts/start_sif.sh`), and `remote-workspace.md` (pinned rsync bridge: `.psc-config` + `scripts/sync_local_to_psc.sh` / `scripts/sync_psc_to_local.sh`, with mandatory workspace safety checks).

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
- ROBO allocation balance shown by `projects` is always negative (e.g. `-168,249 / 0 SU`) — this is normal and the allocation remains usable

## Filesystems

| Variable | Path | Quota | Backup | Notes |
|----------|------|-------|--------|-------|
| `$HOME` | `/jet/home/<user>` | 25 GB | Daily | Scripts, source |
| `$PROJECT` | `/ocean/projects/<group>/<PSC-user>` | Per-allocation | **None** | Ocean; 6,070 inodes/GB |
| `$LOCAL` | Node-local scratch | Node-dependent | — | Fast I/O, wiped at job end |
| `$RAMDISK` | RAM-backed | Depends on memory req | — | Lost on abnormal exit |

Exceeding $PROJECT quota blocks job submission.

## Path Discipline (REQUIRED)

**Ask the user to indicate the workspace** — an absolute Ocean path under `/ocean/projects/<group>/<PSC-user>/...` — before doing anything on PSC. Do not guess. If `.psc-config` exists locally, read `PSC_WORKSPACE` and confirm with the user.

Allowed paths:

- **Login nodes:** the pinned Ocean workspace only. Avoid `~` / `$HOME` whenever possible (only for things that belong there, e.g. SSH keys, dotfiles, module config).
- **Compute nodes (`interact` / `sbatch`):** the pinned Ocean workspace and `$LOCAL`. Nothing else.
- **`/tmp` is never allowed**, on any node. If a tool defaults there, redirect it (`TMPDIR`, `APPTAINER_TMPDIR`, cache flags).

If the workspace has not been specified yet, **stop and ask** — don't `cd`, `mkdir`, download, `singularity pull`, or `sbatch` first.

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

**Important constraints when using `interact`:**
- **Max wall time is 8 hours** (`-t 8:00:00`), regardless of the partition's batch limit (RM/RM-shared 72h and GPU/GPU-shared 48h apply only to `sbatch`). Default is 60 min, and idle sessions are auto-logged-out after 30 min — always pass `-t` explicitly.
- EM partition does **not** allow interactive sessions — use `sbatch` for EM.
- **Effectively one active `interact` session per user** (observed: a second `interact` while one is already running will queue behind it; not explicitly documented in the PSC user guide). Before launching, check `squeue -u $USER` for an existing interactive job and reuse it (re-attach via the original terminal / tmux) instead of spawning another.
- Even for longer jobs, `interact` (up to 8h) is often the right tool — but if the work needs >8h or must survive disconnects, use `sbatch`.
- Wrap `interact` in `tmux`/`screen` on the login node so SSH drops don't kill the session.

## Batch Jobs

```bash
sbatch -p RM -t 5:00:00 -N 1 script.job
squeue -u $USER
scancel <jobid>
```

Output: `slurm-<jobid>.out`. States: PD (pending), R (running), CA (cancelled), F (failed).

Interactive uses `--gres=gpu:<type>:<n>`; batch uses `--gpus=<type>:<n>` (multiple of 8 on GPU full-node).

See `job-scripts.md` for ready-to-adapt templates (RM, RM-shared, EM, GPU, GPU-shared, MPI, OpenMP).

## Parallel Allocation / Partition Racing (reduce queue wait)

Queues on Bridges-2 vary dramatically by allocation and partition. A single `-A <alloc>` submission can sit in PD for hours while another allocation/partition would start in minutes. When wait time matters, **submit the same job to multiple allocations or compatible partitions in parallel and cancel the losers once one starts.**

When to use:
- You have access to 2+ allocations (check with `projects`), or the job can run on multiple partitions (e.g. GPU-shared vs ROBO for H100 work).
- A first submission has been PD for noticeably longer than the job's own runtime, or longer than ~15–30 min.
- The job is idempotent from a clean start (no side effects from duplicate starts before cancel).

How to do it:
1. Submit the same script to each viable (allocation, partition) pair. Tag each with a recognizable `--job-name` so you can find them:
   ```bash
   sbatch -A <alloc-A> -p GPU-shared --gres=gpu:h100-80:1 -J race_h100_A job.sh
   sbatch -A <alloc-B> -p GPU-shared --gres=gpu:h100-80:1 -J race_h100_B job.sh
   sbatch -A <alloc-B> -p ROBO     --gres=h100:1          -J race_h100_R job.sh
   ```
2. Poll: `squeue -u $USER -n race_h100_A,race_h100_B,race_h100_R`.
3. As soon as **one** enters state `R`, cancel the rest:
   ```bash
   RUNNING=$(squeue -u $USER -n race_h100_A,race_h100_B,race_h100_R -h -t R -o %i | head -1)
   squeue -u $USER -n race_h100_A,race_h100_B,race_h100_R -h -t PD -o %i | xargs -r scancel
   ```
4. Record which (allocation, partition) won so later jobs can start there directly.

Rules / cautions:
- **Cancel PD duplicates the instant one starts running** — otherwise multiple copies will run and burn SUs on every allocation.
- **Be patient — do NOT cancel siblings just because waiting feels long.** The cancel trigger is "another sibling entered state `R`," not "I've been waiting a few minutes." Racing only works if every sibling stays alive until exactly one starts; killing PD jobs early to "settle" on one defeats the purpose, since the one you kept may itself be the slowest. If no sibling has started yet, keep waiting.
- **Prefer `interact` for small / short / exploratory tasks.** A single `interact -p RM-shared ...` or `interact -p GPU-shared --gres=gpu:<type>:<n> ...` session is usually better than batch racing for debug work, quick checks, or anything under ~15–30 min — lower overhead, no duplicate-job SU risk, and the user can drive it directly. Reach for racing only when the job is long enough that queue wait actually dominates.
- Only race allocations that are actually valid for the work; don't submit to an EM allocation for a GPU job.
- Every job consumes SUs — be thoughtful and make sure the code and submission script are checked and good to run before launching.
- Don't race more than ~3–4 copies; beyond that the SU-loss risk from a missed cancel outweighs the queue savings.
- For very short jobs (< 15 min) skip racing; overhead of submit+cancel isn't worth it — use `interact` instead.

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

**Pinned-workspace rsync (recommended for project code):** use the bundled `scripts/sync_local_to_psc.sh` / `scripts/sync_psc_to_local.sh`. Both read `.psc-config` in the project root, which fixes the remote path ONCE (`PSC_WORKSPACE=...`); the loader rejects unsafe destinations ($HOME roots, allocation roots, other users' trees). Agents must NEVER construct a remote path by hand — use these scripts, never pass a remote arg, and fix `.psc-config` if a check fails. Full rules and exclude list in `remote-workspace.md`.

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
