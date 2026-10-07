# Session 05 – Git & GitHub

Student: Om Malviya | Enrollment No: 24BCS10448

Both tasks were performed for real in a throwaway repository created by `git-practice.sh` (in this
folder). The script prints every command before running it (`$ ...`), so the blocks below are the
exact terminal output of one run. To reproduce:

```bash
cd homework/session05-git-github
chmod +x git-practice.sh
./git-practice.sh            # uses $TMPDIR/git-practice, or pass your own empty folder as argument
```

The only edit made to the captured output is that the long absolute temp path of the throwaway repo
is shortened to `<work-dir>`.

## Task 1: git commit -a -m

- Practice `git commit -a -m "message"`.
- Understand the difference between `git commit -a -m` and `git commit -m`.
- Test both commands and observe the difference.

### Commands (from `git-practice.sh`)

```bash
git init -b main
git config user.name "Om Malviya"
git config user.email "om.malviya@example.com"

# 1a. first commit of a tracked file
echo "line 1" > notes.txt
git add notes.txt
git commit -m "Add notes.txt"

# 1b. modify the tracked file, then commit WITHOUT git add
echo "line 2" >> notes.txt
git status --short
git commit -m "Try commit without staging"      # -> nothing committed
git log --oneline

# 1c. same modified file, now with -a
git commit -a -m "Commit modified notes.txt with -a"
git log --oneline
git status --short

# 1d. -a does NOT pick up new untracked files
echo "line 3" >> notes.txt
echo "I am new" > new.txt
git status --short
git commit -a -m "Commit with -a while an untracked file exists"
git status --short
git show --stat --oneline HEAD

# 1e. untracked files need git add first
git add new.txt
git commit -m "Add new.txt after explicit git add"
git log --oneline
```

Output (captured 2026-10-07)

```text
Working in: <work-dir>

################ SETUP ################
$ git init -b main
Initialized empty Git repository in <work-dir>/.git/

$ git config user.name Om Malviya

$ git config user.email om.malviya@example.com

################ TASK 1: git commit -m vs git commit -a -m ################
--- 1a. first commit of a tracked file ---
$ git add notes.txt

$ git commit -m Add notes.txt
[main (root-commit) 632dd4f] Add notes.txt
 1 file changed, 1 insertion(+)
 create mode 100644 notes.txt

--- 1b. modify the tracked file, then try 'git commit -m' WITHOUT git add ---
$ git status --short
 M notes.txt

$ git commit -m "Try commit without staging"
On branch main
Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
	modified:   notes.txt

no changes added to commit (use "git add" and/or "git commit -a")
(exit code 1 -> nothing was committed)

$ git log --oneline
632dd4f Add notes.txt

--- 1c. same modified file, now 'git commit -a -m' (stages + commits tracked changes) ---
$ git commit -a -m Commit modified notes.txt with -a
[main 47da4f2] Commit modified notes.txt with -a
 1 file changed, 1 insertion(+)

$ git log --oneline
47da4f2 Commit modified notes.txt with -a
632dd4f Add notes.txt

$ git status --short

--- 1d. -a does NOT pick up NEW untracked files ---
$ git status --short
 M notes.txt
?? new.txt

$ git commit -a -m Commit with -a while an untracked file exists
[main 9d429cd] Commit with -a while an untracked file exists
 1 file changed, 1 insertion(+)

$ git status --short
?? new.txt

$ git show --stat --oneline HEAD
9d429cd Commit with -a while an untracked file exists
 notes.txt | 1 +
 1 file changed, 1 insertion(+)

--- 1e. untracked files need git add first ---
$ git add new.txt

$ git commit -m Add new.txt after explicit git add
[main 66cdcbb] Add new.txt after explicit git add
 1 file changed, 1 insertion(+)
 create mode 100644 new.txt

$ git log --oneline
66cdcbb Add new.txt after explicit git add
9d429cd Commit with -a while an untracked file exists
47da4f2 Commit modified notes.txt with -a
632dd4f Add notes.txt

```

