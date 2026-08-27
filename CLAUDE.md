@AGENTS.md

# Claude Code specifics

[`AGENTS.md`](AGENTS.md), imported above, is the operational contract and applies in full. It is written
to be tool neutral so that Codex and other agents read the same rules. Only the Claude Code
affordances live here.

## Before you touch code

`AGENTS.md` says to orient before editing. In Claude Code the way to do that is the codemap:
it lives in the Obsidian vault under `Claude/repomaps/` and is read via the `read-codemap`
skill (`/codemap hvtiRdatabuild`). If the codemap looks stale, say so and offer to refresh it
(`/regenerate-codemap`) rather than working from a guess.

If the vault is not available, say so rather than staying quiet about it, then orient from the
repo itself — `NAMESPACE`, `R/`, and the README — before editing.

## PHI, credentials and the transcript

`AGENTS.md`'s PHI rules extend to this conversation. A Claude Code session prints tool output
into a transcript that is stored, so:

- Do not print rows from a real dataset to inspect them. Print `dim()`, `names()`, `class()`,
  counts and verdicts. Aggregates are fine; patient values are not.
- Do not echo `Sys.getenv("HVI_DW_PWD")`, or any command that dumps the environment, to check
  whether a credential resolved. Check the **method** — `dw_connect()` reports which rung of
  the ladder it used — never the secret.
- If a debugging step genuinely needs real data, say what you need and why, and let the
  maintainer run it rather than pulling it into the transcript.

## Prose

`AGENTS.md` points at the house voice. In Claude Code, apply the `ehrlinger-writing` skill:
it carries the same voice, reader persona and project context, kept in sync from the vault
sources. For documentation *structure*, the `r-package-style` skill is the companion.
