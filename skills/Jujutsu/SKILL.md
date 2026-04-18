---
name: jujutsu
description: Use when the current repository contains a `.jj/` directory and version-control work requires Jujutsu commands instead of Git porcelain.
---

# Jujutsu

## Overview

Use Jujutsu-first workflows in repositories managed by `jj`. When `.jj/` exists in the repo root, treat `jj` as the default interface for everyday version-control tasks.

## Prefer These Commands

Use the `jj` equivalent of the task at hand:

- Inspect working copy: `jj status`
- Review changes: `jj diff`
- Review history: `jj log`
- Record changes: `jj commit`
- Rename or update change description: `jj describe`
- Create or move to a new change: `jj new`
- Manage bookmarks: `jj bookmark set`
- Push through Git remote integration: `jj git push`

## Guardrails

Avoid Git porcelain commands such as `git status`, `git diff`, `git log`, and `git commit` for routine work in Jujutsu repos unless the user explicitly asks for Git or a task has no practical `jj` equivalent.

Do not assume bookmark names, remote names, or whether the user wants to push `@`, `@-`, or another revision. Inspect the repository state first, then choose the appropriate `jj bookmark` and `jj git push` commands for that repo.

Use low-level Git commands only when required for interoperability, for example `jj git push`, remote inspection, or a workflow that clearly depends on Git-specific behavior.
