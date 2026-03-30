---
name: Jujutsu
description: Use when the current repository contains a `.jj/` directory and Codex needs to inspect, diff, log, commit, or otherwise perform version-control work. Prefer `jj status`, `jj diff`, `jj log`, `jj commit`, and related `jj` commands over Git porcelain commands in Jujutsu repositories.
---

# Jujutsu

## Overview

Use Jujutsu-first workflows in repositories managed by `jj`. When `.jj/` exists in the repo root, treat `jj` as the default interface for everyday version-control tasks.

## Detect Jujutsu Repos

Check for a `.jj/` directory before defaulting to Git porcelain. If `.jj/` is present, prefer `jj` for status, history, diffs, and recording changes.

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

## Request Mapping

Interpret the request `jj push` as this sequence:

1. `jj bookmark set main --revision=@-`
2. `jj git push --bookmark main`

## Guardrails

Avoid Git porcelain commands such as `git status`, `git diff`, `git log`, and `git commit` for routine work in Jujutsu repos unless the user explicitly asks for Git or a task has no practical `jj` equivalent.

Use low-level Git commands only when required for interoperability, for example `jj git push`, remote inspection, or a workflow that clearly depends on Git-specific behavior.
