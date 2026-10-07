#!/bin/bash
# practice.sh - short demo of the shell scripting basics from Session 03:
# variables, if/else, for loop, while loop, functions and command-line arguments.
# Usage: ./practice.sh [arg1] [arg2] ...

# ---------- 1. variables ----------
echo "--- 1. Variables ---"
name="Om Malviya"
roll_no="24BCS10448"
today=$(date +%Y-%m-%d)        # command substitution
count=5
echo "Name: $name | Roll no: $roll_no | Today: $today | Count: $count"
echo

# ---------- 2. if / elif / else ----------
echo "--- 2. if / elif / else ---"
age=${AGE:-21}                  # AGE env var or default 21
if [ "$age" -lt 0 ]; then
    echo "Age $age is invalid"
elif [ "$age" -lt 13 ]; then
    echo "Age $age: child"
elif [ "$age" -lt 20 ]; then
    echo "Age $age: teenager"
else
    echo "Age $age: adult"
fi
echo

# ---------- 3. for loop ----------
echo "--- 3. for loop ---"
for i in 1 2 3; do
    echo "for iteration $i"
done
for file in /etc/hosts /etc/passwd; do
    echo "$file has $(wc -l < "$file" | tr -d ' ') lines"
done
echo

# ---------- 4. while loop ----------
echo "--- 4. while loop ---"
n=1
while [ "$n" -le "$count" ]; do
    echo "while iteration $n"
    n=$((n + 1))
done
echo

# ---------- 5. functions ----------
echo "--- 5. functions ---"
greet() {
    echo "Hello, $1! Welcome to DevOps."
}
add() {
    echo $(( $1 + $2 ))
}
greet "$name"
sum=$(add 7 8)
echo "add 7 8 = $sum"
echo

# ---------- 6. command-line arguments ----------
echo "--- 6. command-line arguments ---"
echo "Script name (\$0)     : $0"
echo "Number of args (\$#)  : $#"
if [ "$#" -eq 0 ]; then
    echo "No arguments given. Try: ./practice.sh hello world"
else
    echo "First argument (\$1) : $1"
    echo "All arguments (\$@)  : $@"
    i=1
    for arg in "$@"; do
        echo "  arg $i = $arg"
        i=$((i + 1))
    done
fi
