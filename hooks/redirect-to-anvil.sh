#!/usr/bin/env bash
# PreToolUse hook: redirect built-in calls to Anvil MCP equivalents
# when the Emacs daemon is reachable. No-op when Anvil is unavailable.
#
# - Bash git (read-only)  → mcp__anvil-emacs-eval__git-*
# - Read on *.org         → mcp__anvil-emacs-eval__org-read-*
set -euo pipefail

input=$(cat)
tool=$(jq -r '.tool_name // ""' <<<"$input")

deny() {
  jq -n --arg r "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  exit 0
}

# Cached Anvil probe (60s TTL) — avoids spawning emacsclient on every hook fire.
# Returns 0 if the Emacs daemon answers, 1 otherwise.
anvil_available() {
  local cache="/tmp/.anvil-probe-${UID:-$(id -u)}"
  if [[ -f $cache ]]; then
    local mtime now
    mtime=$(/usr/bin/stat -f %m "$cache" 2>/dev/null || /usr/bin/stat -c %Y "$cache" 2>/dev/null || echo 0)
    now=$(date +%s)
    if (( now - mtime < 60 )); then
      [[ $(cat "$cache") == ok ]]
      return
    fi
  fi
  if command -v emacsclient >/dev/null 2>&1 && emacsclient -e t >/dev/null 2>&1; then
    echo ok > "$cache"; return 0
  fi
  echo no > "$cache"; return 1
}

case "$tool" in
  Bash)
    cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
    first=$(awk '{print $1}' <<<"$cmd")
    [[ $first == git ]] || exit 0
    anvil_available || exit 0
    sub=$(awk '{print $2}' <<<"$cmd")
    case "$sub" in
      status)
        deny "Use \`mcp__anvil-emacs-eval__git-status\` — structured plist with ahead/behind counts and bucketed paths."
        ;;
      log)
        deny "Use \`mcp__anvil-emacs-eval__git-log\` — returns hash/date/author/subject plists."
        ;;
      diff)
        deny "Use \`mcp__anvil-emacs-eval__git-diff-names\` (paths) or \`git-diff-stats\` (file/insert/delete counts)."
        ;;
      rev-parse)
        deny "Use \`mcp__anvil-emacs-eval__git-head-sha\` or \`git-repo-root\`."
        ;;
      branch)
        # Only redirect bare 'git branch' (read-only). Allow -d/-D/-m/-c/--set-upstream etc.
        rest=$(awk '{$1=""; $2=""; print $0}' <<<"$cmd" | tr -d '[:space:]')
        if [[ -z $rest ]]; then
          deny "Use \`mcp__anvil-emacs-eval__git-branch-current\` — returns the current branch name."
        fi
        ;;
      worktree)
        sub3=$(awk '{print $3}' <<<"$cmd")
        if [[ $sub3 == list ]]; then
          deny "Use \`mcp__anvil-emacs-eval__git-worktree-list\` — structured plists."
        fi
        ;;
    esac
    ;;
  Read)
    path=$(jq -r '.tool_input.file_path // ""' <<<"$input")
    if [[ $path == *.org ]]; then
      anvil_available || exit 0
      deny "Use \`mcp__anvil-emacs-eval__org-read-outline\` (structure) or \`org-read-headline\` / \`org-read-by-id\` (subtree). 10–20× cheaper than full Read on large org files."
    fi
    ;;
esac
