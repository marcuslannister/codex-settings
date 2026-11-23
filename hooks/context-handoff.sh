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

# The last 1 MB holds many token_count events. tail -n +2 drops a line cut in
# half. An event with info null has no usage: skip it, keep the newest real one.
tokens=$(tail -c 1048576 "$transcript" | tail -n +2 | grep -F '"type":"token_count"' |
  jq -r 'select(.payload.info != null) | .payload.info.last_token_usage.total_tokens' | tail -n 1)
[[ $tokens =~ ^[0-9]+$ ]] && [ "$tokens" -ge "$HANDOFF_TOKENS" ] || exit 0

# noclobber makes the create atomic: two parallel tool calls warn once.
mkdir -p "$dir"
(set -C; : > "$warned") || exit 0

jq -n --arg msg "Context fill is ${tokens} tokens (handoff threshold ${HANDOFF_TOKENS} tokens). Read $HOME/Projects/agent-scripts/global/rules/handoff.md and hand off now." \
  '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $msg}}'
