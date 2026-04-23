# AirLab Fast Setup on PSC Bridges-2

Lab-specific workflow on top of the base Bridges-2 guide. Focused on Singularity-based development, the ROBO (H100) partition, Rerun visualization, and the `<allocation-id>` project conventions.

## Account

1. Create ACCESS account at `identity.access-ci.org`
2. Ask allocation managers (Basti, Wenshan, Yaoyu, Bowen, Nikhil) to add you
3. Enable DUO 2FA
4. Register PSC account when you get the email

## Login and Node Pinning

```bash
ssh <psc_user>@bridges2.psc.edu
hostname                                # see which login node you're on
ssh br012.ib.bridges2.psc.edu           # jump to a specific login node
```

tmux sessions and running containers are **per-login-node**. Note which one you're on before detaching.

## Singularity — Preferred Workflow

### Cache directories (set before pulling/building)

```bash
export APPTAINER_CACHEDIR="/ocean/projects/<project>/<user>/data/singularity"
export APPTAINER_TMPDIR="/ocean/projects/<project>/<user>/data/singularity/tmp"
# older variable names also used:
export SINGULARITY_CACHEDIR="$APPTAINER_CACHEDIR"
export SINGULARITY_TMPDIR="$APPTAINER_TMPDIR"
```

### Pull from Docker Hub

```bash
cd /ocean/projects/<project>/<user>/data/singularity
singularity pull <image>.sif docker://<dockerhub_path>
```

### AirLab private registry

```bash
singularity build --docker-login <image>.sif \
  docker://airlab-storage.andrew.cmu.edu:5001/<path>:<tag>
```

### ROBO (H100) needs CUDA 11.8+

```bash
singularity build noeticcuda12.sif docker://amigoshan/noeticcuda12:latest
```

### Pre-built NGC images

```
/ocean/containers/ngc
```

### Remote build via Sylabs

Create account at `cloud.sylabs.io`, generate an access token, then:

```bash
interact -t 4:00:00 -n 4
singularity remote login
singularity build --remote <image>.sif <def_file>.def
```

Definition file example:

```
BootStrap: docker
From: nvcr.io/nvidia/jax:23.08-py3

%post
apt-get update
apt-get install -y ffmpeg
```

## Virtual Environment Inside a Container

```bash
interact -p GPU-shared -t 00:30:00 -n 5 --gres=gpu:v100-32:1
cd /ocean/containers/ngc/pytorch
singularity instance start --nv pytorch_22.12-py3.sif venv
singularity run --nv instance://venv

# inside the container:
pip install --user virtualenv
cd <venv_dir>
virtualenv <venv_name> --system-site-packages
source <venv_name>/bin/activate
pip install <packages>
```

Conda inside a container — add to your entry script:

```bash
source /opt/conda/etc/profile.d/conda.sh
conda activate <env>
```

## Example Files (shared)

```
/ocean/projects/<allocation-id>/shared/examples/train.sbatch
/ocean/projects/<allocation-id>/shared/examples/train.job
/ocean/projects/<allocation-id>/shared/examples/train.sh
```

## ROBO (H100) Partition

Contact `help@psc.edu` for access.

**Interactive:**
```bash
srun --partition=ROBO --mem=64G -t 1:00:00 --mincpus=8 \
  --gres=gpu:h100:1 --job-name=<name> --pty /bin/bash
```

**Batch:**
```bash
sbatch -p ROBO --comment="<ORACLE_STRING>" -n 10 --gres=h100:1 \
  -t 48:00:00 <job>.job -o /path/to/<out>.out
```

Use ROBO only for polished code — it's expensive.

## Interactive GPU Workflow with tmux

Typical loop:

1. SSH to login node
2. `tmux new -s work`
3. `interact -p GPU-shared -t 4:00:00 -n 2 --gres=gpu:v100-32:1`
4. `singularity instance start --nv <image>.sif <name>`
5. `singularity run --nv instance://<name>`
6. Run experiments
7. Detach: `Ctrl+b` then `d`
8. Later, SSH back to **the same login node**, then `tmux attach -t work`

Rule of thumb: `-n` ≈ 2× GPU count.

## Batch Job — Singularity Template

