---
name: docker-split-service
description: Use when creating or modifying a Dockerized service - guides the deps+app two-stage Dockerfile pattern, docker-compose structure, entrypoint conventions, and env-driven configuration
---

# Docker Split Service Pattern

## Overview

Build Docker services using a **two-stage split**: a heavy `Dockerfile.deps` for dependencies and a thin `Dockerfile.app` for application code. App-only changes rebuild in seconds, not minutes.

Every Dockerized service MUST follow the conventions below — no deviations on naming, layout, or version handling. Consistency across services is the whole point. If an existing service in the codebase looks different, fix it to match before adding more on top.

> **Framework note:** examples below use **PyTorch** as the concrete framework, since most services in this codebase are PyTorch-based. The pattern applies identically to other frameworks (TensorFlow, JAX, …) — substitute the relevant `<vendor>/<image>` and version axes.
>
> **Placeholder note:** `<project>` = the service/repo identifier (e.g. the folder name), `<repo>` = the image registry namespace, `<host-port>` = the service-specific host port chosen per R9. All snippets use `/<project>` for the in-container app home — substitute consistently; do not leave literal `<project>` tokens in committed files.

## When to Use

- Creating a new Docker-based service (API server, worker, etc.)
- Adding a new service variant to an existing project
- Refactoring a monolithic Dockerfile into faster-iterating layers
- Bringing an existing nonstandard service in line with the rules below

## Before You Write Anything — Elicit & Verify Versions

Do NOT pick `PYTORCH_VER` / `CUDA_VER` / `CUDNN_VER` (or their equivalents) from your head. Guessing silently produces images that won't run on the user's hardware, and the failure only shows up after a long build.

1. **Ask the user for versions up front.** Single question:
   > "Which PyTorch / CUDA / cuDNN versions should this service target? If you don't have specific pins, tell me the **target GPU** and the **host CUDA driver version** (`nvidia-smi` top-right `CUDA Version:`) and I'll pick a compatible stack."