### What I observed

| | `git commit -m "msg"` | `git commit -a -m "msg"` |
|---|---|---|
| Modified tracked file, not staged | Nothing is committed. Git prints "no changes added to commit" and exits with code 1 (step 1b). | The file is staged automatically and committed (steps 1c, 1d). |
| New untracked file | Not committed (it was never added). | Still **not** committed. `git status` keeps showing `?? new.txt` (step 1d). |
| Already staged changes | Committed. | Committed (plus any other modified tracked files). |

So `-a` is a shortcut for "`git add` every file Git already tracks that was modified or deleted,
then commit". It saves a step when I only edited existing files, but a brand-new file always needs an
explicit `git add` (step 1e). I also noticed that `-a` commits *all* modified tracked files at once,
so if I want a small, focused commit it is safer to `git add` the specific files and use plain
`git commit -m`.

## Task 2: Git Cherry-Pick

- Create 2–4 commits in the main branch.
- Use `git log` to view the commits.
- Create a new branch.
- Make 2–3 commits in the new branch.
- Use `git log` to identify a specific commit.
- Cherry-pick one specific commit from the new branch into the main branch.
- Verify that the selected commit/change is now available in the main branch.

### Commands (from `git-practice.sh`)

```bash
# 2a. 3 commits on main
echo "app v1" >  app.txt; git add app.txt; git commit -m "main commit 1: app v1"
echo "app v2" >> app.txt; git commit -a -m "main commit 2: app v2"
echo "app v3" >> app.txt; git commit -a -m "main commit 3: app v3"
git log --oneline main

# 2b. new branch with 3 commits
git checkout -b feature
echo "feature work 1" > feature.txt;          git add feature.txt; git commit -m "feature commit 1: start feature.txt"
echo "hotfix: important bug fix" > hotfix.txt; git add hotfix.txt;  git commit -m "feature commit 2: add hotfix.txt"
echo "feature work 3" >> feature.txt;         git commit -a -m "feature commit 3: more feature work"
git log --oneline feature

# 2c. identify the 2nd feature commit (feature~1 = one before the tip)
git rev-parse --short feature~1

# 2d. cherry-pick it into main
git checkout main
ls
git cherry-pick ec3eb14

# 2e. verify
git log --oneline main
git show --stat --oneline HEAD
ls
cat hotfix.txt
git log --oneline --graph --all
```

Output (captured 2026-10-07)

