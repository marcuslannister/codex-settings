#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXTRACTOR="$SCRIPT_DIR/extract-trusted-projects.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

cat >"$tmpdir/config.toml" <<'EOF'
model = "gpt-5.4"
approval_policy = "on-request"

[features]
skills = true

[projects."/Users/ken/github/codex"]
trust_level = "trusted"

[projects."/Users/ken/.emacs.d"]
trust_level = "trusted"
note = "keep me with the project block"

[tui]
theme = "catppuccin-latte"

[[skills.config]]
path = "/tmp/skill/SKILL.md"
enabled = false
EOF

cat >"$tmpdir/expected.toml" <<'EOF'
[projects."/Users/ken/github/codex"]
trust_level = "trusted"

[projects."/Users/ken/.emacs.d"]
trust_level = "trusted"
note = "keep me with the project block"
EOF

bash "$EXTRACTOR" "$tmpdir/config.toml" "$tmpdir/trusted-projects.toml"

diff -u "$tmpdir/expected.toml" "$tmpdir/trusted-projects.toml"

if grep -q '^\[features\]' "$tmpdir/trusted-projects.toml"; then
  echo "unexpected non-project section copied"
  exit 1
fi

if grep -q '^\[tui\]' "$tmpdir/trusted-projects.toml"; then
  echo "unexpected tui section copied"
  exit 1
fi

echo "extract-trusted-projects: PASS"
