#!/usr/bin/env bash
set -euo pipefail

input_file="${1:-config.toml}"
output_file="${2:-trusted-projects.toml}"

if [[ ! -f "$input_file" ]]; then
  echo "input file not found: $input_file" >&2
  exit 1
fi

mkdir -p "$(dirname "$output_file")"

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
' "$input_file" > "$output_file"
