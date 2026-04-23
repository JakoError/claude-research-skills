# Bridges-2 Partitions — Detailed Reference

## Node Hardware

| Node type | Count | Cores | RAM | GPUs |
|-----------|-------|-------|-----|------|
| RM (256GB) | many | 128 | 256 GB | — |
| RM-512 | some | 128 | 512 GB | — |
| EM | some | 96 | 4 TB | — |
| GPU h100-80 | 10 | — | 2 TB | 8× H100 (80 GB) |
| GPU l40s-48 | 3 | — | 1 TB | 8× L40S (48 GB) |
| GPU v100-32 | 24 + 1 DGX-2 | — | 512 GB | 8× V100 (32 GB); DGX-2 has 16× |
| GPU v100-16 | 9 | — | 192 GB | 8× V100 (16 GB) |

## Partition Details

### RM
- Full 256GB node(s), 128 cores each
- Range: 1–64 nodes
- Walltime: default 1 h, max 72 h
- **Charges all 128 cores** whether used or not
- Use when: you actually consume a full node

### RM-shared
- Partial 256GB node, 1–64 cores
- Single node only
- 2 GB memory per core
- Walltime: default 1 h, max 72 h
- Use when: serial or few-core jobs

### RM-512
- 512GB node(s), 128 cores each
- Range: 1–2 nodes
- Walltime: 1–72 h
- Use when: memory between 256 GB and 4 TB needed

### EM
- 4TB node, 96 cores
- **One node only**
- Must request cores in multiples of 24 (24 / 48 / 72 / 96)
- ~1 TB RAM per 24 cores requested
- Walltime: 1–120 h
- **No interactive sessions, no OnDemand**

### GPU (full node)
- 1–4 nodes
- Walltime: 1–48 h
- Batch request: `--gpus=<type>:<n>` with n a multiple of 8
- Interactive request: `--gres=gpu:<type>:<n>` with n = 8 or 16
- Charges all cores + GPUs on the assigned node(s)

### GPU-shared
- Up to 4 GPUs on a single node
- Walltime: 1–48 h
- Batch: `--gpus=<type>:<n>`
- Interactive: `--gres=gpu:<type>:<n>`

## GPU Type Strings

Use these exact type names in `--gpus=` / `--gres=gpu:`:

- `h100-80`
- `l40s-48`
- `v100-32`
- `v100-16`

## SU Charging Summary

| Resource | Rate |
|----------|------|
| RM core-hour | 1 SU |
| RM full node-hour | 128 SU |
| RM-shared 2 cores × 0.5h | 1 SU |
| EM core-hour | 1 SU |
| EM full node-hour | 96 SU |
| V100 / L40S GPU-hour | 1 SU |
| V100 / L40S full node-hour | 8 SU |
| H100 GPU-hour | 2 SU |
| H100 full node-hour | 16 SU |
