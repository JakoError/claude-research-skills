---
name: docker-split-service
description: Use when creating or modifying a Dockerized service - guides the deps+app two-stage Dockerfile pattern, docker-compose structure, entrypoint conventions, and env-driven configuration
---

# Docker Split Service Pattern

## Overview

Build Docker services using a **two-stage split**: a heavy `Dockerfile.deps` for dependencies and a thin `Dockerfile.app` for application code. This dramatically speeds up iteration — app changes rebuild in seconds, not minutes.

## When to Use

- Creating a new Docker-based service (API server, worker, etc.)
- Adding a new service variant to an existing project
- Refactoring a monolithic Dockerfile into faster-iterating layers

## Core Pattern: deps + app Split

### Dockerfile.deps (heavy, rarely rebuilt)

Contains OS packages, pip/conda installs, model weights, compiled libraries. Rebuilt only when dependencies change.

```dockerfile
# Use build args for base image version pinning
ARG BASE_TAG="latest"
FROM your-base-image:${BASE_TAG}

# Build args for dependency version pinning
ARG DEP_A_VER="1.0.0"
ARG DEP_B_VER="2.0.0"

ENV DEBIAN_FRONTEND=noninteractive
ENV APP_HOME="/myapp"

# System deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    git build-essential \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Language-specific deps (pip, npm, cargo, etc.)
RUN pip install --no-cache-dir -U pip setuptools wheel
RUN pip install --no-cache-dir "dep-a==${DEP_A_VER}" "dep-b==${DEP_B_VER}"

# Bake in project assets (configs, data, weights, etc.)
COPY ./configs /myapp/configs
COPY ./data /myapp/data

WORKDIR /myapp
```

### Dockerfile.app (thin, rebuilt often)

Sits on top of the deps image. Only copies application code and sets the entrypoint.

```dockerfile
ARG BASE_IMAGE="myrepo/myapp:base-tag"
FROM ${BASE_IMAGE}

WORKDIR /myapp

COPY ./docker/serve/app.py /myapp/docker/serve/app.py
COPY ./docker/serve/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
```

### Entrypoint Convention

Use a bash entrypoint that defaults to `serve` mode but allows arbitrary commands:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd /myapp

if [[ "${1:-serve}" == "serve" ]]; then
  shift || true
  exec uvicorn docker.serve.app:app --host 0.0.0.0 --port "${SERVER_CONTAINER_PORT:-8080}" "$@"
fi

exec "$@"
```

This lets you `docker run <image> serve` (default) or `docker run <image> bash` for debugging.

## docker-compose Structure

Use compose to wire the two-stage build together. Key conventions:

- **`*-base`**: builds deps image, no runtime config
- **`*-server`** (the service): builds app image referencing base, has ports/env/gpus

```yaml
services:
  myapp-base:
    build:
      context: .
      dockerfile: ${DEPS_DOCKERFILE:-docker/serve/Dockerfile.deps}
      args:
        BASE_TAG: ${BASE_TAG:-latest}
        DEP_A_VER: ${DEP_A_VER:-1.0.0}
    image: ${IMAGE_REPO:-myrepo/myapp}:${IMAGE_TAG:-latest}-base

  myapp-server:
    build:
      context: .
      dockerfile: ${APP_DOCKERFILE:-docker/serve/Dockerfile.app}
      args:
        BASE_IMAGE: ${IMAGE_REPO:-myrepo/myapp}:${IMAGE_TAG:-latest}-base
    image: ${IMAGE_REPO:-myrepo/myapp}:${IMAGE_TAG:-latest}-server
    container_name: myapp-server
    ports:
      - "${HOST_PORT:-8080}:${CONTAINER_PORT:-8080}"
    environment:
      CONTAINER_PORT: ${CONTAINER_PORT:-8080}
      # Add service-specific env vars here
    entrypoint: ["/usr/local/bin/entrypoint.sh"]
    command: ["serve"]
    restart: unless-stopped
```

### Image Tag Convention

Encode version info in the tag: `<repo>:<version-info>-<role>`

- `-base` suffix for deps image
- `-server` suffix for app image

Example for a PyTorch/CUDA project: `myrepo/myapp:pytorch2.7.1-cuda12.8-cudnn9-base`

### Env-Driven Configuration

- All version pins (`PYTORCH`, `CUDA`, `CUDNN`, package versions) are env vars with defaults
- Dockerfile paths are overridable (`SERVER_DEPS_DOCKERFILE`, `SERVER_APP_DOCKERFILE`)
- Image repo name is overridable (`SERVER_IMAGE`)
- Runtime config (model paths, device, ports) are environment variables in compose

## Build Workflow

```bash
# Full build (first time or deps changed):
docker compose -f docker-compose.server.yml build

# Fast iteration (app code only):
docker compose -f docker-compose.server.yml build myapp-server
docker compose -f docker-compose.server.yml up -d --no-build myapp-server

# GPU check:
docker compose -f docker-compose.server.yml up -d --no-build myapp-server
curl http://localhost:18080/health

# CPU-only mode:
DEVICE=cpu docker compose -f docker-compose.server.yml up -d --no-build myapp-server

# Stop:
docker compose -f docker-compose.server.yml down
```

## File Layout

```
project-root/
  docker/
    serve/
      Dockerfile.deps          # Heavy deps layer
      Dockerfile.app           # Thin app layer
      docker-compose.yaml      # Local compose (context: .)
      entrypoint.sh            # Shell entrypoint
      app.py                   # Application code (e.g. FastAPI)
      README.md                # Usage docs
  docker-compose.server.yml    # Root-level compose (recommended)
```

Keep a root-level compose file for convenience (`docker-compose.server.yml`) alongside a local one in `docker/serve/` — both use `context: .` pointing to repo root.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Putting pip installs in Dockerfile.app | Move to Dockerfile.deps — app layer should be copy-only |
| Hardcoding versions in Dockerfile | Use `ARG` with defaults, override via compose `args` or env |
| Missing `--no-cache-dir` on pip | Always use it to keep image size down |
| Forgetting `chmod +x` on entrypoint | Add `RUN chmod +x` in Dockerfile.app |
| Using `CMD` instead of `ENTRYPOINT` + `command` | ENTRYPOINT for the script, compose `command` for the mode |
| Rebuilding everything after app change | Only rebuild the app service, not the base |
