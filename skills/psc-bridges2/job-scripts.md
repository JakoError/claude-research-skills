# Bridges-2 Job Script Templates

Adapt these templates. Replace `<group>`, `<PSC-user>`, `<allocation-id>` as needed.

## RM — full node, 128 cores

```bash
#!/bin/bash
#SBATCH -N 1
#SBATCH -p RM
#SBATCH -t 5:00:00
#SBATCH --ntasks-per-node=128
#SBATCH -A <allocation-id>

set -x
cd /ocean/projects/<group>/<PSC-user>/workdir
./a.out
```

Submit: `sbatch script.job`

## RM-shared — partial node

```bash
#!/bin/bash
#SBATCH -N 1
#SBATCH -p RM-shared
#SBATCH -t 5:00:00
#SBATCH --ntasks-per-node=32

cd /ocean/projects/<group>/<PSC-user>/workdir
./a.out
```

Or one-liner: `sbatch -p RM-shared -t 5:00:00 --ntasks-per-node=32 script.job`

## RM-512 — large memory

```bash
#!/bin/bash
#SBATCH -N 1
#SBATCH -p RM-512
#SBATCH -t 5:00:00
#SBATCH --ntasks-per-node=128
```

## EM — 4TB node

```bash
#!/bin/bash
#SBATCH -N 1
#SBATCH -p EM
#SBATCH -t 5:00:00
#SBATCH --ntasks-per-node=48       # must be multiple of 24
```

## GPU — full node, 2 × v100-32 nodes

```bash
#!/bin/bash
#SBATCH -N 2
#SBATCH -p GPU
#SBATCH --gpus=v100-32:16
#SBATCH -t 5:00:00
```

## GPU-shared — 4 GPUs on one node

```bash
#!/bin/bash
#SBATCH -N 1
#SBATCH -p GPU-shared
#SBATCH --gpus=v100-32:4
#SBATCH -t 2:00:00
```

## GPU — H100 single GPU

```bash
#!/bin/bash
#SBATCH -N 1
#SBATCH -p GPU-shared
#SBATCH --gpus=h100-80:1
#SBATCH -t 4:00:00

module load anaconda3
source activate mytorch
python train.py
```

## MPI (OpenMPI on RM)

```bash
#!/bin/bash
#SBATCH -N 4
#SBATCH -p RM
#SBATCH --ntasks-per-node=128
#SBATCH -t 2:00:00

module load gcc openmpi
mpirun ./my_mpi_app
```

## OpenMP (RM-shared)

```bash
#!/bin/bash
#SBATCH -N 1
#SBATCH -p RM-shared
#SBATCH --ntasks-per-node=16
#SBATCH -t 1:00:00

export OMP_NUM_THREADS=16
./my_openmp_app
```

## Singularity container on GPU

```bash
#!/bin/bash
#SBATCH -N 1
#SBATCH -p GPU-shared
#SBATCH --gpus=v100-32:1
#SBATCH -t 2:00:00

module load singularity
singularity exec --nv my_image.sif python infer.py
```

## Using $LOCAL for fast scratch

```bash
#!/bin/bash
#SBATCH -p RM
#SBATCH -N 1
#SBATCH --ntasks-per-node=128
#SBATCH -t 3:00:00

cp $PROJECT/input.dat $LOCAL/
cd $LOCAL
./a.out < input.dat > output.dat
cp output.dat $PROJECT/results/
# $LOCAL is wiped at job end — copy results out first
```

## Common SLURM options

| Flag | Meaning |
|------|---------|
| `-J <name>` | Job name |
| `-o <file>` | Stdout path (default `slurm-%j.out`) |
| `-e <file>` | Stderr path |
| `--mail-type=END,FAIL` | Email notifications |
| `--mail-user=<addr>` | Email address |
| `-A <alloc-id>` | Charge allocation |
| `-d afterok:<jobid>` | Dependency |
