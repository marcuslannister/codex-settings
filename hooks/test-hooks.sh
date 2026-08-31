#!/bin/bash
# Self-check: feeds each hook a command and asserts the outcome.
# The exit-2 hooks live here; the modern-CLI rule is enforced by the repo's own
# hooks/enforce-modern-cli.sh, which answers with a permissionDecision instead.
cd "$(dirname "$0")" || exit 1
MODERN=./enforce-modern-cli.sh
fail=0

payload() { printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(jq -Rn --arg c "$1" '$c')"; }

check() { # check <script> <expected-exit> <command>
  actual=$(payload "$3" | "./$1" >/dev/null 2>&1; echo $?)
  if [ "$actual" != "$2" ]; then
    echo "FAIL $1: expected exit $2, got $actual for: $3"
    fail=1
  fi
}

decision() { # decision <expected: allow|deny> <command>
  out=$(payload "$2" | "$MODERN" 2>/dev/null)
  # No output at all means the hook stayed silent, which permits the command.
  actual=allow
  [ -n "$out" ] && actual=$(jq -r '.hookSpecificOutput.permissionDecision' <<<"$out")
  if [ "$actual" != "$1" ]; then
    echo "FAIL enforce-modern-cli.sh: expected $1, got $actual for: $2"
    fail=1
  fi
}

rewrite() { # rewrite <expected-command> <command>
  out=$(payload "$2" | "$MODERN" 2>/dev/null)
  actual=$(jq -r '.hookSpecificOutput.updatedInput.command // empty' <<<"$out")
  if [ "$actual" != "$1" ]; then
    echo "FAIL enforce-modern-cli.sh: expected rewrite $1, got $actual for: $2"
    fail=1
  fi
}

# A plain `git push` is intentionally allowed: a hook cannot tell an
# authorised ship from an unprompted one. CLAUDE.md governs plain pushes.
# `--force` rewrites published history regardless, so it stays blocked.
check block-git-destructive.sh 0 'git push origin main'
check block-git-destructive.sh 2 'git -C /tmp/repo push --force'
check block-git-destructive.sh 2 'git push -f origin main'
check block-git-destructive.sh 2 'git push --force-with-lease origin main'
# Bundled short flags and forced refspecs also force.
check block-git-destructive.sh 2 'git push -fu origin main'
check block-git-destructive.sh 2 'git push -uf origin main'
check block-git-destructive.sh 2 'git push origin +main'
# A branch/refspec that merely ends in `-f`, or a lease-adjacent option that
# does not by itself force, must not false-positive.
check block-git-destructive.sh 0 'git push origin feature-f'
check block-git-destructive.sh 0 'git push --force-if-includes origin main'
check block-git-destructive.sh 2 'git reset --hard HEAD~1'
check block-git-destructive.sh 2 'git commit -m x --amend'
check block-git-destructive.sh 2 'git rebase main'
check block-git-destructive.sh 2 'git clean -fd'
check block-git-destructive.sh 0 'git status -sb'
check block-git-destructive.sh 0 'git commit -m "fix: no push here"'
# Finishing an authorised rebase, and previewing a clean, are not destructive.
check block-git-destructive.sh 0 'git rebase --continue'
check block-git-destructive.sh 0 'git clean -n'
# `git checkout -- <path>` discards working-tree changes; a branch checkout does not.
check block-git-destructive.sh 2 'git checkout -- .'
check block-git-destructive.sh 2 'git checkout -f main'
check block-git-destructive.sh 0 'git checkout -b feature/x'
check block-git-destructive.sh 0 'git checkout main'
# Prefixes that used to hide the command word.
check block-git-destructive.sh 2 '/usr/bin/git clean -fd'
check block-git-destructive.sh 2 'FOO=1 git clean -fd'
check block-git-destructive.sh 2 'if git clean -fd; then echo x; fi'

# A nested shell payload is inspected, not discarded as a string.
check block-git-destructive.sh 2 "bash -lc 'git restore .'"
check block-git-destructive.sh 2 'bash -c "git clean -fd"'
check block-git-destructive.sh 2 "/bin/sh -c 'git reset --hard'"
check block-git-destructive.sh 0 "bash -lc 'git status -sb'"
# An exempt command beside a destructive one does not excuse it.
check block-git-destructive.sh 2 'git clean -fd; git clean -n'
check block-git-destructive.sh 2 'git rebase main; git rebase --continue'
check block-git-destructive.sh 2 'git status && git clean -fd'
check block-git-destructive.sh 0 'git clean -n; git rebase --continue'

# A quoted token still runs: `git 'clean'` is a clean.
check block-git-destructive.sh 2 "git 'clean' -fd"
check block-git-destructive.sh 2 'git "reset" --hard'
# Transparent prefixes run the next word as the command.
check block-git-destructive.sh 2 'command git clean -fd'
check block-git-destructive.sh 2 'exec git clean -fd'
check block-git-destructive.sh 2 'env -u GIT_DIR git clean -fd'
check block-git-destructive.sh 0 'env -u GIT_DIR git status'

check block-env-dump.sh 2 'env'
check block-env-dump.sh 2 'env | rg TOKEN'
check block-env-dump.sh 2 'export -p'
check block-env-dump.sh 2 'printenv'
check block-env-dump.sh 0 'printenv GITHUB_TOKEN'
check block-env-dump.sh 0 'env -u GITHUB_TOKEN gh pr create --body-file /tmp/b'
check block-env-dump.sh 0 'set -euo pipefail'
check block-env-dump.sh 0 'git reset --soft HEAD~1'
# A quoted alternation is text, not a command word.
check block-env-dump.sh 0 'rg -i "cli|env|gh" hooks/'
check block-env-dump.sh 2 'declare -x'
check block-env-dump.sh 2 'typeset -p'
check block-env-dump.sh 2 '/usr/bin/env'
# A printed secret value, quoted or not.
check block-env-dump.sh 2 'echo $GITHUB_TOKEN'
check block-env-dump.sh 2 'echo "$ANTHROPIC_API_KEY"'
check block-env-dump.sh 2 'printf "%s" "${MY_SECRET}"'
check block-env-dump.sh 0 'echo $HOME'
check block-env-dump.sh 0 'gh auth status'
check block-env-dump.sh 2 "sh -c 'env'"
check block-env-dump.sh 2 'printenv; echo done'
check block-env-dump.sh 2 "'env'"
# An option is not a target, so these still dump.
check block-env-dump.sh 2 'env -0'
check block-env-dump.sh 2 'printenv -0'
check block-env-dump.sh 2 'export'
check block-env-dump.sh 2 'declare'
# A named target is a lookup, not a dump.
check block-env-dump.sh 0 'declare -p FOO'
check block-env-dump.sh 0 'export FOO=1'
check block-env-dump.sh 0 'set -x'
# A secret print inside shell control flow.
check block-env-dump.sh 2 'if echo $GITHUB_TOKEN; then :; fi'
check block-env-dump.sh 2 'echo "${GH_TOKEN}"'

# Isolate the Anvil probe cache from the real one (/tmp/.anvil-probe-$UID) so
# these checks never race a live Claude Code session's redirect decisions,
# and clean up via trap so an interrupted run can't leave stale state behind.
export ANVIL_PROBE_CACHE
ANVIL_PROBE_CACHE=$(mktemp "${TMPDIR:-/tmp}/anvil-probe-test.XXXXXX")
trap 'rm -f "$ANVIL_PROBE_CACHE"' EXIT

# The modern-CLI hook now owns exact `find` and `sed -i` rewrites.
echo no > "$ANVIL_PROBE_CACHE"

decision deny  'grep -r foo .'
decision deny  'ls'
rewrite 'fd --glob x .' 'find . -name x'
rewrite "fd --glob '*.ts' src" "find src -name '*.ts'"
decision allow 'find . -maxdepth 3'
decision allow 'find . -inum 42'
decision allow 'find . -exec rm {} ;'
rewrite "sd 'a' 'b' f" 'sed -i s/a/b/ f'
rewrite "sd 'a' 'b' f" "sed -i 's/a/b/' f"
decision allow 'sed -i s/a/b/g f'
decision allow 'git grep foo'
decision allow 'rg foo'
# Downstream pipeline use stays allowed.
decision allow 'ps aux | grep claude'
decision allow 'cat f | sed s/a/b/'
# The old script also strips env assignments and leading paths.
decision deny  'FOO=1 ls'
decision deny  '/bin/ls -la'
# A leading shell keyword must not hide the command word.
decision deny  'if ls; then echo x; fi'
decision deny  'while ls; do :; done'
decision deny  '! grep foo f'
decision deny  'if FOO=1 /bin/ls; then :; fi'
decision allow 'if rg foo; then echo x; fi'

check gh-json.sh 2 'gh pr view 12'
check gh-json.sh 2 'gh -R o/r issue list'
check gh-json.sh 2 'gh api --paginate repos/o/r/issues'
check gh-json.sh 0 'gh pr view 12 --json title,state'
check gh-json.sh 0 'gh pr diff 12'
check gh-json.sh 0 'rg "gh pr view" docs/'
check gh-json.sh 2 'gh release list'
check gh-json.sh 2 'gh search prs --state open'
check gh-json.sh 0 'gh search prs --state open --json number,title'
# A run log has no JSON form, like `gh pr diff`.
check gh-json.sh 0 'gh run view 123 --log'
check gh-json.sh 0 'gh run view 123 --log-failed'
check gh-json.sh 0 'gh pr create --body-file /tmp/b'
# Each gh read is judged on its own.
check gh-json.sh 2 'gh pr view 1; gh pr view 2 --json title'
check gh-json.sh 2 'gh run view 1 --log; gh pr view 2'
check gh-json.sh 0 'gh pr view 1 --json title; gh run view 2 --log'
check gh-json.sh 2 "gh pr 'view' 1"
check gh-json.sh 2 'env gh pr view 1'
# Other JSON-capable read families.
check gh-json.sh 2 'gh label list'
check gh-json.sh 2 'gh variable list'
check gh-json.sh 2 'gh secret list'
check gh-json.sh 0 'gh label list --json name'

# Flip the isolated probe cache to 'ok' for the Anvil checks.
REDIRECT=./redirect-to-anvil.sh
echo ok > "$ANVIL_PROBE_CACHE"

redirect_decision() { # redirect_decision <expected: allow|deny> <tool_name> <tool_input-json>
  out=$(printf '{"tool_name":"%s","tool_input":%s}' "$2" "$3" | "$REDIRECT" 2>/dev/null)
  actual=allow
  [ -n "$out" ] && actual=$(jq -r '.hookSpecificOutput.permissionDecision' <<<"$out")
  if [ "$actual" != "$1" ]; then
    echo "FAIL redirect-to-anvil.sh: expected $1, got $actual for: $2 $3"
    fail=1
  fi
}

redirect_decision deny  Bash '{"command":"git status"}'
redirect_decision allow Bash '{"command":"git push origin main"}'
redirect_decision deny  Bash '{"command":"curl https://example.com"}'
redirect_decision deny  Bash '{"command":"curl -I https://example.com"}'
redirect_decision allow Bash '{"command":"curl -X POST https://example.com -d foo"}'
# Flags placed after the URL must still be scanned, not just token 2.
redirect_decision allow Bash '{"command":"curl https://example.com --head -o out.html"}'
redirect_decision allow Bash '{"command":"curl https://example.com -X POST -d foo"}'
redirect_decision allow Bash '{"command":"sed -i s/a/b/ f.txt"}'
redirect_decision allow Bash '{"command":"sed -n 1,5p f.txt"}'
redirect_decision deny  Read '{"file_path":"/tmp/x.org"}'
redirect_decision allow Read '{"file_path":"/tmp/x.md"}'
redirect_decision allow Bash '{"command":"echo ok; sed -i s/a/b/ f.txt"}'
redirect_decision allow Bash '{"command":"FOO=1 sed -i s/a/b/ f.txt"}'
redirect_decision allow Bash '{"command":"/usr/bin/sed -i s/a/b/ f.txt"}'

[ "$fail" = 0 ] && echo "all hook checks passed"
exit "$fail"
