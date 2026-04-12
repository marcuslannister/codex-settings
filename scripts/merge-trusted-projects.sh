#!/usr/bin/env bash
set -euo pipefail

config_file="${1:-config.toml}"
trusted_file="${2:-trusted-projects.toml}"

if [[ ! -f "$config_file" ]]; then
  echo "config file not found: $config_file" >&2
  exit 1
fi

if [[ ! -f "$trusted_file" ]]; then
  echo "trusted projects file not found: $trusted_file" >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

config_without_projects="$tmpdir/config-without-projects.toml"
trusted_projects_only="$tmpdir/trusted-projects-only.toml"
merged_config="$tmpdir/config.merged.toml"

awk '
/^\[projects\.".*"\]$/ {
  in_project = 1
  next
}

/^\[\[.*\]\]$/ || /^\[[^[].*\]$/ {
  if (in_project) {
    in_project = 0
  }
}

in_project {
  next
}

/^[[:space:]]*$/ {
  blank_buffer[++blank_count] = $0
  next
}

{
  for (i = 1; i <= blank_count; i++) {
    print blank_buffer[i]
  }
  delete blank_buffer
  blank_count = 0
  print
}
' "$config_file" > "$config_without_projects"

awk '
function flush_block(    end, i) {
  end = block_count
  while (end > 0 && block[end] ~ /^[[:space:]]*$/) {
    end--
  }

  if (end == 0) {
    delete block
    block_count = 0
    return
  }

  if (wrote_block) {
    print ""
  }

  for (i = 1; i <= end; i++) {
    print block[i]
  }

  wrote_block = 1
  delete block
  block_count = 0
}

/^\[projects\.".*"\]$/ {
  flush_block()
  in_project = 1
  block[++block_count] = $0
  next
}

/^\[\[.*\]\]$/ || /^\[[^[].*\]$/ {
  flush_block()
  in_project = 0
  next
}

in_project {
  block[++block_count] = $0
}

END {
  flush_block()
}
' "$trusted_file" > "$trusted_projects_only"

if [[ -s "$config_without_projects" ]]; then
  cat "$config_without_projects" > "$merged_config"
else
  : > "$merged_config"
fi

if [[ -s "$trusted_projects_only" ]]; then
  if [[ -s "$merged_config" ]]; then
    printf '\n' >> "$merged_config"
  fi
  cat "$trusted_projects_only" >> "$merged_config"
fi

mv "$merged_config" "$config_file"