```bash
#!/bin/bash
set -x
source /etc/profile.d/modules.sh

SIF=/path/to/<image>.sif
S_EXEC="singularity exec -B /ocean:/ocean --nv ${SIF}"

SCRIPT=/path/to/script.sh
${S_EXEC} bash ${SCRIPT}
```

Submit:
```bash
sbatch -p GPU-shared -n 10 --gpus=v100-16:4 -t 48:00:00 \
  <job>.job -o /path/to/<out>.out
```

Full `#SBATCH`-embedded variant:

```bash
#!/bin/bash
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -p ROBO
#SBATCH --gpus=h100:1
#SBATCH -t 2-00:00
#SBATCH --job-name test
#SBATCH -o job_%j.out
#SBATCH -e job_%j.err
#SBATCH --mail-type=END
#SBATCH --mail-user=<you>@andrew.cmu.edu

set -x
WORKING_DIR=$PROJECT/SLURM/test_robo
cd $WORKING_DIR
singularity exec --nv xxx.sif /bin/bash $WORKING_DIR/xxx.sh
```

## Job Arrays

**sbatch:**
```bash
#!/bin/bash
#SBATCH -p GPU-shared
#SBATCH -t 1:00:00
#SBATCH -n 5
#SBATCH -J extract_frames
#SBATCH --gpus=v100-16:1
#SBATCH --output=/ocean/projects/<allocation-id>/<user>/sbatch/outputs/extract_frames/%A_%a.out
#SBATCH --array=1-12

bash /ocean/projects/<allocation-id>/<user>/jobs/extract_frames.job ${SLURM_ARRAY_TASK_ID}
```

**.job:**
```bash
#!/bin/bash
A_ID=$1
set -x
source /etc/profile.d/modules.sh
SIF=/ocean/projects/<allocation-id>/<user>/data/singularity/nvidia_frames_base.sif
S_EXEC="singularity exec -B /ocean:/ocean --nv ${SIF}"
${S_EXEC} bash /ocean/projects/<allocation-id>/<user>/scripts/extract_frames.sh ${A_ID}
```

**.sh:**
```bash
#!/bin/bash
A_ID=$1
cd /ocean/projects/<allocation-id>/<user>/daa/nvidia_to_frames
python3 run.py configs/nea_heli/config_${A_ID}.yaml
```

## Monitoring

- Dashboard: `https://ondemand.bridges2.psc.edu/pun/sys/dashboard`
- `squeue -u $USER`, `sacct`
- Prefer Weights & Biases over TensorBoard
- `sacct -S 2023-01-01 --format="jobid,jobname%-12,partition,Start,ElapsedRaw,AllocTRES%-70"`

## Rerun (3D/4D Visualization) via Port Forwarding

Install both locally and on cluster:
```bash
pip install rerun-sdk       # or: conda install -c conda-forge rerun-sdk
```

**~/.ssh/config (local):**
```
Host bridges2.psc.edu
    HostName bridges2.psc.edu
    User <user>
    LocalForward localhost:<rr-port> localhost:<rr-port>
    LocalForward localhost:<ws-server-port> localhost:<ws-server-port>
    LocalForward localhost:<rr-viewer-port> localhost:<rr-viewer-port>
```

On cluster: allocate, then forward the node:
```bash
salloc -p RM-small -t 06:00:00 -n 5
sleep 365d
# from login node:
ssh -L <rr>:localhost:<rr> -L <ws>:localhost:<ws> -L <viewer>:localhost:<viewer> \
    <node>.ib.bridges2.psc.edu
```

Serve:
```bash
singularity instance start --nv example.sif example
singularity run --nv instance://example
source <venv>/bin/activate
tmux new -s debug
rerun --serve --port <rr> --ws-server-port <ws> --web-viewer-port <viewer>
```

Client (local):
```bash
rerun ws://localhost:<ws>
# or browser:
# http://localhost:<viewer>?url=ws://localhost:<ws>
```

Log to it:
```bash
python3 demo.py --addr "0.0.0.0:<rr>"
```

## Project Conventions

- Shared project: `<allocation-id>`
- Repo template: `https://github.com/castacks/Cloud-Computing-Repository-Template`
- New allocation/partition onboarding: see the AirLab ACCESS DISCOVER proposal doc