2. **If the user gives versions, verify the triple before writing a file:**
   - The `pytorch/pytorch:${PYTORCH_VER}-cuda${CUDA_VER}-cudnn${CUDNN_VER}-devel` tag actually exists on Docker Hub (check, don't assume).
   - The host's CUDA driver supports the chosen runtime CUDA (driver max ≥ image CUDA).
   - The target GPU's compute capability is covered by that PyTorch build; set `TORCH_CUDA_ARCH_LIST` (with `+PTX` fallback) when building custom CUDA extensions.
   - PyTorch and cuDNN majors match (consult official release notes, not memory).

3. **If the user gave only a GPU, derive the stack from it**, then confirm with the user before writing files. Consult the current PyTorch and NVIDIA compatibility docs — do not rely on internalized tables. Special-hardware images (Jetson / L4T, ROCm, etc.) require the R8 fallback path.

4. **If any check fails, stop and propose the nearest working triple.** Do not silently downgrade or swap versions — surface the conflict and let the user confirm.

5. **Record the decision in `docker/serve/README.md`** under a "Version pins" heading (target GPU, host driver constraint, chosen triple) so the next agent doesn't re-derive it.

Only after these steps succeed do you start writing Dockerfiles per the rules below.

## Hard Rules (do not deviate)

### R1. Standard file layout — exactly these files, exactly these locations

```
<repo-root>/
  docker/
    serve/
      Dockerfile.deps          # Heavy deps layer
      Dockerfile.app           # Thin app layer
      docker-compose.yaml      # Local compose (context resolves to repo root)
      entrypoint.sh
      app.py                   # Application code (e.g. FastAPI)
      README.md
  docker-compose.server.yml    # Root-level compose — REQUIRED
  .dockerignore                # REQUIRED at repo root
  .env.example                 # REQUIRED — documents every env var the compose reads
```

- The root `docker-compose.server.yml` is **required** — it is the primary entry point. Do NOT skip it and put compose only in `docker/serve/`.
- The local `docker/serve/docker-compose.yaml` is also required, for symmetry and convenience when working inside that directory. Both files build identical images and use `context` resolving to the **repo root**.
- Never invent alternative names like `docker-compose.yml` at root, `serve.yml`, `compose.server.yaml`, etc.
- Never nest compose files inside subprojects without a corresponding root-level compose.

**Monorepo layout.** If the repo contains multiple independent services (each with its own framework/deps), treat each subproject as its own `<repo-root>` — i.e. each subproject directory gets its own `docker/serve/`, its own root-level `docker-compose.server.yml` (at the *subproject* root, not the monorepo root), its own `.dockerignore`, and its own `.env.example`. Do not hoist a single compose file to the monorepo root to "cover" them all; do not bury the only compose file inside `docker/serve/` of a subproject.

**Required companion files (content contract):**

`.dockerignore` (repo root) — minimum content:
```
.git
.gitignore
.venv
__pycache__
*.pyc
.pytest_cache
.mypy_cache
.ruff_cache
.ipynb_checkpoints
node_modules
.env
.env.*
!.env.example
# DO NOT ignore checkpoints/configs/data if Dockerfile.deps COPYs them
```
If `Dockerfile.deps` copies `./checkpoints` or `./data`, those paths must NOT be ignored — verify after writing.

`.env.example` (repo root) — lists every variable the compose files read, with the same defaults, as documentation:
```dotenv
# Image / build
SERVER_IMAGE=<repo>/<project>
SERVER_DEPS_DOCKERFILE=docker/serve/Dockerfile.deps
SERVER_APP_DOCKERFILE=docker/serve/Dockerfile.app

# Versions (see R2)
PYTORCH_VER=2.7.1
CUDA_VER=12.8
CUDNN_VER=9

# Runtime
SERVER_PORT=<host-port>        # per R9
SERVER_CONTAINER_PORT=8080
SERVER_GPUS=all
DEVICE=cuda:0
```
Agents never commit a `.env` — only `.env.example`.

`app.py` contract — the FastAPI (or equivalent) application must expose at least:
- `GET /health` → `200 {"status": "ok"}`. Used by smoke tests and orchestrators.
- A single domain endpoint (e.g. `POST /predict`) documented in `README.md`.

`README.md` (under `docker/serve/`) must document, at minimum:
- one-line purpose of the service,
- the `SERVER_PORT` default and what it maps to,
- every non-standard env var consumed by `app.py` (model paths, device, etc.),
- the exact `docker compose` commands to build and run (copy from the Build Workflow section, adjusted for this project).

### R2. Decompose every version — no monolithic version strings

Each version component is its own `ARG`. Compose the base image tag from those parts inside the `FROM` line.

**WRONG** — bumping any axis forces a string edit and breaks tag derivation:
```dockerfile
ARG BASE_TAG="2.7.1-cuda12.8-cudnn9-devel"
FROM pytorch/pytorch:${BASE_TAG}
```

**RIGHT** — each axis pinned independently (PyTorch shown as the typical case):
```dockerfile
ARG PYTORCH_VER="2.7.1"
ARG CUDA_VER="12.8"
ARG CUDNN_VER="9"
FROM pytorch/pytorch:${PYTORCH_VER}-cuda${CUDA_VER}-cudnn${CUDNN_VER}-devel
```

This applies to every dependency: framework version, CUDA, cuDNN, library pins, Python pin if non-default, etc. Each gets its own `ARG <NAME>_VER="<x.y.z>"` with a default. Override via compose `args:` from env vars.

For non-PyTorch projects, swap `PYTORCH_VER` for the equivalent (`TF_VER`, `JAX_VER`, …) and the base image (`tensorflow/tensorflow:...`, etc.). The structure is identical.

Never hardcode pip index URLs that bake in a CUDA version either — derive from the CUDA arg or pass `INDEX_URL` as its own `ARG`.

### R3. Image tag is derived from version args — never a hardcoded string

**WRONG**:
```yaml
image: ${SERVER_IMAGE:-<repo>/<project>}:${IMAGE_TAG:-pytorch2.7-cuda12.8}-base
```
(The version part is a fixed string — bumping `PYTORCH_VER` doesn't change the tag, so two different builds collide on the same image.)

**RIGHT**:
```yaml
image: ${SERVER_IMAGE:-<repo>/<project>}:pytorch${PYTORCH_VER}-cuda${CUDA_VER}-cudnn${CUDNN_VER}-base
```

The tag MUST include every version axis that affects the image. Bumping any version automatically produces a new tag — no collisions, no need to remember to bump `IMAGE_TAG` separately.

### R4. Standard env var names — single vocabulary across all services

Use exactly these names. Do not introduce parallel vocabulary (`HOST_PORT` vs `SERVER_PORT`, `IMAGE_REPO` vs `SERVER_IMAGE`, `DEPS_DOCKERFILE` vs `SERVER_DEPS_DOCKERFILE`, etc.).

| Variable | Purpose | Default |
|----------|---------|---------|
| `SERVER_IMAGE` | Image repo (no tag) | `<repo>/<project>` |
| `SERVER_DEPS_DOCKERFILE` | Path to Dockerfile.deps | `docker/serve/Dockerfile.deps` |
| `SERVER_APP_DOCKERFILE` | Path to Dockerfile.app | `docker/serve/Dockerfile.app` |
| `SERVER_PORT` | Host port | service-specific |
| `SERVER_CONTAINER_PORT` | Container port | `8080` |
| `SERVER_GPUS` | GPU spec | `all` |
| `PYTORCH_VER`, `CUDA_VER`, `CUDNN_VER` | Base image axes (PyTorch case) | per project |
| `<DEP>_VER` | Pinned dependency versions | per project |
| `DEVICE` | Runtime device (`cuda:0`, `cpu`, …) | `cuda:0` |

### R5. Standard service names — `<project>-server-base` and `<project>-server`

```yaml
services:
  <project>-server-base:   # deps image — no runtime config
    ...
  <project>-server:        # app image — ports, env, gpus
    ...
```

Not `<project>-base`. Not `<project>-app`. Always `-server-base` and `-server`. The `container_name` on the runtime service matches: `container_name: <project>-server`.

### R6. GPU declaration — use top-level `gpus`, not `deploy.resources`

**WRONG** (verbose, swarm-only semantics, harder to override):
```yaml
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          count: 1
          capabilities: [gpu]
```

**RIGHT**:
```yaml
gpus: ${SERVER_GPUS:-all}
```

### R7. App layer is copy-only — no installs in `Dockerfile.app`

`Dockerfile.app` does only: `FROM ${BASE_IMAGE}`, `WORKDIR`, `COPY` of code/entrypoint, `chmod +x`, `ENTRYPOINT`. Any `RUN apt-get`, `RUN pip install`, model downloads, etc. belong in `Dockerfile.deps`. If the app layer takes more than a few seconds to rebuild, it is wrong.

### R8. Prefer official framework base images — and document any fallback

If the project uses a framework with a maintained image (e.g. `pytorch/pytorch:...` for PyTorch), base on it: interpreter, package manager, runtime libs, and CUDA are already wired up.

**Falling back to a raw `nvidia/cuda:...-devel` (or any non-framework base) is allowed only when the framework image genuinely doesn't fit.** When you do, you MUST leave a comment block at the top of `Dockerfile.deps` explaining *why* — so the next agent reading the file can verify the reason still holds before preserving the fallback.

The comment must state:
- which official image was rejected,
- the concrete blocker (be specific — version mismatch, missing toolchain, unpublished tag, etc.),
- a re-evaluation hint if applicable (e.g. "revisit when PyTorch publishes a 3.12 image").

Example:
```dockerfile
# BASE IMAGE FALLBACK — using nvidia/cuda instead of pytorch/pytorch.
# Reason: this project requires Python 3.12, but pytorch/pytorch only
#   publishes 3.11 images as of 2026-04. Re-evaluate after upstream
#   ships 3.12 tags and switch back to pytorch/pytorch:${PYTORCH_VER}-...
ARG CUDA_VER="12.8"
ARG CUDNN_VER="9"
FROM nvidia/cuda:${CUDA_VER}.0-cudnn${CUDNN_VER}-devel-ubuntu22.04
```

No comment, no fallback — default back to the official framework image.

### R9. Host port allocation — deterministic, documented

Every service's `SERVER_PORT` default MUST be unique across the monorepo. Allocate sequentially in the `180xx` range (e.g. 18080, 18081, 18082, …) and record the mapping in a top-level `PORTS.md` (one line per service: `<project> — 180xx — one-line purpose`). When adding a service, append the next free number; do not reuse or guess.

### R10. CPU-only mode — compose profile, GPU is the default

**Default is always GPU.** The bare `docker compose up` path must launch the GPU service; no flag required.

A CPU variant is added ONLY when the underlying model genuinely supports CPU inference (small models, pure-Python pipelines, debug workflows). For GPU-only models (large diffusion, FlashAttention kernels, etc.), do not add a CPU profile — document "GPU required" in the README and move on.

When CPU IS supported, split into compose profiles so the runtime is explicit:

```yaml
  <project>-server:
    profiles: ["gpu"]              # default profile
    gpus: ${SERVER_GPUS:-all}
    environment:
      DEVICE: ${DEVICE:-cuda:0}
    # …

  <project>-server-cpu:
    profiles: ["cpu"]              # opt-in
    extends:
      service: <project>-server
    # no gpus key — CPU host compatible
    environment:
      DEVICE: cpu
```

Default profile resolution: set `COMPOSE_PROFILES=gpu` in `.env.example` (and document it in README) so `docker compose up` runs GPU without extra flags. CPU use is an explicit opt-in: `docker compose --profile cpu up -d`. Never rely on unsetting `SERVER_GPUS` to "disable" GPUs — compose still renders the `gpus:` key and errors on hosts without an nvidia runtime.

## Core Pattern: deps + app Split

### Dockerfile.deps (heavy, rarely rebuilt)

```dockerfile
ARG PYTORCH_VER="2.7.1"
ARG CUDA_VER="12.8"
ARG CUDNN_VER="9"
FROM pytorch/pytorch:${PYTORCH_VER}-cuda${CUDA_VER}-cudnn${CUDNN_VER}-devel

ARG DEP_A_VER="<x.y.z>"
ARG DEP_B_VER="<x.y.z>"
ARG NUM_WORKERS="4"

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV APP_HOME="/<project>"
ENV MAX_JOBS=${NUM_WORKERS}

RUN apt-get update && apt-get install -y --no-install-recommends \
    git build-essential \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir -U pip setuptools wheel
RUN pip install --no-cache-dir "dep-a==${DEP_A_VER}" "dep-b==${DEP_B_VER}"

COPY ./configs /<project>/configs
COPY ./checkpoints /<project>/checkpoints

WORKDIR /<project>
```

### Dockerfile.app (thin, rebuilt often)

```dockerfile
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

WORKDIR /<project>

COPY ./docker/serve/app.py /<project>/docker/serve/app.py
COPY ./docker/serve/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
```

`BASE_IMAGE` has no default — compose always supplies it. This guarantees the app layer is built against the exact deps tag we just produced.

### entrypoint.sh

```bash
#!/usr/bin/env bash
set -euo pipefail
cd /<project>

if [[ "${1:-serve}" == "serve" ]]; then
  shift || true
  exec uvicorn docker.serve.app:app \
    --host 0.0.0.0 --port "${SERVER_CONTAINER_PORT:-8080}" "$@"
fi

exec "$@"
```

## Canonical docker-compose

Both `docker-compose.server.yml` (root) and `docker/serve/docker-compose.yaml` follow this shape. Adjust only `context` so each resolves to repo root.

```yaml
services:
  <project>-server-base:
    build:
      context: .
      dockerfile: ${SERVER_DEPS_DOCKERFILE:-docker/serve/Dockerfile.deps}
      args:
        PYTORCH_VER: ${PYTORCH_VER:-2.7.1}
        CUDA_VER: ${CUDA_VER:-12.8}
        CUDNN_VER: ${CUDNN_VER:-9}
        DEP_A_VER: ${DEP_A_VER:-<x.y.z>}
        DEP_B_VER: ${DEP_B_VER:-<x.y.z>}
        NUM_WORKERS: ${NUM_WORKERS:-4}
    image: ${SERVER_IMAGE:-<repo>/<project>}:pytorch${PYTORCH_VER:-2.7.1}-cuda${CUDA_VER:-12.8}-cudnn${CUDNN_VER:-9}-base

  <project>-server:
    build:
      context: .
      dockerfile: ${SERVER_APP_DOCKERFILE:-docker/serve/Dockerfile.app}
      args:
        BASE_IMAGE: ${SERVER_IMAGE:-<repo>/<project>}:pytorch${PYTORCH_VER:-2.7.1}-cuda${CUDA_VER:-12.8}-cudnn${CUDNN_VER:-9}-base
    image: ${SERVER_IMAGE:-<repo>/<project>}:pytorch${PYTORCH_VER:-2.7.1}-cuda${CUDA_VER:-12.8}-cudnn${CUDNN_VER:-9}-server
    container_name: <project>-server
    gpus: ${SERVER_GPUS:-all}
    ports:
      - "${SERVER_PORT:-<host-port>}:${SERVER_CONTAINER_PORT:-8080}"
    environment:
      SERVER_CONTAINER_PORT: ${SERVER_CONTAINER_PORT:-8080}
      DEVICE: ${DEVICE:-cuda:0}
      # service-specific env vars below
    entrypoint: ["/usr/local/bin/entrypoint.sh"]
    command: ["serve"]
    restart: unless-stopped
```

## Build Workflow

```bash
# Full build (first time or deps changed):
docker compose -f docker-compose.server.yml build

# Fast iteration (app code only):
docker compose -f docker-compose.server.yml build <project>-server
docker compose -f docker-compose.server.yml up -d --no-build <project>-server

# Bump versions without editing files:
PYTORCH_VER=2.8.0 CUDA_VER=12.9 docker compose -f docker-compose.server.yml build

# CPU-only (only if the service defines a cpu profile per R10):
docker compose -f docker-compose.server.yml --profile cpu up -d

# Stop:
docker compose -f docker-compose.server.yml down
```

## Verification (before claiming done)

The conformance checklist is self-attested; these commands produce objective evidence. Run all four from the repo root before declaring a service conformant. All intermediate artifacts stay inside the workspace — never write to `/tmp`, `~`, or anywhere outside the repo.

```bash
# Workspace-scoped scratch dir (add to .gitignore and .dockerignore).
mkdir -p .build

# 1. Compose renders without errors and resolves interpolation.
docker compose -f docker-compose.server.yml config > .build/rendered.yml

# 2. The rendered image tag reflects current version ARGs (should contain
#    pytorch<ver>-cuda<ver>-cudnn<ver>-base and -server). Fail if fixed strings.
grep -E "image: .*pytorch[0-9].*cuda[0-9].*cudnn[0-9].*-(base|server)" .build/rendered.yml

# 3. Build base + server; server layer should finish in seconds on cache hit.
docker compose -f docker-compose.server.yml build

# 4. Health check on the running server.
docker compose -f docker-compose.server.yml up -d <project>-server
curl -fsS "http://localhost:${SERVER_PORT:-<host-port>}/health"
docker compose -f docker-compose.server.yml down
```

If step 2's grep returns nothing, the tag is hardcoded — fix R3 before proceeding. If step 4 fails, `app.py` is missing the required `/health` endpoint — fix the app.py contract before proceeding.

Add `.build/` to both `.gitignore` and `.dockerignore` so verification artifacts never leak into commits or image contexts.

## Conformance Checklist

Run through this every time you touch a service. Any "no" is a bug to fix, not a style preference.

- [ ] Root `docker-compose.server.yml` exists.
- [ ] `docker/serve/docker-compose.yaml` exists and matches the root one.
- [ ] `docker/serve/` contains `Dockerfile.deps`, `Dockerfile.app`, `entrypoint.sh`, `app.py`, `README.md`.
- [ ] Root `.dockerignore` exists and does NOT ignore paths that `Dockerfile.deps` COPYs (`checkpoints/`, `configs/`, `data/`, …).
- [ ] Root `.env.example` exists, lists every var the compose files read, and is committed (real `.env` is gitignored).
- [ ] Monorepo only: each subproject has its own `docker-compose.server.yml`, `.dockerignore`, `.env.example` at the subproject root — no single hoisted compose at monorepo root.
- [ ] `app.py` exposes `GET /health` returning 200.
- [ ] `docker/serve/README.md` documents purpose, `SERVER_PORT`, non-standard env vars, and the build/run commands.
- [ ] No version string is hardcoded inside a base image tag — every version axis is its own `ARG`.
- [ ] Image tag string in compose is built from those same `ARG` values — bumping a version automatically yields a new tag.
- [ ] All env vars use the standard names from R4. No `IMAGE_REPO`, `HOST_PORT`, `IMAGE_TAG`, `DEPS_DOCKERFILE`.
- [ ] Service names are `<project>-server-base` and `<project>-server`.
- [ ] GPU is declared via top-level `gpus:`, not `deploy.resources.reservations.devices`.
- [ ] `Dockerfile.app` contains zero `RUN apt-get` / `RUN pip install` / download steps.
- [ ] Pip index URL (if any) is parameterized, not hardcoded to a specific CUDA version.
- [ ] Each pinned dep has its own `ARG <NAME>_VER` with a default, plumbed through compose `args:`.
- [ ] If the base image is NOT the official framework image (R8), the top of `Dockerfile.deps` has a `# BASE IMAGE FALLBACK — ...` comment with the rejected image, the blocker, and a re-evaluation hint.
- [ ] `SERVER_PORT` default is unique across the monorepo and recorded in `PORTS.md` (R9).
- [ ] GPU is the default profile; CPU profile exists only if the model actually supports CPU inference (R10).
- [ ] All four Verification commands pass (compose config renders, tag grep matches, build succeeds, `/health` returns 200).

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Monolithic `BASE_TAG` lump | Split into per-axis `ARG`s (R2) |
| Image tag with hardcoded version substring | Derive from version `ARG`s (R3) |
| Mixed naming (`HOST_PORT` here, `SERVER_PORT` there) | Use the R4 vocabulary everywhere |
| Compose only at root, or only in `docker/serve/` | Both files required (R1) |
| Service named `-base` / `-app` | Use `-server-base` / `-server` (R5) |
| `deploy.resources.reservations.devices` for GPUs | Top-level `gpus:` (R6) |
| Pip installs in `Dockerfile.app` | Move to `Dockerfile.deps` (R7) |
| `nvidia/cuda` for a PyTorch project with no fallback comment | Use `pytorch/pytorch:...` or document the blocker (R8) |
| Forgetting `chmod +x` on entrypoint | `RUN chmod +x` in `Dockerfile.app` |
| `CMD` instead of `ENTRYPOINT` + `command` | ENTRYPOINT for the script, compose `command` for the mode |
| Rebuilding everything after app change | Only rebuild the `-server` service, not the base |
| `.dockerignore` accidentally excludes `checkpoints/` that deps copies | Whitelist or remove the pattern; verify with `docker compose build` |
| Two services defaulting to the same `SERVER_PORT` | Allocate a new 180xx slot and record in `PORTS.md` (R9) |
| Emptying `SERVER_GPUS` to "go CPU" | Use the `cpu` compose profile (R10) |
| Writing verification artifacts to `/tmp` or `~` | Use workspace-local `.build/`, gitignored |
| Monorepo with one hoisted compose covering multiple subprojects | Each subproject gets its own `docker-compose.server.yml` (R1) |
| `app.py` without `/health` | Add it — verification step 4 depends on it |

## Migrating a Nonstandard Service

When you encounter an existing service that doesn't match, do not extend it as-is. Migrate first:

1. Split any monolithic `BASE_TAG` into per-axis `ARG`s (`PYTORCH_VER`, `CUDA_VER`, `CUDNN_VER`, …).
2. Rewrite the image tag in compose to interpolate those `ARG`s.
3. Rename env vars to the R4 vocabulary.
4. Rename services to `-server-base` / `-server`.
5. Replace `deploy.resources` GPU block with top-level `gpus:`.
6. Add the missing root or local compose file.
7. If the base is not the official framework image, add the R8 fallback comment (or switch back to the official image).
8. Allocate a unique `SERVER_PORT` and add the service to `PORTS.md` (R9).
9. If the service previously relied on an empty-GPUs hack for CPU, replace it with an opt-in `cpu` compose profile (R10) — or drop CPU support entirely if the model doesn't actually run on CPU.
10. Add the missing companion files: `.dockerignore`, `.env.example`, `app.py` `/health` endpoint, `docker/serve/README.md`.
11. Run the Verification commands; only then run the conformance checklist.
