# claude-research-skills

A collection of [Claude Code](https://claude.com/claude-code) skills for research workflows.

## Skills

- **docker-split-service** — scaffold Dockerized services using a deps+app two-stage Dockerfile pattern.
- **fetching-papers** — download and parse academic papers into readable markdown.
- **research-sandbox** *(submodule, forked from [fanurs/claude-research-sandbox](https://github.com/fanurs/claude-research-sandbox))* — create a sandboxed autonomous research environment with Docker + GPU + a multi-session Claude loop.

## Install

Clone with submodules, then copy each skill into your Claude skills folder.

```bash
git clone --recurse-submodules https://github.com/JakoError/claude-research-skills.git
cd claude-research-skills
```

**Claude Code** (user-level skills, `~/.claude/skills/`):

```bash
cp -r skills/* ~/.claude/skills/
```

**Claude Agent SDK** (project-level skills, `./.claude/skills/`):

```bash
mkdir -p /path/to/your/project/.claude/skills
cp -r skills/* /path/to/your/project/.claude/skills/
```

## Updating

Pull the latest skills and submodule commits:

```bash
git pull
git submodule update --remote
cp -r skills/* ~/.claude/skills/   # re-copy to refresh
```
