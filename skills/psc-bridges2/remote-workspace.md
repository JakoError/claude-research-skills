# Remote Workspace on PSC — Pinning the Sync Target

**Rule:** every project that syncs to PSC MUST have a `.psc-config` file declaring exactly one `PSC_WORKSPACE` absolute path. The bundled sync scripts refuse to run without it, and refuse to run against paths that are too broad to be safe (HOME roots, allocation roots, another user's tree). The agent never chooses a remote destination at call time — the pin is the contract.

This prevents the failure mode where the agent guesses a plausible-looking remote path and rsyncs into `/jet/home/<user>/` or `/ocean/projects/<grp>/`, clobbering unrelated work.

## Setup (once per project)

1. Copy the template into your project root:
   ```bash
   cp /path/to/skill/scripts/psc-config.template ./.psc-config
   ```
2. Edit `.psc-config` — at minimum set `PSC_USER` and `PSC_WORKSPACE`. Example:
   ```
   PSC_USER=<psc-user>
   PSC_WORKSPACE=/jet/home/<psc-user>/project/projects/<project-slug>
   PSC_SSH_KEY=~/.ssh/<psc-key>
   PSC_ALLOCATION=<allocation-id>
   ```
3. Add `.psc-config` to your `.gitignore` (it often contains a host-specific key path, and pinning the workspace in the repo would conflict across collaborators).
4. Create the remote workspace if it doesn't exist yet:
   ```bash
   ssh ${PSC_USER}@bridges2.psc.edu "mkdir -p ${PSC_WORKSPACE}"
   ```

## Safety rules the loader enforces

`_psc_common.sh` validates every run:

| Check | Rejected examples |
|---|---|
| `PSC_WORKSPACE` must be absolute | `~/foo`, `project/foo`, empty |
| Must live under `/jet/home/<PSC_USER>/` or `/ocean/projects/<grp>/<PSC_USER>/` | `/tmp/x`, `/jet/home/someoneelse/...` |
| Must be at least one level DEEPER than the user's root | `/jet/home/<psc-user>`, `/ocean/projects/<grp>/<psc-user>` |
| `/ocean/projects/<grp>/<user>` path must include `<user>` as the 2nd component and a 3rd-level subdir | `/ocean/projects/<allocation-id>/shared/foo` — wrong user slot |
| `LOCAL_WORKSPACE` must not be `/` or `$HOME` | `~`, `/` |

If a check fails, the script exits with a one-line explanation and does nothing.

## Default exclude list (baked into `_psc_common.sh`)

Standard excludes — always applied on both directions:

```
.git __pycache__ .idea .vscode .cursor *cache*
node_modules .venv venv .env .env.* *.sif
checkpoints data logs results
.psc-config sync*.bash sync*.sh
```

Rationale: these are either local-only (editor state, caches), massive (data/checkpoints/SIFs — sync via `singularity_pull_docker_local.sh` or explicit scp), or sensitive (`.env*`, `.psc-config` itself). Override per-project with `EXTRA_EXCLUDES=(...)` in `.psc-config`.

**Note:** `data/`, `checkpoints/`, `logs/`, `results/` are excluded because they usually live on `$PROJECT` / `$LOCAL` and should not round-trip. If your project wants to sync (say) small result summaries, write them to a dedicated `reports/` dir which is NOT excluded.

## Usage

From anywhere inside the project (scripts walk up to find `.psc-config`):

```bash
# dry run first, always, for a new project
./scripts/sync_local_to_psc.sh -n

# push (interactive confirm)
./scripts/sync_local_to_psc.sh

# push, skip confirm (for agent automation; still runs safety checks)
./scripts/sync_local_to_psc.sh -y

# pull results back
./scripts/sync_psc_to_local.sh -y

# mirror local deletions to remote (DANGEROUS — gated by an explicit flag)
./scripts/sync_local_to_psc.sh --delete
```

`PSC_YES=1` as an env var is equivalent to `-y` and is the recommended way for an autonomous agent to run these non-interactively — it still cannot override the path safety checks.

## Why a config file (and not CLI args)

An explicit `REMOTE_DEST=...` argument at call time would let the agent *construct* a remote path on the fly, which is exactly the failure mode we want to prevent. Putting the path in a file that is:

- Created once by a human during project setup,
- Validated on every run,
- Immutable relative to the task the agent is doing,

means the agent's syncing capability is capability-scoped to a single pinned location. The agent can still `scp` or `rsync` outside this — but the *skill-provided* path is safe by construction, and doc/protocol can tell the agent to use only these scripts.

## Integrating with the autonomous research loop

If you're using `research-sandbox`, add a Phase 2 question for the PSC workspace, drop `.psc-config` into the scaffold, and add a rule in the project's `CLAUDE.md`:

> When syncing to PSC, ONLY use `./scripts/sync_local_to_psc.sh` and `./scripts/sync_psc_to_local.sh`. Never construct a remote path by hand. Never pass a remote path as an argument. If the script refuses to run, fix `.psc-config` — do not work around the check.

That keeps the autonomy without opening the foot-gun.
