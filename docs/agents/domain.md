# Domain Docs

This repo uses a single-context domain-doc layout.

## Before exploring, read these

- `CONTEXT.md` at the repo root, if present.
- `docs/adr/`, if present, for architectural decisions relevant to the task.

If these files do not exist, proceed silently. Do not ask to create them upfront; domain-modeling skills can create them lazily when terms or decisions are actually resolved.

## Expected file structure

```text
/
|-- CONTEXT.md
|-- docs/adr/
`-- ...
```

## Use the glossary's vocabulary

When output names a domain concept, use the term as defined in `CONTEXT.md`. If the concept is missing, note the gap instead of inventing new project language.

## Flag ADR conflicts

If output contradicts an existing ADR, surface the conflict explicitly rather than silently overriding it.
