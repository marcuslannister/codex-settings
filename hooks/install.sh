#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
codex_config_dir="${CODEX_HOME:-$HOME/.codex}"
config_file="$codex_config_dir/hooks.json"
tmp_file=$(mktemp "${TMPDIR:-/tmp}/codex-hooks.XXXXXX")
trap 'rm -f "$tmp_file"' EXIT

mkdir -p "$codex_config_dir"

jq_program='
  def is_managed:
    (.command // "") as $command
    | ["enforce-modern-cli.sh", "block-git-destructive.sh", "block-env-dump.sh", "gh-json.sh", "redirect-to-anvil.sh", "format-json.sh"]
    | any(. as $name | $command | contains("/hooks/" + $name));
  def strip:
    map(
      .hooks = ((.hooks // []) | map(select(is_managed | not)))
      | select((.hooks // []) | length > 0)
    );
  def command_hook($path): { type: "command", command: ("bash " + ($path | @sh)) };
  def pre_tool_hooks($root): [
    command_hook($root + "/hooks/enforce-modern-cli.sh"),
    command_hook($root + "/hooks/block-git-destructive.sh"),
    command_hook($root + "/hooks/block-env-dump.sh"),
    command_hook($root + "/hooks/gh-json.sh")
  ];

  .hooks |= (. // {})
  | .hooks.PreToolUse = ((.hooks.PreToolUse // [] | strip) + [
      { matcher: "Bash", hooks: pre_tool_hooks($root) },
      { matcher: "Bash|Read", hooks: [command_hook($root + "/hooks/redirect-to-anvil.sh")] }
    ])
  | .hooks.PostToolUse = ((.hooks.PostToolUse // [] | strip) + [
      { matcher: "Write|Edit|MultiEdit", hooks: [command_hook($root + "/hooks/format-json.sh")] }
    ])
'

if [[ -f "$config_file" ]]; then
  jq --arg root "$repo_root" "$jq_program" "$config_file" > "$tmp_file"
else
  jq -n --arg root "$repo_root" "{hooks: {}} | $jq_program" > "$tmp_file"
fi

if [[ -e "$repo_root/hooks.json" && "$config_file" -ef "$repo_root/hooks.json" ]]; then
  dd if="$tmp_file" of="$config_file" status=none
else
  mv "$tmp_file" "$config_file"
  trap - EXIT
fi
printf 'Installed repository hooks in %s\n' "$config_file"
