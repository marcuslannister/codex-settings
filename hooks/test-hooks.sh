#!/bin/bash
# Self-check: feeds each hook a command and asserts the outcome.
# A successful empty response is an allow; nonzero or malformed output is a
# failure, so a crashing hook must not read as safe.
cd "$(dirname "$0")" || exit 1
MODERN=./enforce-modern-cli.sh
fail=0 checks=0

payload() { printf '%s' "$1" | jq -Rsc '{tool_name:"Bash",tool_input:{command:.}}'; } # stdin, not --arg: MSYS rewrites a /usr/bin/... argument for a native jq.exe

# Runs a hook and prints its decision. Codex treats successful empty output as allow.
# HOOK_OS sets OSTYPE for the hook. lib.sh reads PowerShell only on msys or cygwin, so `w check ...`
# runs a check as Windows and `u check ...` as macOS or Linux. A check with neither prefix runs as the host.
hook_decision() {
  local out
  out=$(env ${HOOK_OS:+OSTYPE="$HOOK_OS"} "$1" <<<"$2" 2>/dev/null) || { echo none; return; }
  [ -n "$out" ] || { echo allow; return; }
  jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null <<<"$out" || echo none
}

w() { HOOK_OS=msys "$@"; }
u() { HOOK_OS=linux-gnu "$@"; }

check() { # check <script> <expected: allow|deny> <command>
  checks=$((checks + 1))
  actual=$(hook_decision "./$1" "$(payload "$3")")
  if [ "$actual" != "$2" ]; then
    echo "FAIL $1: expected $2, got $actual for: $3${HOOK_OS:+ [OSTYPE=$HOOK_OS]}"
    fail=$((fail + 1))
  fi
}

decision() { # decision <expected: allow|deny> <command>
  checks=$((checks + 1))
  actual=$(PATH="$tools:$PATH" hook_decision "$MODERN" "$(payload "$2")")
  if [ "$actual" != "$1" ]; then
    echo "FAIL enforce-modern-cli.sh: expected $1, got $actual for: $2${HOOK_OS:+ [OSTYPE=$HOOK_OS]}"
    fail=$((fail + 1))
  fi
}

rewrite() { # rewrite <expected-command> <command>
  checks=$((checks + 1))
  out=$(payload "$2" | PATH="$tools:$PATH" "$MODERN" 2>/dev/null)
  actual=$(jq -r '.hookSpecificOutput.updatedInput.command // empty' <<<"$out")
  if [ "$actual" != "$1" ]; then
    echo "FAIL enforce-modern-cli.sh: expected rewrite $1, got $actual for: $2"
    fail=$((fail + 1))
  fi
}

# enforce-modern-cli.sh rewrites or denies toward a modern tool only when
# `command -v` finds it. $tools holds empty stand-ins for rg, fd, eza, and sd, so
# decision and rewrite do not depend on the machine. $bare holds only what the
# hook runs (jq, dirname, cat) and no modern tool, so classic can test their absence.
fixtures=$(mktemp -d "${TMPDIR:-/tmp}/hooks-fixtures.XXXXXX") || { echo "FAIL: cannot create the fixture folder"; exit 1; }
trap 'rm -rf "$fixtures"' EXIT # later traps repeat this; an empty path above would write to /
tools=$fixtures/tools bare=$fixtures/bare fj=$fixtures/fj
mkdir "$tools" "$bare" "$fj" || { echo "FAIL: cannot create the fixture folders"; exit 1; }
for t in rg fd eza sd; do printf '#!/bin/sh\n' > "$tools/$t"; chmod +x "$tools/$t"; done
for t in jq dirname cat; do printf '#!/bin/sh\nexec "%s" "$@"\n' "$(command -v "$t")" > "$bare/$t"; chmod +x "$bare/$t"; done

classic() { # classic <command>: without the modern tools the hook allows it unchanged
  checks=$((checks + 1))
  out=$(payload "$1" | PATH=$bare "$BASH" "$MODERN" 2>/dev/null) || out=crash
  actual=allow
  [ -z "$out" ] || actual=$(jq -r '.hookSpecificOutput | .permissionDecision + (if .updatedInput then " rewritten" else "" end)' <<<"$out" 2>/dev/null)
  if [ "$actual" != allow ]; then
    echo "FAIL enforce-modern-cli.sh: expected allow unchanged without modern tools, got '$actual' for: $1"
    fail=$((fail + 1))
  fi
}

