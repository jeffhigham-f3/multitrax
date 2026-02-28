# Create commit from staged files

When the user runs this command, create a commit message from the staged files and commit the changes.

## Pre-flight checks (warn, do not block)

1. **Staged files**

    - Run `git status` (or equivalent) to see what is staged.
    - If nothing is staged, **warn** the user: "No files are staged. Stage files with `git add` first, then run this command again." Do not run `git commit`.

2. **Unstaged changes**
    - If there are unstaged changes in addition to staged ones, you may note it briefly; no need to block. The commit will only include staged files.

## Generate commit message

1. **Branch and ticket**

    - Get the current branch name (e.g. `git branch --show-current`).
    - If the branch name contains a Jira-style ticket (e.g. `TCM-281`, `PROJ-123` — pattern like `[A-Z][A-Z0-9]+-\d+`), **always** include that ticket in the commit message.
    - Prefer prefixing the subject with the ticket: `TCM-281: Add log medication button on home screen` (or `[TCM-281] Add log medication button on home screen` if your team uses that format).

2. **Inspect staged changes**

    - Use `git diff --staged` (and optionally `git diff --staged --stat`) to see what is staged.
    - Summarize: which files changed, and the nature of the changes (e.g. "Add LogDoseButton and useLogDoseAction", "Fix Button disabled state", "Update Home screen with medication log entry point").

3. **Commit message format**

    - **Subject line**: Start with the ticket when present (e.g. `TCM-281: Add log medication button on home screen`). One short line (about 50–72 chars), imperative mood. If no ticket in branch, omit the prefix.
    - **Optional body**: If the change set is large or has multiple logical parts, add 1–3 bullet points under the subject, separated by a blank line. You may add "Refs TCM-281" or "Fixes TCM-281" in the body if relevant.

4. **Commit**
    - Run in the project root:
        ```bash
        git commit -m "<subject>" -m "<optional body paragraph(s)>"
        ```
    - Use a single `-m` for subject only, or multiple `-m` for subject + body lines.
    - NOTE: DO NOT PUSH THE COMMIT IMMEDIATELY.

## After committing

-   Print the commit hash (e.g. from `git rev-parse HEAD` or `git log -1 --oneline`).
-   Optionally remind the user to push when ready.