```text
################ TASK 2: git cherry-pick ################
--- 2a. 3 commits on main ---
$ git log --oneline main
e4c276d main commit 3: app v3
d95e250 main commit 2: app v2
627f3d6 main commit 1: app v1
66cdcbb Add new.txt after explicit git add
9d429cd Commit with -a while an untracked file exists
47da4f2 Commit modified notes.txt with -a
632dd4f Add notes.txt

--- 2b. create branch 'feature' and make 3 commits there ---
$ git checkout -b feature
Switched to a new branch 'feature'

$ git log --oneline feature
9de58a1 feature commit 3: more feature work
ec3eb14 feature commit 2: add hotfix.txt
19de7f1 feature commit 1: start feature.txt
e4c276d main commit 3: app v3
d95e250 main commit 2: app v2
627f3d6 main commit 1: app v1
66cdcbb Add new.txt after explicit git add
9d429cd Commit with -a while an untracked file exists
47da4f2 Commit modified notes.txt with -a
632dd4f Add notes.txt

--- 2c. identify the commit to cherry-pick (2nd commit on feature) ---
Selected commit: ec3eb14  (feature commit 2: add hotfix.txt)

--- 2d. switch back to main and cherry-pick it ---
$ git checkout main
Switched to branch 'main'

$ ls
app.txt
new.txt
notes.txt

$ git cherry-pick ec3eb14
[main a33d5ce] feature commit 2: add hotfix.txt
 Date: Wed Oct 7 22:28:57 2026 +0530
 1 file changed, 1 insertion(+)
 create mode 100644 hotfix.txt

--- 2e. verify on main ---
$ git log --oneline main
a33d5ce feature commit 2: add hotfix.txt
e4c276d main commit 3: app v3
d95e250 main commit 2: app v2
627f3d6 main commit 1: app v1
66cdcbb Add new.txt after explicit git add
9d429cd Commit with -a while an untracked file exists
47da4f2 Commit modified notes.txt with -a
632dd4f Add notes.txt

$ git show --stat --oneline HEAD
a33d5ce feature commit 2: add hotfix.txt
 hotfix.txt | 1 +
 1 file changed, 1 insertion(+)

$ ls
app.txt
hotfix.txt
new.txt
notes.txt

$ cat hotfix.txt
hotfix: important bug fix

$ git log --oneline --graph --all
* 9de58a1 feature commit 3: more feature work
* ec3eb14 feature commit 2: add hotfix.txt
* 19de7f1 feature commit 1: start feature.txt
| * a33d5ce feature commit 2: add hotfix.txt
|/  
* e4c276d main commit 3: app v3
* d95e250 main commit 2: app v2
* 627f3d6 main commit 1: app v1
* 66cdcbb Add new.txt after explicit git add
* 9d429cd Commit with -a while an untracked file exists
* 47da4f2 Commit modified notes.txt with -a
* 632dd4f Add notes.txt

Note: the cherry-picked commit on main has a NEW hash (a33d5ce),
      the original on feature is still ec3eb14. feature.txt is NOT on main.
```

### What cherry-pick does and when to use it

`git cherry-pick <hash>` takes the *change* introduced by one commit and applies it as a new commit on
the branch I am currently on. In the run above, commit `ec3eb14` ("feature commit 2: add hotfix.txt")
was copied from `feature` onto `main`. Three things prove it worked:

1. `git log --oneline main` now shows "feature commit 2: add hotfix.txt" on top of main.
2. `git show --stat HEAD` lists exactly one file, `hotfix.txt`, and `cat hotfix.txt` prints its content.
3. `ls` on main shows `hotfix.txt` but **not** `feature.txt`: commits 1 and 3 from `feature` were
   not brought over, only the one I selected.

The copied commit has a new hash (`a33d5ce` instead of `ec3eb14`) because a commit hash also includes the
parent commit and the timestamp. The original commit on `feature` is untouched, which is why the
`--graph` view shows the same message twice on two different branches.

When I would use it:

- Backport a bug fix from a development branch to a release/production branch without merging the
  unfinished features that are on the same branch (exactly the hotfix scenario above).
- Rescue a single good commit from a branch that is going to be abandoned.
- Pick a commit that was accidentally made on the wrong branch and move it to the right one
  (cherry-pick it there, then remove it from the wrong branch).

When not to use it: to bring over a whole branch, `git merge` or `git rebase` is the right tool,
because cherry-picking many commits one by one creates duplicates that make later merges confusing.
If a cherry-pick conflicts, I fix the files, `git add` them and run `git cherry-pick --continue`
(or `git cherry-pick --abort` to cancel).

## Screenshots

The captured terminal output blocks in this README are the substitute for screenshots:

- Task 1 output block -> screenshots of `git status`, the failed `git commit -m`, the successful
  `git commit -a -m`, and `git log --oneline` before/after.
- Task 2 output block -> screenshots of `git log --oneline main`, `git log --oneline feature`,
  `git cherry-pick ec3eb14`, `git show --stat`, `cat hotfix.txt` and `git log --graph --all`.

## Deliverables

- `git-practice.sh` – reproducible script that performs Task 1 and Task 2 in a throwaway repository and prints every command with its output.
- `README.md` – this file: both tasks restated, exact commands, captured output and explanations.
- `git-cheatsheet.md` – the most useful Git commands grouped by setup, basics, branching, remote, undo and inspect (based on `session5-git-github/resources.md`).
