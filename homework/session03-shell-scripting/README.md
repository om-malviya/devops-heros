# Session 03 – Shell Scripting

Student: Om Malviya | Enrollment No: 24BCS10448

## Task: System Information Script

Create a shell script that:

- Prints the current date.
- Prints the hostname.
- Prints the username.
- Prints the disk usage.
- Prints the running processes.
- Uses variables to store and use data.
- Takes user input using `read -p`.
- Creates a directory using `mkdir`.
- Creates a file using `touch`.
- Stores the running processes information in the file using `>` output redirection.

Commands to use: `mkdir`, `touch`, `echo`, `df`, `ps`, `read -p`, variables, `>` output redirection.

### How each requirement is covered in `system-info.sh`

| Requirement | Where in the script |
|---|---|
| Current date | `current_date=$(date)` then `echo "1. Current date  : $current_date"` |
| Hostname | `host_name=$(hostname)` |
| Username | `user_name=$(whoami)` |
| Disk usage | `df -h` |
| Running processes | `ps aux \| head -n 10` on screen, full `ps aux` in the file |
| Variables | `current_date`, `host_name`, `user_name`, `output_dir`, `process_file`, `name`, `roll_no`, `comment` |
| User input with `read -p` | `read -p "Enter your name: " name` (plus roll number and comment) |
| Directory with `mkdir` | `mkdir -p "$output_dir"` (`./output`) |
| File with `touch` | `touch "$process_file"` (`./output/process.log`) |
| `>` redirection | `ps aux > "$process_file"` and `echo "..." > "$info_file"` |

I added two small extras so the script can also run unattended (useful for a CI job or for grading):
`./system-info.sh --non-interactive` skips the prompts and uses default values, and when stdin is
not a terminal (for example answers piped in with `printf`) empty answers fall back to the defaults.

### The script

```bash
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
```

### Making it executable and running it

```bash
cd homework/session03-shell-scripting
chmod +x system-info.sh practice.sh
printf 'Om Malviya\n24BCS10448\nTesting\n' | ./system-info.sh
```

Output (captured 2026-10-07). The `ps aux` lines are very long on macOS, so in this README (and in
`sample-process.log`) each process line is cut at 100 characters and marked with `...`; the file
`output/process.log` written by the script contains the full lines.

```text
===== SYSTEM INFORMATION SCRIPT =====

[stdin is not a terminal: reading answers from input, defaults used for blanks]

My name is Om Malviya
My roll number is 24BCS10448
My comment is: Testing

1. Current date  : Wed Oct  7 22:27:31 IST 2026
2. Hostname      : Oms-MacBook-Air-3.local
3. Username      : ommalviya

4. Disk usage (df -h):
Filesystem                                           Size    Used   Avail Capacity iused ifree %iused  Mounted on
/dev/disk3s1s1                                      228Gi    11Gi    44Gi    21%    453k  460M    0%   /
devfs                                               215Ki   215Ki     0Bi   100%     742     0  100%   /dev
/dev/disk3s6                                        228Gi   7.0Gi    44Gi    14%       7  460M    0%   /System/Volumes/VM
/dev/disk3s2                                        228Gi   9.3Gi    44Gi    18%    2.0k  460M    0%   /System/Volumes/Preboot
/dev/disk3s4                                        228Gi   3.3Mi    44Gi     1%      64  460M    0%   /System/Volumes/Update
/dev/disk1s2                                        500Mi   6.0Mi   482Mi     2%       1  4.9M    0%   /System/Volumes/xarts
/dev/disk1s1                                        500Mi   6.0Mi   482Mi     2%      36  4.9M    0%   /System/Volumes/iSCPreboot
/dev/disk1s3                                        500Mi   1.5Mi   482Mi     1%      98  4.9M    0%   /System/Volumes/Hardware
/dev/disk3s5                                        228Gi   154Gi    44Gi    78%    1.7M  460M    0%   /System/Volumes/Data
map auto_home                                         0Bi     0Bi     0Bi   100%       0     0     -   /System/Volumes/Data/home
/Users/ommalviya/Downloads/Visual Studio Code.app   228Gi   149Gi    53Gi    74%    1.6M  555M    0%   /private/var/folders/h4/bvjjnzzs5jz7f9pgctf2gjdm0000gn/T/AppTranslocation/70CC1F55-8FB5-4BD8-9EFF-C2F8F4832357
/dev/disk4s2                                         95Mi    28Mi    67Mi    30%     516  4.3G    0%   /Volumes/SafeExamBrowser-3.7

5. Running processes (ps aux | head -n 10):
USER               PID  %CPU %MEM      VSZ    RSS   TT  STAT STARTED      TIME COMMAND
_windowserver      166  18.5  0.5 437196320  75776   ??  Ss   22Sep26 898:31.11 /System/Library/Priv ...
ommalviya        21678  18.3  3.3 1951423392 555536   ??  S    11:23AM  16:22.14 /Applications/Googl ...
ommalviya         2734  17.4  1.7 1890647392 292784   ??  S    Tue07PM   3:14.76 /private/var/folder ...
root             42809  12.9  0.2 435357696  34048   ??  Ss   10:15PM   0:03.00 /System/Library/Priv ...
ommalviya        43012  10.7  2.0 440983664 334848   ??  S    10:15PM   0:30.40 /Users/ommalviya/.vs ...
ommalviya         1385  10.0  0.7 489035696 118064   ??  S    22Sep26 291:44.44 /Applications/Google ...
ommalviya        48166   6.1  0.4 411587152  59584   ??  S    10:27PM   0:00.35 /Library/Frameworks/ ...
root                98   4.9  0.0 435332320   5952   ??  Ss   22Sep26  18:53.20 /System/Library/Fram ...
root               134   4.3  0.0 435363616   7760   ??  Ss   22Sep26  10:10.88 /usr/libexec/opendir ...

6. Creating directory './output' with mkdir -p
7. Creating file './output/process.log' with touch
8. Storing running processes in the file with > redirection

9. Verification:
   Files in ./output:
total 424
-rw-r--r--@ 1 ommalviya  staff   207K Oct  7 22:27 process.log
-rw-r--r--@ 1 ommalviya  staff   234B Oct  7 22:27 system-info.txt
   Line count of ./output/process.log: 582
   Size of ./output/process.log      : 208K

   Contents of ./output/system-info.txt:
Report generated on : Wed Oct  7 22:27:31 IST 2026
Hostname            : Oms-MacBook-Air-3.local
Username            : ommalviya
Student name        : Om Malviya
Roll number         : 24BCS10448
Comment             : Testing

Done.
```

