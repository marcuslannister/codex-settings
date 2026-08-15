# Issue tracker: GitHub

Issues and PRDs for this repo live as GitHub issues. Use the `gh` CLI for all operations.

Repo: `marcuslannister/codex-settings` (`origin`). `upstream` is `feiskyer/codex-settings`.

## Pull requests as a triage surface

PRs as a request surface: no.

Do not include external PRs in the normal triage queue unless this file is updated.

## Common operations

- Create: `gh issue create --title "..." --body-file <path>`
- Read: `gh issue view <number> --comments --json number,title,body,state,labels,comments,author,url`
- List: `gh issue list --state open --json number,title,state,labels,author,url`
- Comment: `gh issue comment <number> --body-file <path>`
- Label: `gh issue edit <number> --add-label "..."`
- Close: `gh issue close <number>`

When a skill says "publish to the issue tracker", create a GitHub issue.

When a skill says "fetch the relevant ticket", run `gh issue view <number> --comments --json number,title,body,state,labels,comments,author,url`.