# A plain `git push` is intentionally allowed: a hook cannot tell an
# authorised ship from an unprompted one. CLAUDE.md governs plain pushes.
# `--force` rewrites published history regardless, so it stays blocked.
check block-git-destructive.sh allow 'git push origin main'
check block-git-destructive.sh deny 'git -C ./repo push --force'
check block-git-destructive.sh deny 'git push -f origin main'
check block-git-destructive.sh deny 'git push --force-with-lease origin main'
# Bundled short flags and forced refspecs also force.
check block-git-destructive.sh deny 'git push -fu origin main'
check block-git-destructive.sh deny 'git push -uf origin main'
check block-git-destructive.sh deny 'git push origin +main'
# A branch/refspec that merely ends in `-f`, or a lease-adjacent option that
# does not by itself force, must not false-positive.
check block-git-destructive.sh allow 'git push origin feature-f'
check block-git-destructive.sh allow 'git push --force-if-includes origin main'
check block-git-destructive.sh deny 'git reset --hard HEAD~1'
check block-git-destructive.sh deny 'git commit -m x --amend'
check block-git-destructive.sh deny 'git rebase main'
check block-git-destructive.sh deny 'git clean -fd'
check block-git-destructive.sh allow 'git status -sb'
check block-git-destructive.sh allow 'git commit -m "fix: no push here"'
# Finishing an authorised rebase, and previewing a clean, are not destructive.
check block-git-destructive.sh allow 'git rebase --continue'
check block-git-destructive.sh allow 'git clean -n'
# `git checkout -- <path>` discards working-tree changes; a branch checkout does not.
check block-git-destructive.sh deny 'git checkout -- .'
check block-git-destructive.sh deny 'git checkout -f main'
check block-git-destructive.sh allow 'git checkout -b feature/x'
check block-git-destructive.sh allow 'git checkout main'
# Prefixes that used to hide the command word.
check block-git-destructive.sh deny '/usr/bin/git clean -fd'
check block-git-destructive.sh deny 'FOO=1 git clean -fd'
check block-git-destructive.sh deny 'if git clean -fd; then echo x; fi'

# A nested shell payload is inspected, not discarded as a string.
check block-git-destructive.sh deny "bash -lc 'git restore .'"
check block-git-destructive.sh deny 'bash -c "git clean -fd"'
check block-git-destructive.sh deny "/bin/sh -c 'git reset --hard'"
check block-git-destructive.sh allow "bash -lc 'git status -sb'"
# An exempt command beside a destructive one does not excuse it.
check block-git-destructive.sh deny 'git clean -fd; git clean -n'
check block-git-destructive.sh deny 'git rebase main; git rebase --continue'
check block-git-destructive.sh deny 'git status && git clean -fd'
check block-git-destructive.sh allow 'git clean -n; git rebase --continue'

# A quoted token still runs: `git 'clean'` is a clean.
check block-git-destructive.sh deny "git 'clean' -fd"
check block-git-destructive.sh deny 'git "reset" --hard'
# Transparent prefixes run the next word as the command.
check block-git-destructive.sh deny 'command git clean -fd'
check block-git-destructive.sh deny 'exec git clean -fd'
check block-git-destructive.sh deny 'env -u GIT_DIR git clean -fd'
check block-git-destructive.sh allow 'env -u GIT_DIR git status'

