# Create GitHub pull request

When the user runs this command, create a pull request with `gh pr create` as follows.

## Pre-flight checks (warn, do not block)

1. **Current branch**

    - Detect the current branch (e.g. `git branch --show-current`).
    - If the branch is the repository default (e.g. `main` or `develop`), **warn** the user: "You are on the default branch. PRs should usually be opened from a feature branch. Create and switch to a feature branch first, or confirm you want to proceed."
    - Only proceed after the user confirms or after they are on a non-default branch.

2. **Unpushed commits**

    - If there are commits that are not pushed to the remote (e.g. compare with upstream), **warn**: "You have unpushed commits. The PR will not include them until you push. Push first, or confirm to create the PR anyway."
    - Proceed based on user response.

3. **Uncommitted changes**

    - If there are uncommitted changes, **warn**: "You have uncommitted changes. They will not be part of the PR. Commit and push them first, or confirm to create the PR with current commits only."

## PR content (template + Cursor-generated body)

1. **Template**

    - If the repo has a pull request template, use it as the structure:
        - Look for: `.github/pull_request_template.md`, `.github/PULL_REQUEST_TEMPLATE.md`, or `docs/pull_request_template.md`.
    - If none exists, use a minimal standard structure: Summary, Changes, Testing/QA notes, Issue reference (e.g. "Fixes #...").

2. **Generate body from branch work**

    - Using the current branch and its commits/diffs against the **default branch** (e.g. `main` or `develop`):
        - Summarize what changed (files, features, fixes).
        - Propose a short PR **title** (e.g. from branch name or main change).
        - Fill in the template sections with concrete, professional content (no placeholders).
    - If the branch name or commits reference an issue (e.g. `TCM-278`, `#123`), include "Fixes #123" or "Relates to #123" in the body.

3. **Write body to a temp file**

    - Write the generated body to a temporary file (e.g. `/tmp/pr-body.md` or a project-local temp file).
    - Use this file with `gh pr create --body-file <path>`.

## Run `gh pr create`

Run in the project root:

```bash
gh pr create --title "<generated or user-confirmed title>" --body-file <path-to-generated-body>
```

-   Do **not** use `--draft` (PR should be ready for review).
-   Omit `--base` so the repo default branch is used, unless the user specifies a different base.
-   If the user has specified reviewers or assignees, add `--reviewer` / `--assignee @me` (or as specified).

## After creating

-   Output the PR URL from `gh pr create`.
-   Remove the `/tmp/pr-body.md` file you created during this session.
-   Optionally remind the user to push if there were unpushed commits and they chose to create anyway.
