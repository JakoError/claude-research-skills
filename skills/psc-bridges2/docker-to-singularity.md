# Docker → Singularity on PSC Bridges-2

PSC runs Singularity/Apptainer, not Docker. Two bundled helper scripts convert and run Docker images as Singularity containers on PSC. They live next to this doc at:

```
scripts/singularity_pull_docker_local.sh
scripts/start_sif.sh
```

If the user has a Docker image they want to run on PSC, you generally only need these two scripts — `pull` once to build the `.sif`, then `start_sif.sh` to run it on any subsequent allocation.

## When to use

- User has a Docker image (Docker Hub, NGC, private registry) and wants to run it on PSC.
- User asks about "running Docker on PSC", "converting Docker to Singularity", or mirrors a local Docker workflow to the cluster.
- Extending the `research-sandbox` local Docker setup to a PSC run.

Copy the scripts into the user's project (or `$PROJECT/scripts/`) — do NOT run them from the skill directory, since the skill lives on the host machine, not on PSC. Typical flow: `scp` the two files up, or paste them into `$PROJECT/scripts/` on Bridges-2.

## 1. `singularity_pull_docker_local.sh` — pull on a compute node to `$LOCAL`

**Why it exists:** Login nodes are not for heavy builds, and `$HOME` / `$PROJECT` are slow for Singularity's build/extract phase. This script stages the build in `$LOCAL` (fast node-local scratch), then copies the final `.sif` to the current working directory.

**Requirement:** must run inside an allocation where `$LOCAL` is set (i.e., from an `interact` or `sbatch` session on RM / RM-shared / GPU-shared). The script refuses to run if `$LOCAL` is empty.

**Usage:**
```bash
# allocate a node first
interact -p RM-shared --ntasks-per-node=4 -t 1:00:00
cd $PROJECT/<user>/data/singularity

# then pull
./singularity_pull_docker_local.sh nvcr.io/nvidia/pytorch:24.01-py3
./singularity_pull_docker_local.sh amigoshan/noeticcuda12:latest
```

Behavior:
- Sets `APPTAINER_CACHEDIR` / `APPTAINER_TMPDIR` / `APPTAINER_BUILDDIR` under `$LOCAL/singularity/`.
- Proposes a SIF filename derived from the image path (prompts for confirm / override).
- If a prior local build exists, asks whether to overwrite or reuse.
- Runs `singularity -d pull "$local_sif_path" docker://<image>`.
- Copies the finished `.sif` from `$LOCAL` into the current directory (persistent, e.g. `$PROJECT/.../data/singularity/`).

Everything in `$LOCAL` is wiped at job end — the final `cp` is what preserves the image.

## 2. `start_sif.sh` — locate a `.sif` by keywords and launch it

**Why it exists:** Projects accumulate many `.sif` files. This script fuzzy-matches a filename from a directory of SIFs, starts a `singularity instance`, and either opens an interactive shell or execs a command inside.

**SIF directory resolution:**
1. Explicit 2nd arg if given.
2. Otherwise `$PROJECT/data/singularity`.
3. Fails if neither resolves to an existing directory.

**Usage:**
```bash
# interactive shell inside matched container
./start_sif.sh "cuda 12.4 ubuntu22"

# custom sif directory
./start_sif.sh "noetic cuda12" /ocean/projects/<proj>/<user>/data/singularity

# unique instance name (multiple parallel containers)
./start_sif.sh "cuda 12.4" -n

# auto-confirm (no interactive prompt)
./start_sif.sh "vila-awq" -y

# run a command inside and exit
./start_sif.sh "vila-awq" -y -- PYTHONPATH=./ python3 train.py
./start_sif.sh "vila-awq" -n -y -- cd proj && PYTHONPATH=./ python3 bar.py
```

Flags:
- `-n` — append a short UUID suffix to the instance name (safe for parallel starts of the same image).
- `-y` — skip the confirm prompt.
- `-- <command...>` — everything after `--` is passed to `bash -lc` inside the container. Without it, you get an interactive shell.

Query matching: the query is lowercased and split on `/`, `:`, `_`, `-`, whitespace. Every token must appear as a substring in the `.sif` filename. Multiple matches → numbered picker.

Runtime: uses `--nv` (GPU) and `--bind /local:/mnt/local` so `$LOCAL` is visible at `/mnt/local` inside the container. If you need `/ocean` inside too, extend the binds in the script or wrap it.

## Combined workflow (typical)

```bash
# one-time: pull the image on a compute node
ssh <user>@bridges2.psc.edu
interact -p RM-shared --ntasks-per-node=4 -t 1:00:00
cd $PROJECT/<user>/data/singularity
./singularity_pull_docker_local.sh nvcr.io/nvidia/pytorch:24.01-py3
exit

# later: run it on a GPU allocation
interact -p GPU-shared -t 2:00:00 --gres=gpu:v100-32:1
./start_sif.sh "pytorch 24.01" -y -- python3 train.py
```

## Notes / gotchas

- Both scripts assume bash and standard GNU coreutils (fine on Bridges-2 login and compute nodes).
- `start_sif.sh` stops any existing instance with the same name before starting — use `-n` if you need them coexisting.
- Neither script sets `APPTAINER_CACHEDIR` persistently for later sessions; add the exports to `~/.bashrc` if you pull often outside this script.
- For the AirLab private registry (requires docker-login), prefer `singularity build --docker-login` directly — the pull script is for public / anonymous images.
