# Repository Guidelines

## Project Structure & Module Organization
This repository is a Codex configuration and skills collection. Keep changes scoped to the relevant area:

- `config.toml`, `configs/`, `policy/`, `rules/`: Codex runtime configuration, provider profiles, and policy files.
- `prompts/`: reusable slash-prompt templates in Markdown.
- `skills/*/SKILL.md`: installable Codex skills; each skill must keep the file name exactly `SKILL.md`. Current examples include `skills/Jujutsu/` and the `.system/skill-creator/` tooling.
- `scripts/`: small repo utilities such as config extractors and shell tests.
- `superpowers/skills/` and `superpowers/tests/`: bundled “superpowers” skills plus shell and Node-based regression tests.

## Build, Test, and Development Commands
- `codex`: smoke-test the repository after linking it to `~/.codex`.
- `bash scripts/test-extract-trusted-projects.sh`: verify the TOML project-extraction helper.
- `cd superpowers/tests/claude-code && ./run-skill-tests.sh --integration`: run Claude Code skill tests.
- `cd superpowers/tests/brainstorm-server && npm test`: run the brainstorm server Node test.

## Coding Style & Naming Conventions
Follow the local style of the area you edit. In JS/TS files, use 2-space indentation and keep imports grouped cleanly. Shell scripts should use `#!/usr/bin/env bash` and `set -euo pipefail`. Keep prompt and utility file names descriptive and stable, and preserve exact sentinel names such as `SKILL.md`, `AGENTS.md`, and policy/config filenames. When editing skills, keep frontmatter concise and trigger-focused.

## Testing Guidelines
Add or update the nearest test suite when behavior changes. Shell-based skill tests usually live under `superpowers/tests/**` and follow `test-*.sh`; JS tests use `*.test.js` or `*.test.sh`. For repo utilities, prefer small shell tests that run from a temporary fixture directory. Skill validation can also use `python3 skills/.system/skill-creator/scripts/quick_validate.py <skill-dir>` when `PyYAML` is available.

## Commit & Pull Request Guidelines
Recent history favors short imperative subjects, often with Conventional Commit prefixes, for example `feat: make ChatGPT the default model` or `Fix LiteLLM config for Github Copilot models`. Keep commits focused on one area. PRs should include a concise summary, affected paths, commands run for verification, linked issues when relevant, and screenshots for `pua/landing` UI changes.

## Configuration & Repo Hygiene
Do not treat local runtime artifacts as source material. Files such as `state_*.sqlite*`, `logs_*.sqlite*`, `cache/`, and `shell_snapshots/` are environment byproducts unless the change is explicitly about them. Keep `config.toml` and helper files like `trusted-projects.toml` aligned when contributor changes touch project trust settings.
