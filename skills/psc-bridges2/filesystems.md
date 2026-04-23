# Bridges-2 Filesystems Reference

## Summary

| Variable | Path | Quota | Backed up | Visible | Lifetime |
|----------|------|-------|-----------|---------|----------|
| `$HOME` | `/jet/home/<user>` | 25 GB | Yes (daily) | All nodes | Permanent |
| `$PROJECT` | `/ocean/projects/<group>/<PSC-user>` | Per allocation | **No** | All nodes | Allocation lifetime |
| `$LOCAL` | node-local | Node-dependent | No | One node | Job duration |
| `$RAMDISK` | RAM | Memory-dependent | No | One node | Job duration |

## $HOME (Jet)

- 25 GB hard cap
- Daily backups; recovery 3–4 days via `help@psc.edu`
- Use for scripts, source, configs, small inputs
- **Not** for job output, datasets, checkpoints

## $PROJECT (Ocean)

- One directory per allocation
- Quota set at allocation approval
- **No backups** — your responsibility
- Inode quota: 6,070 inodes per GB allocated — avoid millions of tiny files
- Over-quota **blocks new job submission**
- If you have multiple allocations, verify you are writing into the correct one (`projects` command)

## $LOCAL (Node scratch)

- Local SSD/disk on the assigned node
- Very fast I/O, no SU cost
- Visible only from that node (single-node jobs or node-local staging)
- Wiped when job ends — copy anything you need back to `$PROJECT` before exit
- Ideal for: random-access datasets, intermediate files, DB-like workloads

## $RAMDISK

- In-memory, shares the job's allocated RAM
- Fastest possible I/O
- Size ≈ requested memory (minus app usage)
- Lost on abnormal termination
- Use for: hot temp files, small intermediate artifacts

## Quota Commands

```bash
my_quotas        # $HOME and $PROJECT usage
projects         # allocation balances + Ocean usage
du -sh $PROJECT  # directory size
lfs quota -u $USER /ocean   # if lustre quota available
```

## Transfer Reminders

All transfers must come from outside Bridges-2. Connect to `data.bridges2.psc.edu`, not `bridges2.psc.edu`. Login nodes cannot initiate outbound transfers.

For very large transfers, prefer Globus over rsync/scp — it resumes, retries, and parallelizes automatically.