# PowerShell (Codex on Windows): `git.exe`, the `&` call operator, Windows paths, and a
# `pwsh -Command '...'` wrapper. (Codex sends the inner command; the unwrap is defensive.)
# `w` runs the check as Windows: the PowerShell reading is off elsewhere (see the Unix checks below).
w check block-git-destructive.sh deny 'git.exe reset --hard'
check block-git-destructive.sh deny '& git reset --hard'
w check block-git-destructive.sh deny '& git.exe clean -fd'
w check block-git-destructive.sh deny '.\git.exe clean -fd'
w check block-git-destructive.sh deny 'C:\git\cmd\git.exe restore .'
w check block-git-destructive.sh deny "& 'C:\\Program Files\\Git\\cmd\\git.exe' reset --hard"
w check block-git-destructive.sh deny '& "C:\Program Files\Git\cmd\git.exe" push --force'
w check block-git-destructive.sh deny "pwsh -Command 'git reset --hard HEAD'"
w check block-git-destructive.sh deny '"c:\program files\powershell\7\pwsh.exe" -Command '"'git reset --hard HEAD'"
w check block-git-destructive.sh deny 'powershell.exe -NoProfile -Command "git clean -fd"'
w check block-git-destructive.sh deny "pwsh -NoProfile -ExecutionPolicy Bypass -c 'git status; git clean -fd'"
w check block-git-destructive.sh deny 'PWSH.EXE -command git reset --hard'
w check block-git-destructive.sh deny "pwsh -Command 'Write-Host ''ok''; git restore .'"
w check block-git-destructive.sh allow 'git.exe status -sb'
check block-git-destructive.sh allow '& git status'
w check block-git-destructive.sh allow "& 'C:\\Program Files\\Git\\cmd\\git.exe' status"
w check block-git-destructive.sh allow "pwsh -Command 'git status -sb'"
w check block-git-destructive.sh allow "pwsh -Command 'Write-Host ''git reset --hard'''"
w check block-git-destructive.sh allow "pwsh -Command 'Get-ChildItem C:\\Users'"
check block-git-destructive.sh allow 'pwsh -File .\deploy.ps1'
# Windows ignores case in a command name: `GIT.EXE` is `git`.
w check block-git-destructive.sh deny 'GIT.EXE reset --hard'
w check block-git-destructive.sh deny 'Git.exe clean -fd'
w check block-git-destructive.sh deny 'GIT reset --hard HEAD'
w check block-git-destructive.sh deny '& "C:\Program Files\Git\cmd\GIT.EXE" push --force'
w check block-git-destructive.sh deny "pwsh -Command 'GIT.EXE restore .'"
w check block-git-destructive.sh allow 'GIT.EXE status -sb'
# A quoted path with a reference and a space (`$env:ProgramFiles\Sample Tools`) still names the command,
# and the same command line keeps the references of an output argument for the env check.
w check block-git-destructive.sh deny '& "$env:ProgramFiles\Sample Tools\cmd\git.exe" reset --hard HEAD'
w check block-git-destructive.sh deny '& "${env:ProgramFiles}\Sample Tools\GIT.EXE" push --force'
w check block-git-destructive.sh deny '& "$env:ProgramFiles\Git\cmd\git.exe" reset --hard HEAD'
w check block-git-destructive.sh deny '& "$env:ProgramFiles\Sample Tools\git.exe" reset --hard; Write-Output "token is $env:PATH"'
w check block-git-destructive.sh allow '& "$env:ProgramFiles\Sample Tools\cmd\git.exe" status -sb'
w check block-env-dump.sh deny '& "$env:ProgramFiles\Sample Tools\git.exe" status; Write-Output "token is $env:GH_TOKEN"'
w check block-env-dump.sh allow '& "$env:ProgramFiles\Sample Tools\git.exe" status; Write-Output "token is $env:PATH"'
u check block-git-destructive.sh allow '& "$env:ProgramFiles\Sample Tools\cmd\git.exe" reset --hard HEAD'

check block-env-dump.sh deny 'env'
check block-env-dump.sh deny 'env | rg TOKEN'
check block-env-dump.sh deny 'export -p'
check block-env-dump.sh deny 'printenv'
check block-env-dump.sh allow 'printenv GITHUB_TOKEN'
check block-env-dump.sh allow 'env -u GITHUB_TOKEN gh pr create --body-file ./b'
check block-env-dump.sh allow 'set -euo pipefail'
check block-env-dump.sh allow 'git reset --soft HEAD~1'
# A quoted alternation is text, not a command word.
check block-env-dump.sh allow 'rg -i "cli|env|gh" hooks/'
check block-env-dump.sh deny 'declare -x'
check block-env-dump.sh deny 'typeset -p'
check block-env-dump.sh deny '/usr/bin/env'
# A printed secret value, quoted or not.
check block-env-dump.sh deny 'echo $GITHUB_TOKEN'
check block-env-dump.sh deny 'echo "$ANTHROPIC_API_KEY"'
check block-env-dump.sh deny 'printf "%s" "${MY_SECRET}"'
check block-env-dump.sh allow 'echo $HOME'
check block-env-dump.sh allow 'gh auth status'
check block-env-dump.sh deny "sh -c 'env'"
check block-env-dump.sh deny 'printenv; echo done'
check block-env-dump.sh deny "'env'"
# An option is not a target, so these still dump.
check block-env-dump.sh deny 'env -0'
check block-env-dump.sh deny 'printenv -0'
check block-env-dump.sh deny 'export'
check block-env-dump.sh deny 'declare'
# A named target is a lookup, not a dump.
check block-env-dump.sh allow 'declare -p FOO'
check block-env-dump.sh allow 'export FOO=1'
check block-env-dump.sh allow 'set -x'
# A secret print inside shell control flow.
check block-env-dump.sh deny 'if echo $GITHUB_TOKEN; then :; fi'
check block-env-dump.sh deny 'echo "${GH_TOKEN}"'

