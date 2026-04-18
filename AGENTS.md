# Repository Guidelines

## Project Structure & Module Organization
This repository is a Codex configuration and skills collection. Keep changes scoped to the relevant area:

- `config.toml`, `configs/`, `policy/`, `rules/`: Codex runtime configuration, provider profiles, and policy files.
- `prompts/`: reusable slash-prompt templates in Markdown.
- `skills/*/SKILL.md`: installable Codex skills; each skill must keep the file name exactly `SKILL.md`. Current examples include `skills/jujutsu/` and the `.system/skill-creator/` tooling.
- `scripts/`: small repo utilities such as config extractors and shell tests.
- `superpowers/skills/` and `superpowers/tests/`: bundled “superpowers” skills plus shell and Node-based regression tests.

## Build, Test, and Development Commands
- `codex`: smoke-test the repository after linking it to `~/.codex`.
- `bash scripts/test-extract-trusted-projects.sh`: verify the TOML project-extraction helper.
- `cd superpowers/tests/claude-code && ./run-skill-tests.sh --integration`: run Claude Code skill tests.
- `cd superpowers/tests/brainstorm-server && npm test`: run the brainstorm server Node test.

## Search Tools
- Prefer `rg "pattern"` for text search and `rg --files` for file listing.
- Prefer `fd name` for path discovery and `fd -t d name` for directory discovery.
- Fall back to `grep` or `find` only when `rg` or `fd` is unavailable.

## Version Control
- If the repository contains `.jj/`, prefer `jj` over Git porcelain for status, diff, log, commit, and push-related work unless the user explicitly asks for Git.

## Coding Style & Naming Conventions
Follow the local style of the area you edit. In JS/TS files, use 2-space indentation and keep imports grouped cleanly. Shell scripts should use `#!/usr/bin/env bash` and `set -euo pipefail`. Keep prompt and utility file names descriptive and stable, and preserve exact sentinel names such as `SKILL.md`, `AGENTS.md`, and policy/config filenames. When editing skills, keep frontmatter concise and trigger-focused.

## Testing Guidelines
Add or update the nearest test suite when behavior changes. Shell-based skill tests usually live under `superpowers/tests/**` and follow `test-*.sh`; JS tests use `*.test.js` or `*.test.sh`. For repo utilities, prefer small shell tests that run from a temporary fixture directory. Skill validation can also use `python3 skills/.system/skill-creator/scripts/quick_validate.py <skill-dir>` when `PyYAML` is available.

## Commit & Pull Request Guidelines
Recent history favors short imperative subjects, often with Conventional Commit prefixes, for example `feat: make ChatGPT the default model` or `Fix LiteLLM config for Github Copilot models`. Keep commits focused on one area. PRs should include a concise summary, affected paths, commands run for verification, linked issues when relevant, and screenshots for `pua/landing` UI changes.

## Configuration & Repo Hygiene
Do not treat local runtime artifacts as source material. Files such as `state_*.sqlite*`, `logs_*.sqlite*`, `cache/`, and `shell_snapshots/` are environment byproducts unless the change is explicitly about them. Keep `config.toml` and helper files like `trusted-projects.toml` aligned when contributor changes touch project trust settings.

## English Coaching

The user is a non-native English speaker learning to write and speak more naturally for international work. Apply this in every session, passively, without being asked:

- When the user writes in English and makes grammar or phrasing mistakes, add a correction block at the end of your reply. If the reply is primarily tool use with no text, still output a short text line before the corrections.
Each correction is two lines,  starting with 😇 original , new line with 👉 corrected (Pattern name).
No explanation beyond the pattern name. One item per mistake. Prioritize the most important ones, skip minor ones.
- Tone: patient and encouraging, like a kind teacher. Never cold or clinical.

Common patterns to identify: Missing article, Wrong article, Redundant preposition, Gerund vs. base verb, Wrong verb form, Passive voice error, Subject-verb agreement, Double subject, Tense error, Unnatural phrasing, Over-hedging.

Ignore capitalization error.

Example format (no quotation marks):
😇 discuss about
👉 discuss (Redundant preposition)

😇 I am very interest
👉 I am very interested (Wrong verb form)

😇 it is not good to be read
👉 it's hard to read (Unnatural phrasing)

## Never

- Modify `.env`, lockfiles, or CI secrets without explicit approval
- Remove a referenced symbol without searching call sites first
- Commit without running tests when the project has a fast test suite

## Always

- Show diff before committing
- Update CHANGELOG for user-facing changes if the project keeps one

## Verification

- Run the project's test and lint commands before declaring a change complete
- API changes: update or add contract tests if the project has them
- UI changes: capture before/after screenshots

## Compact Instructions

Preserve:

1. Architecture decisions (NEVER summarize)
2. Modified files and key changes
3. Current verification status (pass/fail commands)
4. Open risks, TODOs, rollback notes

