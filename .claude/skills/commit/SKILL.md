---
name: commit
description: Stage and commit changes following project conventions.
disable-model-invocation: true
argument-hint: [path] [message]
---

Stage and commit the specified path (or all changes if no path given) with a short, lowercase commit message.

1. Show what will be committed:
   ```bash
   git status
   git diff --stat $ARGUMENTS
   ```

2. Stage the files:
   ```bash
   git add $ARGUMENTS
   ```

3. Confirm what is staged, then commit with a concise message that describes the change. Follow the style of recent commits (`git log --oneline -5`). Use lowercase, no period at end.

4. Run `git status` after committing to confirm it succeeded.

Do not push. Do not amend existing commits.
