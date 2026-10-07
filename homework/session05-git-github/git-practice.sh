#!/bin/bash
# git-practice.sh - Session 05 homework, reproducible demo of:
#   Task 1: git commit -m  vs  git commit -a -m
#   Task 2: git cherry-pick
# Everything happens in a throwaway repository (default: $TMPDIR/git-practice), never in this repo.
# Usage: ./git-practice.sh [work-dir]
set -e

WORK_DIR="${1:-${TMPDIR:-/tmp}/git-practice}"

# print the command, then run it (so the output is self-documenting)
run() {
    echo "\$ $*"
    "$@"
    echo
}

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
echo "Working in: $(pwd)"
echo

echo "################ SETUP ################"
run git init -b main
run git config user.name "Om Malviya"
run git config user.email "om.malviya@example.com"

echo "################ TASK 1: git commit -m vs git commit -a -m ################"
echo "--- 1a. first commit of a tracked file ---"
echo "line 1" > notes.txt
run git add notes.txt
run git commit -m "Add notes.txt"

echo "--- 1b. modify the tracked file, then try 'git commit -m' WITHOUT git add ---"
echo "line 2" >> notes.txt
run git status --short
echo "\$ git commit -m \"Try commit without staging\""
git commit -m "Try commit without staging" || echo "(exit code $? -> nothing was committed)"
echo
run git log --oneline

echo "--- 1c. same modified file, now 'git commit -a -m' (stages + commits tracked changes) ---"
run git commit -a -m "Commit modified notes.txt with -a"
run git log --oneline
run git status --short

echo "--- 1d. -a does NOT pick up NEW untracked files ---"
echo "line 3" >> notes.txt          # modified tracked file
echo "I am new" > new.txt           # brand new, untracked file
run git status --short
run git commit -a -m "Commit with -a while an untracked file exists"
run git status --short
run git show --stat --oneline HEAD

echo "--- 1e. untracked files need git add first ---"
run git add new.txt
run git commit -m "Add new.txt after explicit git add"
run git log --oneline

echo "################ TASK 2: git cherry-pick ################"
echo "--- 2a. 3 commits on main ---"
echo "app v1" >  app.txt; git add app.txt; git commit -q -m "main commit 1: app v1"
echo "app v2" >> app.txt; git commit -q -a -m "main commit 2: app v2"
echo "app v3" >> app.txt; git commit -q -a -m "main commit 3: app v3"
run git log --oneline main

echo "--- 2b. create branch 'feature' and make 3 commits there ---"
run git checkout -b feature
echo "feature work 1" >  feature.txt;   git add feature.txt;   git commit -q -m "feature commit 1: start feature.txt"
echo "hotfix: important bug fix" > hotfix.txt; git add hotfix.txt; git commit -q -m "feature commit 2: add hotfix.txt"
echo "feature work 3" >> feature.txt;   git commit -q -a -m "feature commit 3: more feature work"
run git log --oneline feature

echo "--- 2c. identify the commit to cherry-pick (2nd commit on feature) ---"
PICK=$(git rev-parse --short feature~1)
echo "Selected commit: $PICK  ($(git log -1 --format=%s "$PICK"))"
echo

echo "--- 2d. switch back to main and cherry-pick it ---"
run git checkout main
run ls
run git cherry-pick "$PICK"

echo "--- 2e. verify on main ---"
run git log --oneline main
run git show --stat --oneline HEAD
run ls
run cat hotfix.txt
echo "\$ git log --oneline --graph --all"
git log --oneline --graph --all
echo
echo "Note: the cherry-picked commit on main has a NEW hash ($(git rev-parse --short HEAD)),"
echo "      the original on feature is still $PICK. feature.txt is NOT on main."