# PowerShell: the environment is the `env:` drive and [Environment].
w check block-env-dump.sh deny 'Get-ChildItem env:'
w check block-env-dump.sh deny 'Get-ChildItem Env:\'
w check block-env-dump.sh deny "Get-ChildItem 'Env:\\'"
w check block-env-dump.sh deny 'GCI ENV:'
w check block-env-dump.sh deny 'gci -Path env:'
w check block-env-dump.sh deny 'ls env:'
w check block-env-dump.sh deny 'dir env:'
w check block-env-dump.sh deny 'Get-Item env:*'
w check block-env-dump.sh deny 'gi env:*'
w check block-env-dump.sh deny 'gci env:*TOKEN*'
w check block-env-dump.sh deny "Get-ChildItem env: | Where-Object Name -like '*TOKEN*'"
w check block-env-dump.sh deny '[Environment]::GetEnvironmentVariables()'
w check block-env-dump.sh deny "[System.Environment]::GetEnvironmentVariables('Process')"
w check block-env-dump.sh deny '$e = [Environment]::GetEnvironmentVariables(); $e.Keys'
w check block-env-dump.sh deny "pwsh -Command 'Get-ChildItem env:'"
w check block-env-dump.sh deny "pwsh -Command '[Environment]::GetEnvironmentVariables()'"
w check block-env-dump.sh deny 'echo $env:GITHUB_TOKEN'
w check block-env-dump.sh deny 'Write-Host $env:GITHUB_TOKEN'
w check block-env-dump.sh deny 'write-output ${env:ANTHROPIC_API_KEY}'
w check block-env-dump.sh deny 'Write-Host "$env:MY_SECRET"'
w check block-env-dump.sh deny '$env:GITHUB_TOKEN'
w check block-env-dump.sh deny '$ENV:github_token'
w check block-env-dump.sh deny 'Write-Host hi; $env:GH_TOKEN'
# A named lookup, a plain variable, and ordinary commands stay allowed.
w check block-env-dump.sh allow '$env:PATH'
w check block-env-dump.sh allow 'echo $env:PATH'
w check block-env-dump.sh allow 'Write-Host $env:USERPROFILE'
w check block-env-dump.sh allow 'Get-Item env:PATH'
w check block-env-dump.sh allow 'Get-ChildItem env:GITHUB_TOKEN'
w check block-env-dump.sh allow 'Get-ChildItem C:\Users'
w check block-env-dump.sh allow 'Get-ChildItem'
w check block-env-dump.sh allow "[Environment]::GetEnvironmentVariable('PATH')"
w check block-env-dump.sh allow 'Get-Process | Select-Object -First 3'
w check block-env-dump.sh allow 'Invoke-RestMethod -Headers @{ Authorization = "Bearer $env:GITHUB_TOKEN" } https://example.com'
w check block-env-dump.sh allow "pwsh -Command 'Get-Date'"
w check block-env-dump.sh allow "pwsh -Command 'Write-Host \$env:PATH'"
w check block-env-dump.sh deny 'PRINTENV.EXE'
w check block-env-dump.sh deny 'GET-CHILDITEM ENV:'

