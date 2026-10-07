# Git Cheat Sheet

Student: Om Malviya | Enrollment No: 24BCS10448

Compiled from the links in `session5-git-github/resources.md`:

- https://git-scm.com/cheat-sheet
- https://education.github.com/git-cheat-sheet-education.pdf
- https://www.geeksforgeeks.org/git/git-cheat-sheet/

## 1. Setup

| Command | What it does |
|---|---|
| `git config --global user.name "Om Malviya"` | Set the name recorded in commits |
| `git config --global user.email "me@example.com"` | Set the email recorded in commits |
| `git config --global init.defaultBranch main` | Use `main` as the default branch name |
| `git config --list` | Show the current configuration |
| `git init` / `git init -b main` | Create a new repository in the current folder |
| `git clone <url>` | Download an existing repository |

## 2. Basics (working tree -> staging area -> repository)

| Command | What it does |
|---|---|
| `git status` / `git status --short` | Show modified, staged and untracked files |
| `git add <file>` | Stage one file |
| `git add .` | Stage everything in the current folder (new + modified) |
| `git commit -m "msg"` | Commit only what is staged |
| `git commit -a -m "msg"` | Stage all *modified/deleted tracked* files and commit (does **not** add new untracked files) |
| `git commit --amend` | Rewrite the last commit (message and/or content) |
| `git diff` | Changes in working tree not yet staged |
| `git diff --staged` | Changes staged but not yet committed |
| `git rm <file>` | Delete a file and stage the deletion |
| `git mv <old> <new>` | Rename/move a file and stage it |

## 3. Branching and merging

| Command | What it does |
|---|---|
| `git branch` | List local branches (`-a` includes remote branches) |
| `git branch <name>` | Create a branch |
| `git checkout <name>` / `git switch <name>` | Switch to a branch |
| `git checkout -b <name>` / `git switch -c <name>` | Create and switch in one step |
| `git merge <branch>` | Merge `<branch>` into the current branch |
| `git rebase <branch>` | Replay my commits on top of `<branch>` |
| `git cherry-pick <hash>` | Copy one specific commit onto the current branch |
| `git cherry-pick --abort` / `--continue` | Cancel or continue a cherry-pick after a conflict |
| `git branch -d <name>` | Delete a merged branch (`-D` forces) |
| `git stash` / `git stash pop` | Put uncommitted changes aside and bring them back |

## 4. Remote (GitHub)

| Command | What it does |
|---|---|
| `git remote -v` | List remotes and their URLs |
| `git remote add origin <url>` | Connect the local repo to GitHub |
| `git push -u origin main` | Push and set the upstream for the branch |
| `git push` / `git push origin <branch>` | Upload commits |
| `git fetch` | Download remote changes without merging |
| `git pull` | `fetch` + `merge` of the tracking branch |
| `git pull --rebase` | `fetch` + `rebase` instead of merge |
| `git push origin --delete <branch>` | Delete a remote branch |

## 5. Undo

| Command | What it does |
|---|---|
| `git restore <file>` | Discard unstaged changes in a file (old form: `git checkout -- <file>`) |
| `git restore --staged <file>` | Unstage a file, keep the change in the working tree |
| `git reset --soft HEAD~1` | Undo last commit, keep changes staged |
| `git reset --mixed HEAD~1` | Undo last commit, keep changes unstaged (default) |
| `git reset --hard HEAD~1` | Undo last commit and throw the changes away |
| `git revert <hash>` | Make a new commit that undoes `<hash>` (safe on shared branches) |
| `git clean -fd` | Remove untracked files and directories |
| `git reflog` | History of where HEAD pointed; lets me recover "lost" commits |

## 6. Inspect

| Command | What it does |
|---|---|
| `git log` | Full commit history |
| `git log --oneline` | One line per commit |
| `git log --oneline --graph --all` | Picture of all branches |
| `git log -p <file>` | History of a file with the diffs |
| `git show <hash>` | Show a commit (message + diff) |
| `git show --stat <hash>` | Show a commit with just the list of changed files |
| `git blame <file>` | Who last changed each line |
| `git diff <a> <b>` | Compare two commits/branches |
| `git rev-parse --short HEAD` | Print the current commit hash |

## Quick mental model

```text
working tree --(git add)--> staging area --(git commit)--> local repo --(git push)--> GitHub
     ^                                                        |
     +------------------------(git pull / git fetch + merge)--+
```
