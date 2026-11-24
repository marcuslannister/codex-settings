# Hook portability
- Hooks run on macOS (BSD tools, bash 3.2), Linux (GNU tools), and Windows Git Bash. Run `bash hooks/test-hooks.sh` before you commit; CI runs it on all three. Reason: a hook that passes on one system can fail open on another.
- Check a tool with `command -v` before you use it, for example `sd`, `eza`, `fd`, `rg`, and `trash`. Reason: some machines lack them, and the agent then gets `command not found`.
- Call GNU first, then BSD: `stat -c %Y`, then `stat -f %m`. Reason: GNU `stat -f` prints file system data and exits 1.
- Source `lib.sh` in every hook that calls `jq`, and send test input on stdin, not as a `jq --arg` argument. Reason: a native `jq.exe` writes CRLF (`lib.sh` adds `-b`), and MSYS rewrites an argument such as `/usr/bin/git`.
- Codex on Windows runs commands in PowerShell (`pwsh -Command '...'`), so a hook can receive PowerShell syntax. When a hook matches a command, test its PowerShell form too (`git.exe`, `& git`, `Get-ChildItem env:`). Reason: `lib.sh` unwraps the pwsh wrapper, but a bash-only pattern misses the PowerShell spelling.
