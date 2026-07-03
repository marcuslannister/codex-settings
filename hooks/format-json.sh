#!/usr/bin/env bash
# PostToolUse hook: pretty-print JSON files after Write/Edit/MultiEdit.
# - No-op on non-*.json paths and on *.jsonl / *.ndjson
# - Leaves invalid JSON untouched and surfaces a stderr note (don't damage broken files)
set -euo pipefail

input="$(cat)"
tool="$(jq -r '.tool_name // empty' <<<"$input")"

case "$tool" in
  Write|Edit|MultiEdit) ;;
  *) exit 0 ;;
esac

path="$(jq -r '.tool_input.file_path // empty' <<<"$input")"

case "$path" in
  *.jsonl|*.ndjson) exit 0 ;;
  *.json) ;;
  *) exit 0 ;;
esac

[ -f "$path" ] || exit 0

tmp="${path}.fmt.$$"
if jq --indent 2 . "$path" > "$tmp" 2>/dev/null; then
  if ! cmp -s "$path" "$tmp"; then
    mv "$tmp" "$path"
  else
    rm -f "$tmp"
  fi
else
  rm -f "$tmp"
  echo "format-json: $path is not valid JSON; left unchanged" >&2
fi

exit 0
