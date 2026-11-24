#!/bin/bash
set -euo pipefail
# Blocks environment dumps and printed secret values (AGENTS.MD: secrets).
# The test is whether the command names a target. `printenv NAME` and
# `declare -p NAME` are lookups; `env`, `env -0`, and `declare -x` are dumps.
# The same test holds in PowerShell (Codex on Windows): `$env:NAME` and
# `Get-Item env:NAME` are lookups; `Get-ChildItem env:`, `Get-Item env:*`, and
# `[Environment]::GetEnvironmentVariables()` are dumps.
source "$(dirname "$0")/lib.sh"
read_command "$(cat)"

SECRET_RE='\$\{?[A-Za-z_]*(TOKEN|SECRET|PASSWD|PASSWORD|API_?KEY|CREDENTIAL)'
# PowerShell names are case-insensitive, so these two run on the lower-cased segment.
SECRET_PS='\$\{?env:[a-z_]*(token|secret|passwd|password|api_?key|credential)'
DUMP_PS='\[(system\.)?environment\]::getenvironmentvariables'

deny() {
  guard_deny "Blocked: $1
$2"
}

deny_ps() {
  guard_deny "Blocked: $1
Query the exact variable name only, for example \`\$env:MY_VAR\`, and redact the value."
}

for seg in "${SEGMENTS[@]}"; do
  read -r cmd args <<<"$seg"

  [[ $cmd =~ ^(echo|printf|print|cat|tee)$ && $args =~ $SECRET_RE ]] \
    && deny "printing a secret variable." \
      "Never reveal a secret value, not even an internal one. Use the approved secret tools and redact the output."

  lseg=$(tr '[:upper:]' '[:lower:]' <<<"$seg")
  read -r lcmd largs <<<"$lseg"
  # Printing cmdlets, and a bare `$env:NAME` statement, which prints its value.
  [[ ( $lcmd =~ ^(echo|write-host|write-output|write-information|out-host)$ && $largs =~ $SECRET_PS ) || $lcmd =~ ^$SECRET_PS ]] \
    && deny "printing a secret variable." \
      "Never reveal a secret value, not even an internal one. Use the approved secret tools and redact the output."
  [[ $lseg =~ $DUMP_PS ]] && deny_ps "\`$seg\` dumps the whole environment."
  case $lcmd in
    get-childitem|gci|ls|dir|get-item|gi)
      # `env:` alone, or with a wildcard, lists the variables; `env:NAME` is a lookup.
      set -f
      for w in $largs; do
        [[ $w =~ ^env:[/\\]?(.*)$ ]] || continue
        [[ -z ${BASH_REMATCH[1]} || ${BASH_REMATCH[1]} == *[*?]* ]] && deny_ps "\`$seg\` dumps the whole environment."
      done
      set +f ;;
  esac

  case $cmd in
    env|printenv|export|declare|typeset)
      # An option is not a target: `-0`, `-p`, and `-x` all still dump.
      for w in $args; do [[ $w == -* ]] || continue 2; done ;;
    # `set -euo pipefail` configures the shell. Bare `set` prints everything.
    set) [[ -n $args ]] && continue ;;
    *) continue ;;
  esac

  deny "\`$seg\` dumps the whole environment." \
    "Query the exact variable name only, for example \`printenv MY_VAR\`, and redact the value."
done

guard_allow
