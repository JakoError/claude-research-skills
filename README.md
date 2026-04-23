# claude-research-skills

A collection of [Claude Code](https://claude.com/claude-code) skills for research workflows.

## Skills

- **docker-split-service** — scaffold Dockerized services using a deps+app two-stage Dockerfile pattern.
- **fetching-papers** — download and parse academic papers into readable markdown.
- **psc-bridges2** — SSH/SLURM workflows on PSC Bridges-2 (partitions, GPU types, allocations, Ocean/jet, modules, Singularity, AirLab).
- **research-sandbox** *(submodule, forked from [fanurs/claude-research-sandbox](https://github.com/fanurs/claude-research-sandbox))* — create a sandboxed autonomous research environment with Docker + GPU + a multi-session Claude loop.

## Install

Pick one of the methods below.

### Method 1 — Plugin install (recommended)

One-time, two commands inside Claude Code. No clone, no copy. `/plugin update` keeps it current.

```
/plugin marketplace add JakoError/claude-research-skills
/plugin install research-skills@jakoerror-research
/reload-plugins
```

> If clone fails with `Host key verification failed`, your machine doesn't trust GitHub's SSH key yet. Fix once with:
> ```bash
> mkdir -p ~/.ssh && ssh-keyscan -t ed25519,rsa github.com >> ~/.ssh/known_hosts
> ```
> or force HTTPS globally:
> ```bash
> git config --global url."https://github.com/".insteadOf git@github.com:
> ```

To uninstall later: `/plugin uninstall research-skills@jakoerror-research`.

### Method 2 — Manual copy (no plugin system)

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

To update: `git pull && git submodule update --remote && cp -r skills/* ~/.claude/skills/`

### Method 3 — Symlink (live edits)

Same as Method 2, but symlink instead of copy so `git pull` instantly updates loaded skills:

```bash
git clone --recurse-submodules https://github.com/JakoError/claude-research-skills.git ~/code/claude-research-skills
cd ~/.claude/skills
for s in ~/code/claude-research-skills/skills/*/; do
  ln -s "$s" "$(basename "$s")"
done
```

> Note: don't combine Method 1 with Method 2/3 — duplicate skills will load twice.
