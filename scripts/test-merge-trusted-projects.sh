#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MERGER="$SCRIPT_DIR/merge-trusted-projects.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

cat >"$tmpdir/config.toml" <<'EOF'
model = "gpt-5.4"
approval_policy = "on-request"

[projects."/old/project"]
trust_level = "trusted"

[features]
skills = true

[projects."/another/old/project"]
trust_level = "untrusted"

[tui]
theme = "catppuccin-latte"
EOF

cat >"$tmpdir/trusted-projects.toml" <<'EOF'
[projects."/Users/ken/github/codex"]
trust_level = "trusted"

[projects."/Users/ken/.emacs.d"]
trust_level = "trusted"
EOF

cat >"$tmpdir/expected.toml" <<'EOF'
model = "gpt-5.4"
approval_policy = "on-request"

[features]
skills = true

[tui]
theme = "catppuccin-latte"

[projects."/Users/ken/github/codex"]
trust_level = "trusted"

[projects."/Users/ken/.emacs.d"]
trust_level = "trusted"
EOF

bash "$MERGER" "$tmpdir/config.toml" "$tmpdir/trusted-projects.toml"

diff -u "$tmpdir/expected.toml" "$tmpdir/config.toml"

if grep -q '^\[projects\."/old/project"\]' "$tmpdir/config.toml"; then
  echo "old project block was not removed"
  exit 1
fi

if ! grep -q '^\[features\]' "$tmpdir/config.toml"; then
  echo "non-project sections were not preserved"
  exit 1
fi

echo "merge-trusted-projects: PASS"
