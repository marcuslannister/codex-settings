#!/usr/bin/env bash
# PostToolUse: in a herdr pane, tell the agent once per session when context
# fill reaches HANDOFF_TOKENS, so it hands off to a new tab before auto compact
# (model_auto_compact_token_limit = 650000 in config.base.toml) fires.
# 360000 is 36/65 of that limit: the ratio Claude Code uses (hand off at 36%,
# auto compact at 65%).
# The fill is last_token_usage.total_tokens of the newest token_count event in
# the rollout (transcript_path): the size of the last request. It drops after a
# compaction. total_token_usage is a running sum and is not the fill.
# Codex writes a response's token_count after that response's tool output, so
# the fill lags by one response. The first tool call of a session sees none.
# Never blocks a tool: on any error, exit 0 with no output.
set -euo pipefail
trap 'exit 0' ERR
exec 2>/dev/null

HANDOFF_TOKENS="${HANDOFF_TOKENS:-360000}"
[ "${HERDR_ENV:-}" = "1" ] || exit 0
[[ $HANDOFF_TOKENS =~ ^[0-9]+$ ]] || exit 0

# A subagent has its own agent_id and its own context: only the main thread hands off.
{ read -r session; read -r transcript; } < <(
  jq -r 'select((.agent_id // "") == "") | (.session_id // ""), (.transcript_path // "")')
[[ ${session:-} =~ ^[A-Za-z0-9_-]+$ ]] && [ -f "${transcript:-}" ] || exit 0

dir="${TMPDIR:-/tmp}/codex-ctx"
warned="$dir/$session.warned"
[ ! -e "$warned" ] || exit 0

# Prints the newest valid fill on stdin, or nothing. tail -n +2 drops a line cut
# in half (or session_meta, when stdin is the whole rollout). An event with info
# null has no usage: skip it, keep the newest real one.
newest_fill() {
  tail -n +2 | grep -F '"type":"token_count"' |
    jq -r 'select(.payload.info != null) | .payload.info.last_token_usage.total_tokens | numbers' | tail -n 1
}
# The last 1 MiB holds many token_count events. A long tool output can push them
# all out of it: then read the whole rollout once.
# shortcut: one full read, not a backward search in chunks; upgrade if a rollout
# often has more than 1 MiB after its last count.
tokens=$(tail -c 1048576 "$transcript" | newest_fill || true)
[ -n "$tokens" ] || tokens=$(newest_fill < "$transcript" || true)
[[ $tokens =~ ^[0-9]+$ ]] && [ "$tokens" -ge "$HANDOFF_TOKENS" ] || exit 0

# noclobber makes the create atomic: two parallel tool calls warn once.
mkdir -p "$dir"
(set -C; : > "$warned") || exit 0

jq -n --arg msg "Context fill is ${tokens} tokens (handoff threshold ${HANDOFF_TOKENS} tokens). Read $HOME/Projects/agent-scripts/global/rules/handoff.md and hand off now." \
  '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $msg}}'
