# Changelog

## Unreleased

- Stop the hooks from reading a heredoc body as commands. `lib.sh` has a new `strip_heredocs`, which `read_command` runs first: it drops the body and end word of each heredoc, so `cat >> f <<'EOF'` with a body line that starts with `set`, `env`, or `export` is no longer denied as an environment dump (the same for `block-git-destructive`, `gh-json`, and `enforce-modern-cli`). A body stays checked when a shell reads it (`sh`, `bash`, `ssh`, `source`, or `eval` on the opening line), and an unquoted body keeps its lines with `$` or a backtick, because they expand.

- Make the hooks work on Linux and Windows (Git Bash), not only macOS. `lib.sh` reads the `stat` mtime with GNU `stat -c %Y` first: the old order made `redirect-to-anvil.sh` exit 1 with no decision on every second call. Under MSYS, `lib.sh` runs `jq -b`, so a native `jq.exe` does not write CRLF; `format-json.sh` and `context-handoff.sh` source `lib.sh` for the same reason (`read -r` kept a `\r` in the rollout path, so the handoff warning never fired). `enforce-modern-cli.sh` rewrites or denies toward `rg`, `eza`, `fd`, and `sd` only when `command -v` finds the tool. `test-hooks.sh` sends the command on stdin (MSYS rewrote `/usr/bin/...` arguments) and prints `N passed, M failed`. `hooks/AGENTS.md` holds the portability rule, and `.github/workflows/hooks.yml` runs the tests on macOS, Linux, and Windows.

- Add a PostToolUse hook, `hooks/context-handoff.sh`: in a Herdr pane it warns the agent once per session when context fill reaches 360000 tokens (36/65 of the auto compact limit), so the agent hands off to a new tab first. `HANDOFF_TOKENS` overrides the threshold. Run `hooks/install.sh`, then review the hook with `/hooks`.
- Replace the deprecated `[features].multi_agent` with `multi_agent_v2` (stable in Codex 0.171.0): no deprecation warning at start, and `spawn_agent` and `wait_agent` still work.
- Remove seven subagents with no calls in 90 days (command-creator, deep-reflector, github-issue-fixer, insight-documenter, instruction-reflector, pr-reviewer, ui-engineer).
- Auto compact at 650000 tokens, 65% of the 1M context window (was 90%).
- Load the codegraph MCP server only in indexed repos: Codex reads `mcp_servers` from a trusted project's `.codex/config.toml`, so the global entry is gone. First-turn input in `/tmp`: 25500 → 22919 tokens with the Nowledge lean patch.
- Point `AGENTS.md` at the generated Codex instructions in the `home` repo (`~/Projects/home/AGENTS.codex.md`)

- Update the Herdr Codex integration version marker from 8 to 10
- Remove unsupported skills and voice transcription feature flags from the shared Codex configuration
- Add a portable Codex Stop hook for Nowledge Mem capture and session-scoped skill outcome reporting
- Standardize safety-hook deny and rewrite responses, allow successful hooks to exit silently, share command parsing with separator data, and add a self-check
- Preserve glob and replacement arguments in modern CLI rewrites
- Add portable installer and reusable safety hooks for Codex
- Point `AGENTS.md` to the tracked generated Codex instructions
- Add agent guidance for domain docs, GitHub issues, and triage labels
- Add the Herdr agent-state hook
- Disable Codex local Memory by default
- Remove the Codex claude-mem plugin
- Refresh shared Codex defaults and feature flags
- Slim README to config + prompts; drop unused alternate `configs/`
