# claude-research-skills

A collection of [Claude Code](https://claude.com/claude-code) skills for research workflows.

## Skills

- **docker-split-service** — scaffold Dockerized services using a deps+app two-stage Dockerfile pattern.
- **fetching-papers** — download and parse academic papers into readable markdown.
- **research-sandbox** *(submodule, forked from [fanurs/claude-research-sandbox](https://github.com/fanurs/claude-research-sandbox))* — create a sandboxed autonomous research environment with Docker + GPU + a multi-session Claude loop.

## Install

Clone with submodules:

```bash
git clone --recurse-submodules https://github.com/JakoError/claude-research-skills.git
```

Symlink (or copy) each skill into `~/.claude/skills/`:

```bash
ln -s "$PWD/claude-research-skills/skills/docker-split-service"   ~/.claude/skills/docker-split-service
ln -s "$PWD/claude-research-skills/skills/fetching-papers"        ~/.claude/skills/fetching-papers
ln -s "$PWD/claude-research-skills/skills/research-sandbox"       ~/.claude/skills/research-sandbox
```

## Updating the submodule

```bash
git submodule update --remote skills/research-sandbox
```
