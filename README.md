# OpenAI Codex CLI Settings and Custom Prompts

Configs and custom prompts for [OpenAI Codex CLI](https://github.com/openai/codex).

## Configuration Files

### Main Configuration

- [config.base.toml](config.base.toml):
  - Copy to `config.toml` before local use
  - `config.toml` is ignored: Codex may write absolute paths, trusted projects, marketplace cache, hook state
  - Machine-local MCP servers and runtime state stay in `config.toml`

## Custom Prompts

Stored in `prompts/`. Use via `/prompts:` in Codex.

- `/prompts:diff-review` - Visual review of code changes
- `/prompts:fact-check` - Verify generated docs against code and git history
- `/prompts:generate-slides` - Self-contained HTML slide deck
- `/prompts:generate-visual-plan` - Visual implementation plan
- `/prompts:generate-web-diagram` - Standalone HTML diagram
- `/prompts:plan-review` - Compare plan against current codebase
- `/prompts:project-recap` - Visual recap for context switching

Add a new prompt: drop a `.md` file in `~/.codex/prompts/`, then restart Codex.

## References

- [Codex CLI Official Docs](https://developers.openai.com/codex/cli/)
- [Codex GitHub Repository](https://github.com/openai/codex)

## LICENSE

MIT — see [LICENSE](LICENSE).