Interactive run (what the prompts look like when typing in a terminal; the answers are the same
as the ones piped in above):

```text
Enter your name: Om Malviya
Enter your roll number: 24BCS10448
Enter your comment: Testing
```

Second run with `--non-interactive` (no prompts, defaults used), only the first lines shown:

```bash
./system-info.sh --non-interactive | head -n 10
```

Output (captured 2026-10-07)

```text
===== SYSTEM INFORMATION SCRIPT =====

[non-interactive mode: using default values]

My name is Om Malviya
My roll number is 24BCS10448
My comment is: Shell scripting homework

1. Current date  : Wed Oct  7 22:27:31 IST 2026
2. Hostname      : Oms-MacBook-Air-3.local
```

### Checking the file that was created with `>`

```bash
ls -lh output/
wc -l output/process.log
head -n 15 output/process.log | cut -c1-100 > sample-process.log
```

Output (captured 2026-10-07)

```text
total 432
-rw-r--r--@ 1 ommalviya  staff   208K Oct  7 22:27 process.log
-rw-r--r--@ 1 ommalviya  staff   251B Oct  7 22:27 system-info.txt
     587 output/process.log
```

The `output/` directory is listed in this folder's `.gitignore` because its content changes on every
run and is machine specific. `sample-process.log` (first 15 lines of a real `process.log`, lines cut
at 100 characters) is committed instead so the result of the `>` redirection is visible in the repo.

## Practice script: `practice.sh`

Based on the course examples in `session3-shell-scripting/` (`variable.sh`, `condition.sh`, `loop.sh`,
`while_loop1.sh`, `function.sh`), this script demonstrates variables, `if/elif/else`, a `for` loop,
a `while` loop, functions and command-line arguments in one place. It takes no keyboard input so it
runs unattended.

```bash
./practice.sh hello world
```

Output (captured 2026-10-07)

```text
--- 1. Variables ---
Name: Om Malviya | Roll no: 24BCS10448 | Today: 2026-10-07 | Count: 5

--- 2. if / elif / else ---
Age 21: adult

--- 3. for loop ---
for iteration 1
for iteration 2
for iteration 3
/etc/hosts has 9 lines
/etc/passwd has 142 lines

--- 4. while loop ---
while iteration 1
while iteration 2
while iteration 3
while iteration 4
while iteration 5

--- 5. functions ---
Hello, Om Malviya! Welcome to DevOps.
add 7 8 = 15

--- 6. command-line arguments ---
Script name ($0)     : ./practice.sh
Number of args ($#)  : 2
First argument ($1) : hello
All arguments ($@)  : hello world
  arg 1 = hello
  arg 2 = world
```

## What I learned

- A variable is assigned with `name=value` (no spaces) and read with `$name`; `$(command)` stores the
  output of a command in a variable (`current_date=$(date)`).
- `read -p "prompt" var` prints the prompt and stores the typed line in `var`. If stdin is a pipe it
  still works, it just reads the next line from the pipe. `${var:-default}` gives a fallback value.
- `mkdir -p` does not fail if the directory already exists, so the script can be run many times.
- `touch` creates an empty file (or updates the timestamp of an existing one).
- `>` replaces the content of a file with the command output; `>>` appends. `ps aux > process.log`
  therefore puts the whole process list in the file and shows nothing on screen.
- `df -h` shows disk usage in human readable units; `ps aux` shows all processes of all users.
- `[ -t 0 ]` is true only when stdin is a terminal, which is how the script knows whether it is being
  run by a person or by another program.

## Screenshots

Terminal output blocks in this README stand in for screenshots:

- `printf ... | ./system-info.sh` block -> screenshot of the script run with user input.
- `./system-info.sh --non-interactive` block -> screenshot of the unattended run.
- `ls -lh output/` / `wc -l` block -> screenshot proving the directory and file were created and filled.
- `./practice.sh hello world` block -> screenshot of the practice script.

## Submission

The public GitHub repository for this homework is this repository (`devops-heros`); this task lives in
`homework/session03-shell-scripting/`.

## Deliverables

- `system-info.sh` – the required System Information Script (date, hostname, user, `df -h`, `ps`, variables, `read -p`, `mkdir -p`, `touch`, `>`).
- `practice.sh` – demo of variables, if/else, for, while, functions and command-line arguments.
- `sample-process.log` – first 15 lines (cut at 100 chars) of a real `output/process.log` produced by the script.
- `.gitignore` – ignores the generated `output/` directory.
- `README.md` – this file, with the captured command output.