# Double quotes expand `$env:NAME` in PowerShell and single quotes do not; a quoted path is still a path.
w check block-env-dump.sh deny 'Write-Output "token is $env:GH_TOKEN"'
w check block-env-dump.sh deny 'Write-Host "Bearer ${env:ANTHROPIC_API_KEY} ok"'
w check block-env-dump.sh deny 'echo "a $env:PATH and $env:GITHUB_TOKEN"'
w check block-env-dump.sh deny 'gci "env:*"'
w check block-env-dump.sh deny "Get-Item 'env:*'"
w check block-env-dump.sh deny 'Get-ChildItem -Path "env:"'
w check block-env-dump.sh allow "Write-Output 'token is \$env:GH_TOKEN'"
w check block-env-dump.sh allow "echo '\$env:EXAMPLE_TOKEN'"
w check block-env-dump.sh allow "printf '\\\$EXAMPLE_TOKEN'"
w check block-env-dump.sh allow 'Write-Output "token is $env:PATH"'
w check block-env-dump.sh allow 'Write-Output "hello world"'
w check block-env-dump.sh allow 'gci "env:PATH"'
w check block-env-dump.sh allow 'Get-ChildItem "C:\Program Files"'
# An assignment sets the variable and prints nothing; a bare reference prints it.
w check block-env-dump.sh allow '$env:API_TOKEN = "x"'
w check block-env-dump.sh allow '$env:API_TOKEN="x"'
w check block-env-dump.sh allow '$env:API_TOKEN += "x"'
w check block-env-dump.sh allow '${env:MY_SECRET} = 1'
w check block-env-dump.sh deny '$env:API_TOKEN'
w check block-env-dump.sh deny '$env:API_TOKEN.Length'
# The pwsh wrapper counts only in command position; as an argument of another command it is text.
w check block-env-dump.sh deny "pwsh -Command 'env'"
w check block-env-dump.sh deny "echo hi; pwsh -Command 'env'"
w check block-env-dump.sh deny "& pwsh -Command 'env'"
w check block-env-dump.sh allow "printf pwsh -Command 'env'"
# A Windows host runs a command name case-insensitively.
w check block-env-dump.sh deny 'ENV'
w check block-env-dump.sh deny 'ls env:'

# On macOS and Linux the same text is Bash, and the hooks decide as they did before the PowerShell
# rules: `env:` is a file name, `ENV` is not `env`, `\$X` and `'$env:X'` are literal text, and
# `pwsh -Command` is not unwrapped. `u` runs each check as Unix, also on a Windows host.
u check block-env-dump.sh allow 'ls env:'
u check block-env-dump.sh allow 'dir env:'
u check block-env-dump.sh allow 'Get-ChildItem env:'
u check block-env-dump.sh allow '[Environment]::GetEnvironmentVariables()'
u check block-env-dump.sh allow 'ENV'
u check block-env-dump.sh allow 'PRINTENV.EXE'
u check block-env-dump.sh allow "echo '\$env:EXAMPLE_TOKEN'"
u check block-env-dump.sh allow "printf '\\\$EXAMPLE_TOKEN'"
u check block-env-dump.sh allow 'echo $env:GITHUB_TOKEN'
u check block-env-dump.sh allow '$env:API_TOKEN'
u check block-env-dump.sh allow "pwsh -Command 'env'"
u check block-env-dump.sh allow "printf pwsh -Command 'env'"
u check block-env-dump.sh deny 'env'
u check block-env-dump.sh deny 'echo $GITHUB_TOKEN'
u check block-git-destructive.sh allow 'GIT.EXE reset --hard'
u check block-git-destructive.sh allow 'git.exe reset --hard'
u check block-git-destructive.sh allow "pwsh -Command 'git reset --hard HEAD'"
u check block-git-destructive.sh deny 'git reset --hard HEAD'
u check gh-json.sh allow 'gh.exe pr view 12'

# Isolate the Anvil probe cache from the real one (/tmp/.anvil-probe-$UID) so
# these checks never race a live Claude Code session's redirect decisions,
# and clean up via trap so an interrupted run can't leave stale state behind.
export ANVIL_PROBE_CACHE
ANVIL_PROBE_CACHE=$(mktemp "${TMPDIR:-/tmp}/anvil-probe-test.XXXXXX")
trap 'rm -f "$ANVIL_PROBE_CACHE"; rm -rf "$fixtures"' EXIT

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
# Downstream pipeline use stays allowed, including the stderr-carrying pipe.
decision allow 'ps aux | grep claude'
decision allow 'cat f | sed s/a/b/'
decision allow 'cat f |& grep x'
# Grouping punctuation must not swallow the pipe that precedes it, and must
# not manufacture an exemption where the preceding operator was not a pipe.
decision allow 'ps aux | (grep x)'
decision deny  'true; (grep foo f)'
decision deny  '(ls)'
decision deny  'ps aux | (true; grep x)'
# `||` and `&&` start a fresh command, so they are not a pipeline exemption.
decision deny  'true || grep foo f'
decision deny  'true && grep foo f'
# Sharing lib.sh closed what the old inline splitter missed: a nested shell
# payload and the transparent `command`/`env` prefixes.
decision deny  "bash -c 'ls -la'"
decision deny  'command ls'
decision deny  'env ls'
# The old script also strips env assignments and leading paths.
decision deny  'FOO=1 ls'
decision deny  '/bin/ls -la'
# A leading shell keyword must not hide the command word.
decision deny  'if ls; then echo x; fi'
decision deny  'while ls; do :; done'
decision deny  '! grep foo f'
decision deny  'if FOO=1 /bin/ls; then :; fi'
decision allow 'if rg foo; then echo x; fi'
# The pwsh wrapper and `.exe` do not hide the command word.
w decision deny  "pwsh -Command 'grep -r foo .'"
w decision deny  '& grep.exe foo f'
w decision allow "pwsh -Command 'rg foo'"
w decision deny  'GREP.EXE -r foo .'

