#!/bin/bash
# system-info.sh - Session 03 homework: System Information Script
# Prints date, hostname, username, disk usage and running processes,
# takes user input with read -p, creates a directory and a file,
# and stores the running processes in the file using > redirection.
#
# Usage:
#   ./system-info.sh                   # interactive (asks name, roll number, comment)
#   ./system-info.sh --non-interactive # uses default values, no prompts
#   printf 'Name\nRoll\nComment\n' | ./system-info.sh   # answers piped in

set -u

# ---------- variables ----------
current_date=$(date)
host_name=$(hostname)
user_name=$(whoami)
output_dir="./output"
process_file="$output_dir/process.log"
info_file="$output_dir/system-info.txt"

# default values used when no input is given
default_name="Om Malviya"
default_roll="24BCS10448"
default_comment="Shell scripting homework"

non_interactive="no"
if [ "${1:-}" = "--non-interactive" ]; then
    non_interactive="yes"
fi

echo "===== SYSTEM INFORMATION SCRIPT ====="
echo

# ---------- user input ----------
if [ "$non_interactive" = "yes" ]; then
    echo "[non-interactive mode: using default values]"
    name="$default_name"
    roll_no="$default_roll"
    comment="$default_comment"
else
    if [ ! -t 0 ]; then
        echo "[stdin is not a terminal: reading answers from input, defaults used for blanks]"
    fi
    read -p "Enter your name: " name
    read -p "Enter your roll number: " roll_no
    read -p "Enter your comment: " comment
    # fall back to defaults if the user (or the pipe) gave nothing
    name="${name:-$default_name}"
    roll_no="${roll_no:-$default_roll}"
    comment="${comment:-$default_comment}"
fi
echo

echo "My name is $name"
echo "My roll number is $roll_no"
echo "My comment is: $comment"
echo

# ---------- basic system info ----------
echo "1. Current date  : $current_date"
echo "2. Hostname      : $host_name"
echo "3. Username      : $user_name"
echo

echo "4. Disk usage (df -h):"
df -h
echo

echo "5. Running processes (ps aux | head -n 10):"
ps aux | head -n 10
echo

# ---------- directory + file + redirection ----------
echo "6. Creating directory '$output_dir' with mkdir -p"
mkdir -p "$output_dir"

echo "7. Creating file '$process_file' with touch"
touch "$process_file"

echo "8. Storing running processes in the file with > redirection"
ps aux > "$process_file"

# also write a small summary file using > and >>
echo "Report generated on : $current_date" >  "$info_file"
echo "Hostname            : $host_name"     >> "$info_file"
echo "Username            : $user_name"     >> "$info_file"
echo "Student name        : $name"          >> "$info_file"
echo "Roll number         : $roll_no"       >> "$info_file"
echo "Comment             : $comment"       >> "$info_file"
echo

# ---------- verification ----------
echo "9. Verification:"
echo "   Files in $output_dir:"
ls -lh "$output_dir"
echo "   Line count of $process_file: $(wc -l < "$process_file" | tr -d ' ')"
echo "   Size of $process_file      : $(du -h "$process_file" | cut -f1)"
echo
echo "   Contents of $info_file:"
cat "$info_file"
echo
echo "Done."
