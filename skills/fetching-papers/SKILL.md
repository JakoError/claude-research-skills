---
name: fetching-papers
description: Use when the user asks to download, fetch, or parse an academic paper into readable markdown, or references a paper by short-name/code-dir that isn't yet under ./papers/. Covers arXiv, HuggingFace Papers, OpenReview, ACL/CVF, and DOI sources; uses mineru for PDF→markdown.
---

# Fetching Papers

## Overview

Download an academic paper and parse it to markdown + extracted figures using **mineru**, storing results under `./papers/<PAPER-ID>/` with the project's existing convention.

**Core principle:** Paper-ID matches the project's code-dir name when one exists (e.g., `DiffV2IR/` ↔ `papers/DiffV2IR/`). Never invent a new naming scheme if the project already has one.

## When to Use

- User says "download the X paper", "get the paper for Y", "parse this PDF"
- User references a paper by name/abbreviation that isn't yet in `./papers/`
- User wants markdown output of a PDF to read or feed to another tool

**Skip when:** the paper already exists at `papers/<ID>/<ID>.md` — just read it.

## Workflow

```dot
digraph fetch {
  "Identify paper" [shape=box];
  "Resolve to canonical URL" [shape=box];
  "papers/<ID>/ exists?" [shape=diamond];
  "Skip — read existing" [shape=box];
  "Download PDF" [shape=box];
  "Parse with mineru" [shape=box];
  "Verify output" [shape=box];

  "Identify paper" -> "Resolve to canonical URL";
  "Resolve to canonical URL" -> "papers/<ID>/ exists?";
  "papers/<ID>/ exists?" -> "Skip — read existing" [label="yes, .md present"];
  "papers/<ID>/ exists?" -> "Download PDF" [label="no"];
  "Download PDF" -> "Parse with mineru";
  "Parse with mineru" -> "Verify output";
}
```

## Step 1 — Identify the paper & pick Paper-ID

The user often names a paper by abbreviation (e.g., "PID", "F-ViTA", "DiffV2IR"). Resolve it:

1. **Check existing project layout first** — `ls papers/` and `ls` the project root.
   - If a top-level code dir matches (e.g., `PID/`), **use that name as Paper-ID** (preserve case).
   - Look at sibling `papers/<other>/` entries for the naming style already used.
2. **Grep for citations** in the matching code dir's README, paper-related comments, or `*.bib`:
   ```
   Grep pattern="arxiv|doi|openreview|huggingface.co/papers" path="<code-dir>"
   ```
3. **If no local reference**, ask the user for the arXiv ID / URL / title. Do not guess IDs.

## Step 2 — Resolve to a canonical PDF URL

Try sources in order (use the first that works):

| Source | URL pattern |
|---|---|
| arXiv | `https://arxiv.org/pdf/<ID>.pdf` (strip version for latest) |
| HuggingFace Papers | `https://huggingface.co/papers/<arxiv-id>` → links to PDF |
| OpenReview | `https://openreview.net/pdf?id=<ID>` |
| CVF Open Access | `https://openaccess.thecvf.com/content/<venue>/papers/<...>.pdf` |
| ACL Anthology | `https://aclanthology.org/<ID>.pdf` |
| DOI (Springer/Elsevier/etc.) | resolve via `https://doi.org/<DOI>` |

If the user has the `huggingface-skills:huggingface-papers` skill available, prefer it for HF-indexed papers (gives structured metadata + abstract).

## Step 3 — Ensure mineru is installed

Check the project's Python env first:

- `E:\Code\CMU\lab\RGB2IR` stores env details in `python_environment.md` — **read it** and use that env.
- Otherwise look for `pyproject.toml` / `.venv/` / `requirements.txt`.
- If the user hasn't specified an env, ask before installing.

Install via **uv** into that env:

```bash
# Preferred: install into the project/user-preferred env
uv tool install -U "mineru[core]"
# OR, for one-off use without polluting tool env:
uv run --with "mineru[core]" -- mineru --help
```

Verify: `mineru --version`. If it fails, do not silently fall back to another parser — report the error and ask.

## Step 4 — Download the PDF

```bash
mkdir -p "papers/<ID>"
curl -L -f -o "papers/<ID>/<ID>.pdf" "<resolved-url>"
```

Use `-f` so HTTP errors fail the command. Verify file is a real PDF: `file papers/<ID>/<ID>.pdf` should report `PDF document`.

## Step 5 — Parse with mineru

```bash
mineru -p "papers/<ID>/<ID>.pdf" -o "papers/<ID>/"
```

mineru writes markdown + figures into `papers/<ID>/<ID>/` (nested subdir named after the PDF). That nested layout matches what already exists for `papers/F-ViTA/F-ViTA/`.

Common flags:
- `-b pipeline` (default, CPU/GPU local) vs `-b vlm-transformers` (heavier, better for complex layout)
- `-l en` to pin language and avoid autodetection overhead
- `--formula-enable true --table-enable true` (defaults on; keep on for ML papers)

Run `mineru --help` for the full list.

## Step 6 — Verify

- Read the first ~50 lines of the generated `.md` and confirm title + authors match what the user asked for.
- List the output dir so the user sees what was produced.
- Never claim success without opening the markdown.

## Final layout

```
papers/
  <ID>/
    <ID>.pdf
    <ID>/
      <ID>.md
      images/
      <ID>_content_list.json
      <ID>_layout.pdf   (optional debug)
```

## Common Mistakes

| Mistake | Fix |
|---|---|
| Using marker / pymupdf4llm / pdftotext instead of mineru | User asked for mineru. Use mineru. |
| Flat `papers/<id>.pdf` | Always `papers/<ID>/<ID>.pdf` (matches existing project layout) |
| Lowercasing the ID | Preserve casing of the matching code dir (`DiffV2IR`, not `diffv2ir`) |
| Creating a new venv | Read `python_environment.md` / ask the user; don't spawn `.venv-papers` |
| Guessing arXiv IDs | If no local citation found, ask the user for the URL |
| `pip install mineru` | Use `uv tool install` or `uv run --with` |
| Declaring done without reading the .md | Always verify title/abstract |

## Red Flags — STOP

- About to `pip install` instead of `uv tool install`
- About to save as flat `papers/foo.pdf`
- About to guess an arXiv ID without asking
- About to fall back to a non-mineru parser silently
- About to create a new venv without consulting `python_environment.md`

All of these mean: stop, re-read Steps 1 and 3.