check gh-json.sh deny 'gh pr view 12'
check gh-json.sh deny 'gh -R o/r issue list'
check gh-json.sh deny 'gh api --paginate repos/o/r/issues'
check gh-json.sh allow 'gh pr view 12 --json title,state'
check gh-json.sh allow 'gh pr diff 12'
check gh-json.sh allow 'rg "gh pr view" docs/'
check gh-json.sh deny 'gh release list'
check gh-json.sh deny 'gh search prs --state open'
check gh-json.sh allow 'gh search prs --state open --json number,title'
# A run log has no JSON form, like `gh pr diff`.
check gh-json.sh allow 'gh run view 123 --log'
check gh-json.sh allow 'gh run view 123 --log-failed'
check gh-json.sh allow 'gh pr create --body-file ./b'
# Each gh read is judged on its own.
check gh-json.sh deny 'gh pr view 1; gh pr view 2 --json title'
check gh-json.sh deny 'gh run view 1 --log; gh pr view 2'
check gh-json.sh allow 'gh pr view 1 --json title; gh run view 2 --log'
check gh-json.sh deny "gh pr 'view' 1"
check gh-json.sh deny 'env gh pr view 1'
# Other JSON-capable read families.
check gh-json.sh deny 'gh label list'
check gh-json.sh deny 'gh variable list'
check gh-json.sh deny 'gh secret list'
check gh-json.sh allow 'gh label list --json name'
# PowerShell: `gh.exe` and the pwsh wrapper.
w check gh-json.sh deny 'gh.exe pr view 12'
w check gh-json.sh deny "pwsh -Command 'gh pr view 12'"
w check gh-json.sh allow "pwsh -Command 'gh pr view 12 --json title'"
w check gh-json.sh deny 'GH.EXE pr view 12'

# Without the modern tools on PATH, the classic commands run as typed.
classic 'grep -r foo .'
classic 'ls -la'
classic 'find . -name x'
classic 'sed -i s/a/b/ f'

# Flip the isolated probe cache to 'ok' for the Anvil checks.
REDIRECT=./redirect-to-anvil.sh
echo ok > "$ANVIL_PROBE_CACHE"

