# Changelog

## Unreleased

- Update the Herdr Codex integration version marker from 8 to 10
- Remove unsupported skills and voice transcription feature flags from the shared Codex configuration
- Add a portable Codex Stop hook for Nowledge Mem capture and session-scoped skill outcome reporting
- Standardize safety-hook deny and rewrite responses, allow successful hooks to exit silently, share command parsing with separator data, and add a self-check
- Preserve glob and replacement arguments in modern CLI rewrites
- Add portable installer and reusable safety hooks for Codex
- Point `AGENTS.md` to the tracked generated Codex instructions
- Add agent guidance for domain docs, GitHub issues, and triage labels
- Add the Herdr agent-state hook
- Disable Codex local Memory by default
- Remove the Codex claude-mem plugin
- Refresh shared Codex defaults and feature flags
- Slim README to config + prompts; drop unused alternate `configs/`