redirect_decision() { # redirect_decision <expected: allow|deny> <tool_name> <tool_input-json>
  checks=$((checks + 1))
  actual=$(hook_decision "$REDIRECT" "$(printf '{"tool_name":"%s","tool_input":%s}' "$2" "$3")")
  if [ "$actual" != "$1" ]; then
    echo "FAIL redirect-to-anvil.sh: expected $1, got $actual for: $2 $3${HOOK_OS:+ [OSTYPE=$HOOK_OS]}"
    fail=$((fail + 1))
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
redirect_decision deny  Read '{"file_path":"./x.org"}'
redirect_decision allow Read '{"file_path":"./x.md"}'
redirect_decision allow Bash '{"command":"echo ok; sed -i s/a/b/ f.txt"}'
redirect_decision allow Bash '{"command":"FOO=1 sed -i s/a/b/ f.txt"}'
redirect_decision allow Bash '{"command":"/usr/bin/sed -i s/a/b/ f.txt"}'
# PowerShell: `git.exe` and the pwsh wrapper reach the same redirect.
w redirect_decision deny  Bash '{"command":"git.exe status"}'
w redirect_decision deny  Bash '{"command":"pwsh -Command '"'git status'"'"}'
w redirect_decision allow Bash '{"command":"pwsh -Command '"'git commit -m x'"'"}'

# context-handoff.sh reads the fill from a rollout. A fake rollout has a running
# total far above the fill and a trailing token_count with no info, so a wrong
# field or a null event shows up. TMPDIR is isolated, so the once-per-session
# marker never touches a real session. HERDR_ENV is set and an inherited
# HANDOFF_TOKENS is cleared, so the cases use the default threshold, 360000.
HANDOFF=./context-handoff.sh
handoff_tmp=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test.XXXXXX")
trap 'rm -f "$ANVIL_PROBE_CACHE"; rm -r "$handoff_tmp"; rm -rf "$fixtures"' EXIT

rollout() { # rollout <file> <fill>
  printf '%s\n' '{"type":"session_meta","payload":{}}' \
    "{\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"total_tokens\":9000000},\"last_token_usage\":{\"total_tokens\":$2}}}}" \
    '{"type":"event_msg","payload":{"type":"token_count","info":null}}' > "$1"
}

handoff() { # handoff <expected: warn|none> <session> <transcript> [extra json fields]
  checks=$((checks + 1))
  local out rc=0 want=""
  out=$(printf '{"session_id":"%s","transcript_path":"%s"%s}' "$2" "$3" "${4:-}" |
    TMPDIR=$handoff_tmp "$HANDOFF" 2>/dev/null) || rc=$?
  [ "$1" = warn ] && want="Context fill is ${FILL:-360000} tokens (handoff threshold ${HANDOFF_TOKENS:-360000} tokens). Read $HOME/Projects/agent-scripts/global/rules/handoff.md and hand off now."
  actual=$(jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$out" 2>/dev/null)
  if [ "$rc" != 0 ] || [ "$actual" != "$want" ]; then
    echo "FAIL context-handoff.sh: expected $1 (exit 0), got exit $rc, '$actual' for session $2"
    fail=$((fail + 1))
  fi
}

export HERDR_ENV=1
unset HANDOFF_TOKENS
rollout "$handoff_tmp/below" 359999
rollout "$handoff_tmp/at" 360000
handoff none s-below "$handoff_tmp/below"
FILL=360000 handoff warn s-at "$handoff_tmp/at"
handoff none s-at "$handoff_tmp/at"
HERDR_ENV= handoff none s-no-herdr "$handoff_tmp/at"
# A subagent has its own context, and its call must not use up the main warning.
handoff none s-sub "$handoff_tmp/at" ',"agent_id":"a1"'
FILL=360000 handoff warn s-sub "$handoff_tmp/at"
# More than 1 MiB of other lines after the last count: the hook reads the whole rollout.
rollout "$handoff_tmp/gap" 360000
yes '{"type":"response_item","payload":{"type":"function_call_output"}}' | head -n 20000 >> "$handoff_tmp/gap"
checks=$((checks + 1)); [ "$(wc -c < "$handoff_tmp/gap")" -gt 1048576 ] || { echo "FAIL context-handoff.sh: the gap fixture is under 1 MiB"; fail=$((fail + 1)); }
FILL=360000 handoff warn s-gap "$handoff_tmp/gap"
# HANDOFF_TOKENS overrides the threshold.
rollout "$handoff_tmp/low" 5000
HANDOFF_TOKENS=1000 FILL=5000 handoff warn s-low "$handoff_tmp/low"
# Errors must stay silent: missing rollout, empty rollout, bad threshold.
handoff none s-gone "$handoff_tmp/missing"
: > "$handoff_tmp/empty"
handoff none s-empty "$handoff_tmp/empty"
HANDOFF_TOKENS=abc handoff none s-bad "$handoff_tmp/at"

# format-json.sh must write LF. A native jq.exe on Windows writes CRLF unless lib.sh adds -b.
printf '{"a":1,"b":[2,3]}\n' > "$fj/x.json"
printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$fj/x.json" | ./format-json.sh 2>/dev/null
checks=$((checks + 1))
lines=$(wc -l < "$fj/x.json"); crs=$(tr -cd '\r' < "$fj/x.json" | wc -c)
if [ "$((lines))" -lt 3 ] || [ "$((crs))" -ne 0 ]; then
  echo "FAIL format-json.sh: expected a formatted file with LF only, got $((lines)) lines and $((crs)) CR"
  fail=$((fail + 1))
fi

echo "$((checks - fail)) passed, $fail failed"
exit $((fail > 0))
