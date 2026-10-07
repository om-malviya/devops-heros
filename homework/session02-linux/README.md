# Session 02 – Linux
Student: Om Malviya | Enrollment No: 24BCS10448

Environment used for the hands-on parts: macOS (Darwin 25.2, arm64) with the BSD userland for Task 1
and the cheat-sheet practice, and an Ubuntu 24.04 LTS VM (arm64, systemd; the Colima VM on the same
laptop, reached with `colima ssh`) for everything that only exists on Linux: `adduser`, `useradd`,
`journalctl`, `systemctl`, `apt`, `free`, `ss`, `ip`, `lsblk`, `dmesg`. Every output block was really
executed and is labelled `Output (captured 2026-10-07)` or `Output (captured 2026-10-07, Ubuntu 24.04 VM)`;
the only `Expected output` left is the cross-filesystem hard link in Task 1, which this single-volume
laptop cannot demonstrate. Scratch files were created under a throw-away directory shown as
`/tmp/links-demo` and `/tmp/cheatsheet-practice`.

## Task 1: Soft Link & Hard Link

### Difference between soft links and hard links

| | Hard link | Soft (symbolic) link |
|---|---|---|
| What it is | A second directory entry pointing at the **same inode** (same data blocks) | A small special file whose content is the **path** of the target |
| Command | `ln target linkname` | `ln -s target linkname` |
| Inode number | Identical to the original | Its own, different inode |
| `ls -l` type char | `-` (looks like a normal file) | `l`, shown as `name -> target` |
| Link count (`stat %l`) | Increments on the original (2, 3, …) | Stays 1 on both |
| Delete the original | Data survives; the hard link still opens it | Link becomes **dangling** ("No such file or directory") |
| Across filesystems/partitions | Not allowed (inodes are per-filesystem) | Allowed (it is just a path) |
| Directories | Not allowed (`ln: mydir: Is a directory`) | Allowed |
| Size | Same as the file | Length of the target path (e.g. 12 bytes for `original.txt`) |
| Typical use | Keep a file alive under two names, deduplicate backups (rsync `--link-dest`) | `/usr/bin/python3 -> python3.12`, `current -> release-42`, dotfile repos |

### Commands to create both

```bash
ln  original.txt hard.txt      # hard link
ln -s original.txt soft.txt    # soft (symbolic) link
ls -li                         # -i prints the inode number
stat -f '%i links=%l %Sp %z bytes %N' original.txt hard.txt soft.txt   # macOS stat; Linux: stat -c '%i %h %A %s %n'
readlink soft.txt              # where does the symlink point
```

### Practice: creating, using and deleting links

```bash
cd /tmp/links-demo
echo "hello links" > original.txt
ln original.txt hard.txt
ln -s original.txt soft.txt
ls -li
stat -f '%i links=%l %Sp %z bytes %N' original.txt hard.txt soft.txt
readlink soft.txt
```

```text
Output (captured 2026-10-07)
$ ls -li
total 16
45107481 -rw-r--r--@ 2 om  wheel  12 Oct  7 22:28 hard.txt
45107481 -rw-r--r--@ 2 om  wheel  12 Oct  7 22:28 original.txt
45107484 lrwxr-xr-x@ 1 om  wheel  12 Oct  7 22:28 soft.txt -> original.txt

$ stat -f '%i links=%l %Sp %z bytes %N' original.txt hard.txt soft.txt
45107481 links=2 -rw-r--r-- 12 bytes original.txt
45107481 links=2 -rw-r--r-- 12 bytes hard.txt
45107484 links=1 lrwxr-xr-x 12 bytes soft.txt

$ readlink soft.txt
original.txt
```

I observed that `original.txt` and `hard.txt` share inode `45107481` and the link count is 2, while
`soft.txt` has its own inode `45107484`, mode `lrwxr-xr-x`, and its "size" (12 bytes) is just the
length of the string `original.txt`.

Writing through either link changes the same data:

```bash
echo "line 2 via hard link" >> hard.txt && cat original.txt
echo "line 3 via soft link" >> soft.txt && cat original.txt
```

```text
Output (captured 2026-10-07)
hello links
line 2 via hard link

hello links
line 2 via hard link
line 3 via soft link
```

Now delete the source file and observe:

```bash
rm original.txt
ls -li
cat hard.txt
cat soft.txt
```

```text
Output (captured 2026-10-07)
$ ls -li
total 8
45107481 -rw-r--r--@ 1 om  wheel  54 Oct  7 22:28 hard.txt
45107484 lrwxr-xr-x@ 1 om  wheel  12 Oct  7 22:28 soft.txt -> original.txt

$ cat hard.txt
hello links
line 2 via hard link
line 3 via soft link

$ cat soft.txt
cat: soft.txt: No such file or directory
```

After `rm original.txt` the link count on inode 45107481 dropped from 2 to 1 and the data is still fully
readable through `hard.txt`. The soft link still *exists* (`ls` shows it) but is dangling: it points at a
path that no longer resolves.

Edge cases I tested:

```bash
ln -s /nonexistent/file dangling.txt; ls -l dangling.txt; cat dangling.txt   # symlink to nothing is allowed
mkdir mydir && ln -s mydir dirlink && ls -ld mydir dirlink                    # symlink to a directory works
ln mydir dirhard                                                              # hard link to a directory is refused
```

```text
Output (captured 2026-10-07)
lrwxr-xr-x@ 1 om  wheel  17 Oct  7 22:28 dangling.txt -> /nonexistent/file
cat: dangling.txt: No such file or directory

lrwxr-xr-x@ 1 om  wheel   5 Oct  7 22:28 dirlink -> mydir
drwxr-xr-x@ 2 om  wheel  64 Oct  7 22:28 mydir

ln: mydir: Is a directory
```

Deleting links (a link is removed with plain `rm`; never put a trailing `/` on a directory symlink or you
delete the contents, not the link):

```bash
rm soft.txt dangling.txt dirlink && ls -li
rm hard.txt && rmdir mydir && ls -la
```

```text
Output (captured 2026-10-07)
total 8
45107481 -rw-r--r--@ 1 om  wheel  54 Oct  7 22:28 hard.txt
45107486 drwxr-xr-x@ 2 om  wheel  64 Oct  7 22:28 mydir

total 0
drwxr-xr-x@  2 om  wheel   64 Oct  7 22:28 .
drwx------@ 24 om  wheel  768 Oct  7 22:28 ..
```

Hard link across filesystems (could not be demonstrated on this single-volume machine):

```bash
ln /home/om/file.txt /mnt/usb/file.txt
```

```text
Expected output
ln: failed to create hard link '/mnt/usb/file.txt' => '/home/om/file.txt': Invalid cross-device link
```

### Interview-style Q&A

**Q1. What is the difference between a hard link and a soft link?**
A hard link is another name for the same inode, so the file has two equal entries and survives until the
last name is removed. A soft link is a separate file that stores a path; if the target is deleted or
moved, the link breaks.

**Q2. How do you tell them apart with `ls`?**
`ls -li`: hard links share the inode number and the link count is > 1; soft links have type `l` and show
`name -> target`.

**Q3. What happens to a hard link / soft link when the original file is deleted?**
Hard link: nothing, data is intact (link count decrements). Soft link: it dangles and reading it gives
"No such file or directory".

**Q4. Can you hard-link a directory or a file on another partition?**
No for both. Directory hard links would create loops in the tree and are refused (`Is a directory`);
inodes are per-filesystem so cross-device hard links fail with `Invalid cross-device link`. Soft links can
do both.

**Q5. How do you find all hard links of a file?**
`find / -samefile file.txt` or `find / -inum <inode>`.

**Q6. Does a hard link take extra disk space?**
No, only a directory entry. A symlink uses one inode plus the path bytes.

**Q7. Why does the link count of an empty directory start at 2?**
One for its name in the parent and one for its own `.` entry; each subdirectory's `..` adds another.

**Q8. Where do you see symlinks in real DevOps work?**
`/etc/alternatives`, `/usr/bin/python3 -> python3.12`, systemd `multi-user.target.wants/*.service`
(enabling a service *is* creating a symlink), `current -> releases/2026-10-07` for zero-downtime deploys.

## Task 2: adduser vs useradd

### Difference

| | `useradd` | `adduser` |
|---|---|---|
| What | Low-level binary from the `shadow-utils`/`passwd` package, exists on every Linux | Debian/Ubuntu Perl wrapper around `useradd` (`/usr/sbin/adduser`), config in `/etc/adduser.conf` |
| Style | Non-interactive; does nothing you don't ask for | Interactive; asks for password and GECOS (full name, room, phone) |
| Home directory | Only with `-m`; shell defaults to `/bin/sh` (or `/etc/default/useradd`) | Created automatically, skeleton copied from `/etc/skel`, shell `/bin/bash` |
| Password | Not set; you must run `passwd` separately | Prompted during creation |
| Group | Depends on `USERGROUPS_ENAB` in `/etc/login.defs` | Always creates a matching private group |
| On RHEL/CentOS/Fedora | The real command | `adduser` is just a symlink to `useradd` |
| Best for | Scripts, cloud-init, Dockerfiles, Ansible (deterministic flags) | Humans at a terminal on Ubuntu/Debian |

**Which is preferred on Ubuntu and why:** `adduser`. Ubuntu's own docs recommend it because it is
"friendly": one command creates the user, the private group, the home directory with skeleton files,
sets a bash shell and a password, and respects the distro policy in `/etc/adduser.conf`. With
`useradd` it is easy to forget `-m -s /bin/bash` and end up with a user that has no home directory and
drops into `sh`. In automation I would still use `useradd` with explicit flags (or Ansible's `user`
module) because it never prompts.

### Hands-on: both commands on a real Ubuntu 24.04 VM

I ran these inside the Colima VM on this laptop (`colima ssh`, Ubuntu 24.04.4 LTS, arm64, systemd).
The VM is non-interactive, so for `adduser` I passed `--disabled-password --gecos "Test User"`
(this skips the password and "Full Name/Room/Phone" prompts; everything else is identical to the
interactive run).

First the low-level `useradd` with no flags, to see what you get "for free":

```bash
sudo useradd testuser2
ls /home
getent passwd testuser2
id testuser2
ls -la /home/testuser2
grep -E "^(CREATE_HOME|USERGROUPS_ENAB)" /etc/login.defs; grep ^SHELL /etc/default/useradd
```

```text
Output (captured 2026-10-07, Ubuntu 24.04 VM)
$ ls /home
ommalviya.guest
ommalviya.linux
$ getent passwd testuser2
testuser2:x:1000:1001::/home/testuser2:/bin/sh
$ id testuser2
uid=1000(testuser2) gid=1001(testuser2) groups=1001(testuser2)
$ ls -la /home/testuser2
ls: cannot access '/home/testuser2': No such file or directory
$ grep ...
USERGROUPS_ENAB yes
SHELL=/bin/sh
```

I observed that `useradd` created the account and (because `USERGROUPS_ENAB yes`) a private group,
but **no home directory** (`/home` is unchanged, `/home/testuser2` does not exist even though
`/etc/passwd` claims it), no GECOS, and the shell is `/bin/sh`. The account also has no password
yet. On this VM the first free UID was 1000 because the Colima login user is UID 501.

Now the Debian wrapper, `adduser`:

```bash
sudo adduser --disabled-password --gecos "Test User" testuser   # interactive form: sudo adduser testuser
id testuser
getent passwd testuser
getent group testuser
sudo ls -la /home/testuser
ls -la /etc/skel
sudo usermod -aG sudo testuser && groups testuser
```

```text
Output (captured 2026-10-07, Ubuntu 24.04 VM)
info: Adding user `testuser' ...
info: Selecting UID/GID from range 1000 to 59999 ...
info: Adding new group `testuser' (1002) ...
info: Adding new user `testuser' (1002) with group `testuser (1002)' ...
info: Creating home directory `/home/testuser' ...
info: Copying files from `/etc/skel' ...
info: Adding new user `testuser' to supplemental / extra groups `users' ...
info: Adding user `testuser' to group `users' ...

$ id testuser
uid=1002(testuser) gid=1002(testuser) groups=1002(testuser),100(users)
$ getent passwd testuser
testuser:x:1002:1002:Test User,,,:/home/testuser:/bin/bash
$ getent group testuser
testuser:x:1002:
$ sudo ls -la /home/testuser
total 20
drwxr-x--- 2 testuser testuser 4096 Oct  7 22:42 .
drwxr-xr-x 4 root     root     4096 Oct  7 22:42 ..
-rw-r--r-- 1 testuser testuser  220 Oct  7 22:42 .bash_logout
-rw-r--r-- 1 testuser testuser 3771 Oct  7 22:42 .bashrc
-rw-r--r-- 1 testuser testuser  807 Oct  7 22:42 .profile
$ ls -la /etc/skel
total 20
drwxr-xr-x  2 root root 4096 May 21 16:49 .
drwxr-xr-x 74 root root 4096 Oct  7 22:42 ..
-rw-r--r--  1 root root  220 Mar 31  2024 .bash_logout
-rw-r--r--  1 root root 3771 Mar 31  2024 .bashrc
-rw-r--r--  1 root root  807 Mar 31  2024 .profile
$ groups testuser
testuser : testuser sudo users
```

One command did everything: private group `testuser` (1002), home `/home/testuser` with mode
`drwxr-x---` (that is why I needed `sudo` to list it), the three skeleton files copied from
`/etc/skel`, GECOS `Test User,,,`, shell `/bin/bash`, and on Ubuntu 24.04 it also adds the user to
the `users` group. In interactive use it would additionally prompt for the password; with
`--disabled-password` the account exists but cannot log in with a password until `sudo passwd testuser`.

To get the same result from `useradd` I have to spell every flag out:

```bash
sudo useradd -m -s /bin/bash -c "Test User Two" testuser3
getent passwd testuser3
sudo ls -la /home/testuser3
```

```text
Output (captured 2026-10-07, Ubuntu 24.04 VM)
testuser3:x:1003:1003:Test User Two:/home/testuser3:/bin/bash
total 20
drwxr-x--- 2 testuser3 testuser3 4096 Oct  7 22:43 .
drwxr-xr-x 5 root      root      4096 Oct  7 22:43 ..
-rw-r--r-- 1 testuser3 testuser3  220 Mar 31  2024 .bash_logout
-rw-r--r-- 1 testuser3 testuser3 3771 Mar 31  2024 .bashrc
-rw-r--r-- 1 testuser3 testuser3  807 Mar 31  2024 .profile
```

(`-m` creates the home and copies `/etc/skel`; `-s` sets bash; `-c` sets the comment/GECOS.)

Clean up all three:

```bash
sudo userdel -r testuser3                # low-level
sudo userdel -r testuser2                # low-level (no home existed)
sudo deluser --remove-home testuser      # Debian wrapper
ls /home; getent passwd testuser testuser2 testuser3; echo "exit=$?"
```

```text
Output (captured 2026-10-07, Ubuntu 24.04 VM)
userdel: testuser3 mail spool (/var/mail/testuser3) not found
userdel: testuser2 mail spool (/var/mail/testuser2) not found
userdel: testuser2 home directory (/home/testuser2) not found
info: Looking for files to backup/remove ...
info: Removing files ...
warn: `/usr/bin/crontab' not executed. Skipping crontab removal. Package `cron' required.
info: Removing user `testuser' ...
ommalviya.guest
ommalviya.linux
exit=2
```

`getent` exit code 2 means "not found", so all three accounts and `/home/testuser` are gone. The
`userdel -r` warnings about the mail spool are harmless (no MTA installed); the warning for
`testuser2` confirms once more that `useradd` never created its home directory.

macOS note: neither command exists on the host; users are managed through Directory Services
(`sysadminctl -addUser`, `dscl`). I ran the read-only equivalent to confirm:

```bash
which adduser useradd; dscl . -list /Users | grep -v '^_' | head -5
```

```text
Output (captured 2026-10-07)
adduser not found
useradd not found
daemon
nobody
om
root
```

## Task 3: journalctl

### What it is used for

`journalctl` queries the **systemd journal**, the binary, indexed log store that `systemd-journald`
collects from the kernel, early boot, stdout/stderr of every service, and syslog. Because every entry
carries metadata (unit name, PID, priority, boot ID, timestamp) I can filter precisely instead of
grepping flat files in `/var/log`. Logs live in `/run/log/journal` (volatile) or `/var/log/journal`
(persistent, if the directory exists / `Storage=persistent` in `/etc/systemd/journald.conf`).

### Viewing system and service logs

| Command | Purpose |
|---|---|
| `journalctl` | Whole journal, oldest first, paged with `less` |
| `journalctl -e` / `-n 50` | Jump to end / last 50 lines |
| `journalctl -f` | Follow live, like `tail -f` |
| `journalctl -xe` | Last entries with explanatory help text (first thing to run after a service fails) |
| `journalctl -b` / `-b -1` | This boot / previous boot |
| `journalctl -k` | Kernel messages only (`dmesg` equivalent) |
| `journalctl -p err` | Priority error and worse (`emerg alert crit err warning notice info debug`) |
| `journalctl --since "1 hour ago"` / `--since today --until "10:00"` | Time windows |
| `journalctl -u nginx` | One service (unit) |
| `journalctl -u nginx -f` | Follow one service |
| `journalctl _PID=1234` / `_UID=1000` | Filter by field |
| `journalctl -o json-pretty` | Structured output for scripts |
| `journalctl --disk-usage` / `--vacuum-size=200M` | Size and cleanup |
| `journalctl --list-boots` | Boot IDs available |

### Hands-on on the Ubuntu 24.04 VM

The Colima VM runs systemd, so I used it for the real `journalctl` practice (my user is in the
`systemd-journal` group, so no `sudo` is needed). nginx is not installed there; the services that
*are* running and worth looking at are `docker.service`, `k3s.service` (the Kubernetes node) and
`ssh.service`.

First, which services exist, and the tail of the whole journal:

```bash
systemctl list-units --type=service --no-pager | head -14
journalctl --no-pager -n 10
```

```text
Output (captured 2026-10-07, Ubuntu 24.04 VM)
  UNIT                                           LOAD   ACTIVE SUB     DESCRIPTION
  apparmor.service                               loaded active exited  Load AppArmor profiles
  cloud-config.service                           loaded active exited  Cloud-init: Config Stage
● cloud-final.service                            loaded failed failed  Cloud-init: Final Stage
  cloud-init-local.service                       loaded active exited  Cloud-init: Local Stage (pre-network)
  cloud-init.service                             loaded active exited  Cloud-init: Network Stage
  containerd.service                             loaded active running containerd container runtime
  dbus.service                                   loaded active running D-Bus System Message Bus
  dnsmasq.service                                loaded active running dnsmasq - A lightweight DHCP and caching DNS server
  docker.service                                 loaded active running Docker Application Container Engine
  getty@tty1.service                             loaded active running Getty on tty1
  k3s.service                                    loaded active running Lightweight Kubernetes
  kmod-static-nodes.service                      loaded active exited  Create List of Static Device Nodes
  ldconfig.service                               loaded active exited  Rebuild Dynamic Linker Cache

$ journalctl --no-pager -n 10
Oct 07 22:43:11 colima deluser[17911]: `/usr/bin/crontab' not executed. Skipping crontab removal. Package `cron' required.
Oct 07 22:43:11 colima deluser[17911]: Removing user `testuser' ...
Oct 07 22:43:11 colima userdel[17916]: delete user 'testuser'
Oct 07 22:43:11 colima userdel[17916]: delete 'testuser' from group 'sudo'
Oct 07 22:43:11 colima userdel[17916]: delete 'testuser' from group 'users'
Oct 07 22:43:11 colima userdel[17916]: removed group 'testuser' owned by 'testuser'
Oct 07 22:43:11 colima userdel[17916]: removed shadow group 'testuser' owned by 'testuser'
Oct 07 22:43:11 colima userdel[17916]: delete 'testuser' from shadow group 'sudo'
Oct 07 22:43:11 colima userdel[17916]: delete 'testuser' from shadow group 'users'
Oct 07 22:43:11 colima sudo[17910]: pam_unix(sudo:session): session closed for user root
```

The last ten lines are exactly the `deluser testuser` I had just run in Task 2: `deluser` logs its
own progress, then calls `userdel`, which logs every group it touches, and `sudo` logs the session
close through PAM. Nothing in Task 2 was invisible to the journal.

Logs for one specific service with `-u`:

```bash
journalctl -u docker --no-pager -n 10
journalctl -u k3s --no-pager -n 10
```

```text
Output (captured 2026-10-07, Ubuntu 24.04 VM)
$ journalctl -u docker --no-pager -n 10
Oct 07 22:41:17 colima dockerd[1529]: time="2026-10-07T22:41:17.344510508+05:30" level=info msg="received task-delete event from containerd" container=4a108eab4b3699a9c043489a2b00edac5da9a5d3cb559ddc91b12cc23489bda3 module=libcontainerd namespace=moby topic=/tasks/delete type="*events.TaskDelete"
Oct 07 22:41:30 colima dockerd[1529]: time="2026-10-07T22:41:30.775795653+05:30" level=info msg="sbJoin: gwep4 ''->'0c5b10b85982', gwep6 ''->''" eid=0c5b10b85982 ep=frontend net=frontend-net nid=01c04b06dcc0
Oct 07 22:41:30 colima dockerd[1529]: time="2026-10-07T22:41:30.897439123+05:30" level=info msg="sbJoin: gwep4 ''->'e8d97ab4532b', gwep6 ''->''" eid=e8d97ab4532b ep=backend net=backend-net nid=2ed119022a27
Oct 07 22:41:30 colima dockerd[1529]: time="2026-10-07T22:41:30.930479485+05:30" level=info msg="sbJoin: gwep4 'e8d97ab4532b'->'e8d97ab4532b', gwep6 ''->''" eid=82d8d2d505e6 ep=backend net=frontend-net nid=01c04b06dcc0
Oct 07 22:42:55 colima dockerd[1529]: time="2026-10-07T22:42:55.532622443+05:30" level=info msg="image pulled" digest="sha256:6ea90827b1100f8f2ae306a539f86d2c264a26ed435a2a9f75551dd5c3aeb242" remote="docker.io/library/mysql:8"
Oct 07 22:42:55 colima dockerd[1529]: time="2026-10-07T22:42:55.753926767+05:30" level=info msg="sbJoin: gwep4 ''->'bbdc36255228', gwep6 ''->''" eid=bbdc36255228 ep=db net=db-net nid=21f62777069c
Oct 07 22:42:55 colima dockerd[1529]: time="2026-10-07T22:42:55.822377368+05:30" level=info msg="sbJoin: gwep4 'bbdc36255228'->'dc032262cd39', gwep6 ''->''" eid=dc032262cd39 ep=db net=backend-net nid=2ed119022a27
Oct 07 22:43:07 colima dockerd[1529]: time="2026-10-07T22:43:07.339381996+05:30" level=error msg="[resolver] failed to query external DNS server" client-addr="udp:192.168.5.1:57473" dns-server="udp:192.168.5.1:53" error="read udp 192.168.5.1:57473->192.168.5.1:53: i/o timeout" question=";db.\tIN\t A"
Oct 07 22:43:09 colima dockerd[1529]: time="2026-10-07T22:43:09.842175685+05:30" level=error msg="[resolver] failed to query external DNS server" client-addr="udp:192.168.5.1:60806" dns-server="udp:192.168.5.1:53" error="read udp 192.168.5.1:60806->192.168.5.1:53: i/o timeout" question=";db.\tIN\t A"
Oct 07 22:43:11 colima dockerd[1529]: time="2026-10-07T22:43:11.339894914+05:30" level=error msg="[resolver] failed to query external DNS server" client-addr="udp:192.168.5.1:36300" dns-server="udp:192.168.5.1:53" error="read udp 192.168.5.1:36300->192.168.5.1:53: i/o timeout" question=";db.\tIN\t A"

$ journalctl -u k3s --no-pager -n 10
Oct 07 22:43:08 colima k3s[2058]: I1007 22:43:08.293129    2058 reconciler_common.go:299] "Volume detached for volume \"kube-api-access-pjx76\" (UniqueName: \"kubernetes.io/projected/0e9fd652-42fc-4130-a060-a3020c098fa2-kube-api-access-pjx76\") on node \"colima\" DevicePath \"\""
Oct 07 22:43:08 colima k3s[2058]: I1007 22:43:08.782524    2058 scope.go:122] "RemoveContainer" containerID="afb71887555e4783439aefd41d8eb05ce8c137fcd28ae0b2102c0415cdd6fd89"
Oct 07 22:43:08 colima k3s[2058]: E1007 22:43:08.784203    2058 prober_manager.go:209] "Readiness probe already exists for container" pod="s10/web-rolling-f66497d77-xjm88" containerName="web"
Oct 07 22:43:08 colima k3s[2058]: I1007 22:43:08.786589    2058 scope.go:122] "RemoveContainer" containerID="afb71887555e4783439aefd41d8eb05ce8c137fcd28ae0b2102c0415cdd6fd89"
Oct 07 22:43:08 colima k3s[2058]: E1007 22:43:08.786783    2058 log.go:32] "ContainerStatus from runtime service failed" err="rpc error: code = NotFound desc = an error occurred when try to find container \"afb71887555e4783439aefd41d8eb05ce8c137fcd28ae0b2102c0415cdd6fd89\": not found" containerID="afb71887555e4783439aefd41d8eb05ce8c137fcd28ae0b2102c0415cdd6fd89"
Oct 07 22:43:08 colima k3s[2058]: I1007 22:43:08.786804    2058 pod_container_deletor.go:53] "DeleteContainer returned error" containerID={"Type":"containerd","ID":"afb71887555e4783439aefd41d8eb05ce8c137fcd28ae0b2102c0415cdd6fd89"} err="failed to get container status \"afb71887555e4783439aefd41d8eb05ce8c137fcd28ae0b2102c0415cdd6fd89\": rpc error: code = NotFound desc = an error occurred when try to find container \"afb71887555e4783439aefd41d8eb05ce8c137fcd28ae0b2102c0415cdd6fd89\": not found"
Oct 07 22:43:08 colima k3s[2058]: I1007 22:43:08.788338    2058 pod_startup_latency_tracker.go:108] "Observed pod startup duration" pod="s10/web-rolling-f66497d77-xjm88" podStartSLOduration=1.7883337240000001 podStartE2EDuration="1.788333724s" podCreationTimestamp="2026-10-07 22:43:07 +0530 IST" firstStartedPulling="0001-01-01 00:00:00 +0000 UTC" lastFinishedPulling="0001-01-01 00:00:00 +0000 UTC" observedRunningTime="2026-10-07 22:43:08.787715263 +0530 IST m=+567.373257726" watchObservedRunningTime="2026-10-07 22:43:08.788333724 +0530 IST m=+567.373876188"
Oct 07 22:43:09 colima k3s[2058]: E1007 22:43:09.787101    2058 prober_manager.go:209] "Readiness probe already exists for container" pod="s10/web-rolling-f66497d77-xjm88" containerName="web"
Oct 07 22:43:10 colima k3s[2058]: I1007 22:43:10.474774    2058 kubelet_volumes.go:161] "Cleaned up orphaned pod volumes dir" podUID="0e9fd652-42fc-4130-a060-a3020c098fa2" path="/var/lib/kubelet/pods/0e9fd652-42fc-4130-a060-a3020c098fa2/volumes"
Oct 07 22:43:11 colima k3s[2058]: E1007 22:43:11.473211    2058 prober_manager.go:209] "Readiness probe already exists for container" pod="s11/web-nodeport-59b6887c46-m585t" containerName="web"
```

`-u docker` shows only what `dockerd` (PID 1529) wrote to its stdout/stderr: an image pull of
`mysql:8`, containers joining networks (`sbJoin`), and three `level=error` lines where its embedded
DNS resolver timed out. `-u k3s` shows the kubelet inside k3s (PID 2058) starting and cleaning up pods
for other namespaces on the same node. Each line still carries the full `Mon DD HH:MM:SS host
process[pid]:` prefix, which is what lets me correlate the two services by time.

Filtering by priority, by time, and checking the journal size:

```bash
journalctl -p err -b --no-pager | tail
journalctl --since "10 min ago" --no-pager | tail -n 5
journalctl --disk-usage
journalctl --list-boots --no-pager
journalctl -k --no-pager | tail -n 3
```

```text
Output (captured 2026-10-07, Ubuntu 24.04 VM)
$ journalctl -p err -b --no-pager | tail
Oct 07 22:29:02 ubuntu systemd-modules-load[144]: Failed to find module 'virtio_vsock'
Oct 07 22:29:05 lima-colima dnsmasq[571]: directory /etc/resolv.conf for resolv-file is missing, cannot poll
Oct 07 22:29:05 lima-colima dnsmasq[571]: FAILED to start up
Oct 07 22:29:05 lima-colima systemd[1]: Failed to start dnsmasq.service - dnsmasq - A lightweight DHCP and caching DNS server.
Oct 07 22:29:06 lima-colima sudo[1046]: ommalviya : unable to resolve host lima-colima: Temporary failure in name resolution
Oct 07 22:29:31 lima-colima sudo[1068]:     root : unable to resolve host lima-colima: Temporary failure in name resolution
Oct 07 22:29:39 colima systemd[1]: Failed to start cloud-final.service - Cloud-init: Final Stage.
Oct 07 22:31:06 colima sshd[1048]: pam_systemd(sshd:session): Failed to create session: Connection timed out
Oct 07 22:33:06 colima sshd[1289]: pam_systemd(sshd:session): Failed to create session: Connection timed out

$ journalctl --since "10 min ago" --no-pager | tail -n 5
Oct 07 22:43:11 colima userdel[17916]: removed group 'testuser' owned by 'testuser'
Oct 07 22:43:11 colima userdel[17916]: removed shadow group 'testuser' owned by 'testuser'
Oct 07 22:43:11 colima userdel[17916]: delete 'testuser' from shadow group 'sudo'
Oct 07 22:43:11 colima userdel[17916]: delete 'testuser' from shadow group 'users'
Oct 07 22:43:11 colima sudo[17910]: pam_unix(sudo:session): session closed for user root

$ journalctl --disk-usage
Archived and active journals take up 8.0M in the file system.

$ journalctl --list-boots --no-pager
IDX BOOT ID                          FIRST ENTRY                 LAST ENTRY
  0 c7d4614098ce4387b4abb8e469fc42e7 Wed 2026-10-07 22:29:02 IST Wed 2026-10-07 22:43:11 IST

$ journalctl -k --no-pager | tail -n 3
Oct 07 22:43:08 colima kernel: veth46b345b9: entered promiscuous mode
Oct 07 22:43:08 colima kernel: cni0: port 9(veth46b345b9) entered blocking state
Oct 07 22:43:08 colima kernel: cni0: port 9(veth46b345b9) entered forwarding state
```

What I observed: `-p err -b` found the real boot-time problems in a few seconds (dnsmasq failed on its
first start because `/etc/resolv.conf` did not exist yet, cloud-init's final stage failed, and the
hostname changed from `ubuntu` to `lima-colima` to `colima` during boot, which explains the "unable
to resolve host" lines). The journal is only 8 MB because the VM was booted 14 minutes earlier and
there is a single boot (`--list-boots`); `/var/log/journal` exists so it is persistent and would
accumulate across reboots. `-k` is the kernel ring buffer, showing the veth interfaces k3s creates
for every pod.

One thing that surprised me: `journalctl -u ssh -n 5` returned the same `userdel`/`sudo` lines as the
plain tail above. The `-p err` output explains it: `pam_systemd ... Failed to create session` means
my SSH login never got its own session scope, so every process I spawn stays in the `ssh.service`
cgroup and `-u ssh` matches them. A useful reminder that `-u` filters by the cgroup/unit a process
belongs to, not by the program name.

Troubleshooting workflow I would follow: `systemctl status <svc>` → `journalctl -xeu <svc>` →
`journalctl -p err -b` → fix → `systemctl restart <svc>` → `journalctl -u <svc> -f` while reproducing.

macOS note: there is no journal here; the counterpart is the unified log
(`log show --last 5m --predicate 'process == "sshd"'`, where `--predicate` plays the role of `-u`).
I tried `log show --last 2m --style compact | head` from my shell but it returned no lines in this
non-interactive session, so I have not included a captured block for it.

## Task 4: Linux Command Cheat Sheet

I extracted the text of the three course PDFs with `pdftotext` (`basic-linux.pdf`, `ad-linux.pdf`,
`Linux Networking Cheat Sheet.pdf`) to get the exact list of commands, then practised every one that
exists on macOS in `/tmp/cheatsheet-practice`. Linux-only ones are marked and given expected output.

### Command → purpose → example

**1. Files & directories**

| Command | Purpose | Example |
|---|---|---|
| `ls` | list directory contents | `ls -l /etc`, `ls -ltr` (latest last) |
| `cd` | change directory | `cd /var/log` |
| `pwd` | print working directory | `pwd` |
| `mkdir` | make directory | `mkdir -p /tmp/devops_logs` |
| `rm` | remove files/dirs | `rm -rf /tmp/devops_logs` |
| `touch` | create empty file / update mtime | `touch index.html` |
| `cp` | copy | `cp app.conf /etc/app/` |
| `mv` | move / rename | `mv app.log backup_app.log` |
| `find` | search by name/type/size | `find / -type f -name "file.txt"` |
| `locate` | fast indexed search (Linux, needs `updatedb`) | `locate nginx.conf` |
| `file` | identify file type | `file script.sh` |
| `rsync` | sync directories | `rsync -avz src/ dest/` |

**2. Viewing & searching**

| Command | Purpose | Example |
|---|---|---|
| `cat` | print file | `cat /etc/os-release` |
| `less` / `more` | page through big files | `less /var/log/syslog` |
| `head` / `tail` | first / last lines | `tail -n 100 /var/log/syslog`, `tail -f` to follow |
| `grep` | search text (regex) | `grep -ir "error" /var/log/` |
| `wc` | count lines/words/bytes | `wc -l file` |
| `sort` / `uniq` | sort, dedupe/count | `sort \| uniq -c` |
| `awk` | column processing | `awk '{print $1}' file` |
| `sed` | stream edit / replace | `sed 's/ERROR/CRITICAL/' file` |
| `xargs` | build commands from stdin | `ls *.txt \| xargs wc -l` |

**3. Processes & services**

| Command | Purpose | Example |
|---|---|---|
| `ps` | list processes | `ps aux \| grep nginx` |
| `top` / `htop` | live resource view | `top` (`top -l 1` on macOS for one snapshot) |
| `kill` / `pkill` | signal a process | `kill -9 1234`, `pkill nginx` |
| `nice` / `renice` | priority | `nice -n 10 cmd`, `renice -n -5 PID` |
| `nohup … &` / `bg` / `fg` | background jobs | `nohup python3 app.py &` |
| `systemctl` (Linux) | manage systemd services | `systemctl status nginx`, `systemctl restart nginx` |
| `journalctl` (Linux) | service logs | `journalctl -xe`, `journalctl -u nginx -f` |
| `uptime`, `vmstat 1`, `iostat -xz 1`, `sar -u 1 3`, `free -h` | load, memory, CPU, I/O (last four Linux/sysstat) | `free -h` |
| `strace -p PID` (Linux) | trace syscalls | `strace -p 1234` |
| `watch -n 1 df -h` (Linux) | re-run a command | `watch -n 1 df -h` |

**4. Networking**

| Command | Purpose | Example |
|---|---|---|
| `ping` | reachability | `ping -c 3 google.com` |
| `ip a` / `ifconfig` | addresses | `ip a` (Linux), `ifconfig en0` (macOS) |
| `ip route` / `netstat -rn` | routes | `ip route`, `netstat -rn` |
| `ip neigh` / `arp -a` | ARP table | `ip neigh` |
| `netstat -tulnp` / `ss -tulwn` / `ss -plnt` | listening ports (ss = modern) | `ss -tulpn` |
| `curl` | HTTP client | `curl -I https://api.github.com` |
| `wget` | download | `wget https://example.com/file.zip` |
| `traceroute` | path to host | `traceroute google.com` |
| `nmap` | port scan | `nmap 192.168.1.10` |
| `lsof -i :80` | which process uses port 80 | `lsof -i :80` |
| `ssh` / `scp` | remote shell / copy | `ssh user@host`, `scp file user@host:/path` |

**5. Permissions & users**

| Command | Purpose | Example |
|---|---|---|
| `chmod` | permissions | `chmod 755 script.sh` |
| `chown` | owner:group | `chown user:group file.txt` |
| `umask` | default permission mask | `umask` → `0022` |
| `sudo visudo` | edit sudoers safely | `sudo visudo` |
| `adduser` / `useradd` | create user | `adduser devops`, `useradd -m -s /bin/bash devuser` |
| `usermod` | modify user | `usermod -aG sudo devops` |
| `passwd` | set password | `passwd devops` |
| `deluser` / `userdel` | delete user | `userdel -r devops` |
| `id`, `groups`, `whoami`, `who`, `w`, `last` | identity and sessions | `id devops` |

**6. Packages, disk, scheduling, system info**

| Command | Purpose | Example |
|---|---|---|
| `apt` (Ubuntu) / `yum`/`dnf` (RHEL) | packages | `apt update && apt install nginx -y` |
| `df -h` | filesystem usage | `df -h` |
| `du -sh` | folder size | `du -sh /var/log`, `du -sh * \| sort -h` |
| `lsblk`, `mount`/`umount` (Linux) | block devices, mounts | `lsblk` |
| `tar` | archive | `tar -czf logs.tar.gz dir/`, `tar -tzf`, `tar -xzf` |
| `crontab -e` / `-l` | schedule | `0 2 * * * /home/user/backup.sh` |
| `uname -a`, `hostname`, `uptime`, `date`, `history`, `clear`, `man`, `which`, `env`, `alias` | system info and shell helpers | `man ls`, `which python3` |
| `dmesg` (Linux) | kernel ring buffer | `dmesg \| less` |
| Shortcuts | `!!` last cmd, `!n` nth from history, `Ctrl+C` cancel, `Ctrl+L` clear | |

### Practice on this machine

```bash
cd /tmp/cheatsheet-practice && pwd
mkdir -p devops_logs && touch index.html app.conf app.log && ls -l
cp app.conf devops_logs/ && mv app.log backup_app.log && ls -l devops_logs .
```

```text
Output (captured 2026-10-07)
/tmp/cheatsheet-practice
total 0
-rw-r--r--@ 1 om  wheel   0 Oct  7 22:28 app.conf
-rw-r--r--@ 1 om  wheel   0 Oct  7 22:28 app.log
drwxr-xr-x@ 2 om  wheel  64 Oct  7 22:28 devops_logs
-rw-r--r--@ 1 om  wheel   0 Oct  7 22:28 index.html
.:
total 0
-rw-r--r--@ 1 om  wheel   0 Oct  7 22:28 app.conf
-rw-r--r--@ 1 om  wheel   0 Oct  7 22:28 backup_app.log
drwxr-xr-x@ 3 om  wheel  96 Oct  7 22:28 devops_logs
-rw-r--r--@ 1 om  wheel   0 Oct  7 22:28 index.html

devops_logs:
total 0
-rw-r--r--@ 1 om  wheel  0 Oct  7 22:28 app.conf
```

```bash
printf "INFO server started\nERROR disk full\nINFO request ok\nERROR timeout\nWARN slow query\nINFO request ok\n" > syslog.txt
head -n 2 syslog.txt; tail -n 2 syslog.txt
grep ERROR syslog.txt; grep -c ERROR syslog.txt
wc syslog.txt
awk '{print $1}' syslog.txt | sort | uniq -c
sed 's/ERROR/CRITICAL/' syslog.txt
find . -type f -name "*.conf"
ls *.txt | xargs wc -l
```

```text
Output (captured 2026-10-07)
INFO server started
ERROR disk full
WARN slow query
INFO request ok
ERROR disk full
ERROR timeout
2
       6      17      98 syslog.txt
   2 ERROR
   3 INFO
   1 WARN
INFO server started
CRITICAL disk full
INFO request ok
CRITICAL timeout
WARN slow query
INFO request ok
./app.conf
./devops_logs/app.conf
       6 syslog.txt
```

I observed that `grep -c` counts matching lines, `wc` prints lines/words/bytes, and `awk | sort | uniq -c`
is the classic one-liner to count log levels (it needs `sort` first because `uniq` only merges adjacent
duplicates).

```bash
printf '#!/bin/bash\necho hello from script\n' > script.sh
ls -l script.sh && chmod 755 script.sh && ls -l script.sh && ./script.sh
chown $(id -un):staff script.sh && ls -l script.sh
umask; id; whoami; groups | tr " " "\n" | head -5
```

```text
Output (captured 2026-10-07)
-rw-r--r--@ 1 om  wheel  35 Oct  7 22:28 script.sh
-rwxr-xr-x@ 1 om  wheel  35 Oct  7 22:28 script.sh
hello from script
-rwxr-xr-x@ 1 om  staff  35 Oct  7 22:28 script.sh
0022
uid=501(om) gid=20(staff) groups=20(staff),12(everyone),61(localaccounts),80(admin),...
om
staff
everyone
localaccounts
_appserverusr
admin
```

`chmod 755` = `rwxr-xr-x` (owner 7 = 4+2+1, group/others 5 = 4+1). `umask 0022` is why new files are
644 and directories 755. `chown` changed only the group here (wheel → staff) because I own the file
already.

```bash
hostname; uname -a; uptime; date; who; w | head -3; last | head -3
```

```text
Output (captured 2026-10-07)
Oms-MacBook-Air-3.local
Darwin Oms-MacBook-Air-3.local 25.2.0 Darwin Kernel Version 25.2.0: Tue Nov 18 21:08:48 PST 2025; root:xnu-12377.61.12~1/RELEASE_ARM64_T8132 arm64
22:28  up 15 days,  7:13, 1 user, load averages: 2.83 2.76 2.78
Wed Oct  7 22:28:10 IST 2026
om        console      Sep 22 15:15
22:28  up 15 days,  7:13, 1 user, load averages: 2.83 2.76 2.78
USER       TTY      FROM    LOGIN@  IDLE WHAT
om  console  -      22Sep26 15days -
om  console                         Tue Sep 22 15:15   still logged in
reboot time                                Tue Sep 22 15:15
om  ttys002                         Sun Sep 20 14:08 - 14:08  (00:00)
```

```bash
ps aux | head -5
ps aux | grep -i "[f]inder" | head -1
top -l 1 | head -10          # Linux: top -b -n 1 | head
```

```text
Output (captured 2026-10-07)
USER               PID  %CPU %MEM      VSZ    RSS   TT  STAT STARTED      TIME COMMAND
_windowserver      166  58.6  0.7 437180464 112304   ??  Ss   22Sep26 898:46.20 /System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer -daemon
root             42809  35.3  0.2 435357696  33472   ??  Ss   10:15PM   0:03.36 .../XprotectService
om               8150  15.5  3.9 438162656 658256   ??  R    29Sep26 563:27.16 /Applications/WhatsApp.app/Contents/MacOS/WhatsApp
om              48567  12.9  0.1 435376416  24016   ??  S    10:28PM   0:00.07 .../mdworker_shared -s mdworker -c MDSImporterWorker
om                501   0.0  0.2 436008464  37504   ??  S    22Sep26  12:39.16 /System/Library/CoreServices/Finder.app/Contents/MacOS/Finder
Processes: 588 total, 4 running, 1 stuck, 583 sleeping, 5261 threads
2026/10/07 22:28:11
Load Avg: 2.83, 2.76, 2.78
CPU usage: 14.28% user, 20.57% sys, 65.13% idle
SharedLibs: 490M resident, 106M data, 82M linkedit.
MemRegions: 2092397 total, 4534M resident, 124M private, 1132M shared.
PhysMem: 15G used (3186M wired, 7020M compressor), 174M unused.
VM: 416T vsize, 17G framework vsize, 2534508(0) swapins, 3286456(0) swapouts.
Networks: packets: 79110727/51G in, 15410935/7896M out.
Disks: 25946632/459G read, 26793191/384G written.
```

The `[f]inder` trick in grep stops the grep process from matching itself.

```bash
sleep 300 & echo "started PID $!"; ps -p $! -o pid,stat,command
kill -9 $!; sleep 1; ps -p $! -o pid,stat,command || echo "process $! is gone"
nohup sleep 2 > nohup.out 2>&1 & echo "nohup job PID $!"
crontab -l
```

```text
Output (captured 2026-10-07)
started PID 48595
  PID STAT COMMAND
48595 S    sleep 300
[1]  48595 Killed: 9               sleep 300
  PID STAT COMMAND
process 48595 is gone
nohup job PID 48630
crontab: no crontab for om
```

```bash
df -h | head -4
du -sh devops_logs .
tar -czf logs.tar.gz syslog.txt devops_logs && ls -l logs.tar.gz && tar -tzf logs.tar.gz
file logs.tar.gz script.sh syslog.txt
rsync -av devops_logs/ devops_backup/ && ls devops_backup
```

```text
Output (captured 2026-10-07)
Filesystem        Size    Used   Avail Capacity iused ifree %iused  Mounted on
/dev/disk3s1s1   228Gi    11Gi    44Gi    21%    453k  457M    0%   /
devfs            215Ki   215Ki     0Bi   100%     742     0  100%   /dev
/dev/disk3s6     228Gi   7.0Gi    44Gi    14%       7  457M    0%   /System/Volumes/VM
  0B	devops_logs
8.0K	.
-rw-r--r--@ 1 om  wheel  578 Oct  7 22:28 logs.tar.gz
syslog.txt
devops_logs/
devops_logs/app.conf
logs.tar.gz: gzip compressed data, last modified: Wed Oct  7 16:58:15 2026, from Unix, original size modulo 2^32 9216
script.sh:   Bourne-Again shell script text executable, ASCII text
syslog.txt:  ASCII text
Transfer starting: 2 files
./
app.conf
sent 150 bytes  received 48 bytes  180000 bytes/sec
app.conf
```

`tar -c` create, `-z` gzip, `-f` file, `-t` list, `-x` extract; I remember it as "create zip file".

```bash
which bash python3 git
env | grep -E "^(HOME|SHELL|USER|PATH)=" | cut -c1-80
man ls | head -8
alias ll='ls -alF'; alias ll
lsof -i :80 | head -3
cat /etc/hosts | head -5
```

```text
Output (captured 2026-10-07)
/bin/bash
/Library/Frameworks/Python.framework/Versions/3.12/bin/python3
/usr/bin/git
SHELL=/bin/zsh
USER=om
PATH=$HOME/.local/bin:$HOME/.antigravity/antigravity/bin:$HOME/.nvm/versions/nod
HOME=$HOME
LS(1)                       General Commands Manual                      LS(1)

NAME
     ls – list directory contents

SYNOPSIS
     ls [-@ABCFGHILOPRSTUWabcdefghiklmnopqrstuvwxy1%,] [--color=when]
        [-D format] [file ...]
alias ll='ls -alF'
(no output: nothing is listening on port 80 on this laptop)
##
# Host Database
#
# localhost is used to configure the loopback interface
# when the system is booting.  Do not change this entry.
```

`history` printed nothing because the commands ran from a non-interactive script (history is only
recorded by an interactive shell); in a terminal `history | tail -3` lists the last three commands and
`!!` repeats the last one.

### Linux-only commands from the cheat sheet (run on the Ubuntu 24.04 VM)

I ran these inside the Colima VM (`colima ssh`). I did not install nginx there (the VM is shared with
the Docker/Kubernetes homework and I did not want to change its package set), so `systemctl status`
is shown for `docker` instead, and `apt` is shown with the read-only `apt list --installed`.

```bash
uname -a; hostname; uptime
apt list --installed 2>/dev/null | head -8
systemctl status docker --no-pager | head -12
free -h
sudo ss -tulpn | head -8
ip a | head -12
lsblk
sudo dmesg | tail -2
```

```text
Output (captured 2026-10-07, Ubuntu 24.04 VM)
Linux colima 6.8.0-117-generic #117-Ubuntu SMP PREEMPT_DYNAMIC Thu May  7 17:26:37 UTC 2026 aarch64 aarch64 aarch64 GNU/Linux
colima
 22:43:12 up 14 min,  1 user,  load average: 1.38, 1.27, 0.77

Listing...
adduser/now 3.137ubuntu1 all [installed,local]
apparmor/now 4.0.1really4.0.1-0ubuntu0.24.04.6 arm64 [installed,local]
apt/now 2.8.3 arm64 [installed,local]
base-files/now 13ubuntu10.4 arm64 [installed,local]
base-passwd/now 3.6.3build1 arm64 [installed,local]
bash/now 5.2.21-2ubuntu4 arm64 [installed,local]
bsdutils/now 1:2.39.3-9ubuntu6.5 arm64 [installed,local]

● docker.service - Docker Application Container Engine
     Loaded: loaded (/usr/lib/systemd/system/docker.service; enabled; preset: enabled)
    Drop-In: /etc/systemd/system/docker.service.d
             └─docker.conf
     Active: active (running) since Wed 2026-10-07 22:33:08 IST; 10min ago
TriggeredBy: ● docker.socket
       Docs: https://docs.docker.com
   Main PID: 1529 (dockerd)
      Tasks: 135
     Memory: 92.0M (peak: 110.3M)
        CPU: 10.929s
     CGroup: /system.slice/docker.service

               total        used        free      shared  buff/cache   available
Mem:           5.8Gi       2.1Gi       131Mi       6.8Mi       3.7Gi       3.7Gi
Swap:             0B          0B          0B

Netid State  Recv-Q Send-Q                    Local Address:Port  Peer Address:PortProcess
udp   UNCONN 0      0                               0.0.0.0:36165      0.0.0.0:*    users:(("dnsmasq",pid=1388,fd=16))
udp   UNCONN 0      0                             127.0.0.1:53         0.0.0.0:*    users:(("dnsmasq",pid=1388,fd=6))
udp   UNCONN 0      0                           192.168.5.1:53         0.0.0.0:*    users:(("dnsmasq",pid=1388,fd=4))
udp   UNCONN 0      0                      192.168.5.1%eth0:68         0.0.0.0:*    users:(("systemd-network",pid=425,fd=21))
udp   UNCONN 0      0                               0.0.0.0:8472       0.0.0.0:*
udp   UNCONN 0      0                                 [::1]:53            [::]:*    users:(("dnsmasq",pid=1388,fd=10))
udp   UNCONN 0      0      [fe80::5055:55ff:fecd:4a65]%eth0:53            [::]:*    users:(("dnsmasq",pid=1388,fd=8))

1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host noprefixroute
       valid_lft forever preferred_lft forever
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
    link/ether 52:55:55:cd:4a:65 brd ff:ff:ff:ff:ff:ff
    inet 192.168.5.1/24 metric 200 brd 192.168.5.255 scope global dynamic eth0
       valid_lft 2751sec preferred_lft 2751sec
    inet6 fe80::5055:55ff:fecd:4a65/64 scope link
       valid_lft forever preferred_lft forever

NAME    MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
vda     253:0    0   20G  0 disk
├─vda1  253:1    0   19G  0 part /
├─vda15 253:15   0   99M  0 part /boot/efi
└─vda16 259:0    0  923M  0 part /boot
vdb     253:16   0   40G  0 disk
└─vdb1  253:17   0   40G  0 part /var/lib/ramalama
                                 /var/lib/cni
                                 /var/lib/rancher
                                 /var/lib/containerd
                                 /var/lib/docker
                                 /mnt/lima-colima
vdc     253:32   0 19.1M  1 disk /mnt/lima-cidata

[  845.823074] cni0: port 9(veth46b345b9) entered blocking state
[  845.823077] cni0: port 9(veth46b345b9) entered forwarding state
```

What I read from this: the VM has 5.8 GiB RAM with no swap and most memory in `buff/cache`
(`available` 3.7 Gi is the number that matters, not `free`); `ss -tulpn` shows who owns each
listening socket (dnsmasq on :53, port 8472/udp with no process is the flannel VXLAN tunnel of k3s,
owned by the kernel); `ip a` shows the single NIC `eth0` with `192.168.5.1/24`; `lsblk` shows two
virtio disks, a 20 G root disk and a 40 G data disk mounted at `/var/lib/docker`, `/var/lib/rancher`
etc. (bind mounts of one partition); and `dmesg` ends with the same `cni0`/`veth` lines that
`journalctl -k` showed in Task 3, because both read the kernel ring buffer. The one command I still
only show as documentation is `sudo apt install nginx -y`, for the reason given above.

## Screenshots

| Spec item | Stand-in in this README |
|---|---|
| Soft/hard link creation and deletion | `Output (captured 2026-10-07)` blocks in Task 1 (`ls -li`, `stat`, `cat` after `rm`) |
| Test user creation | `Output (captured 2026-10-07, Ubuntu 24.04 VM)` blocks in Task 2 (`useradd`, `adduser`, `id`, `getent`, `ls -la /home/testuser`, cleanup) |
| journalctl for a service | `Output (captured 2026-10-07, Ubuntu 24.04 VM)` blocks in Task 3 (`journalctl -n 10`, `-u docker`, `-u k3s`, `-p err -b`, `--since`, `--disk-usage`) |
| Cheat-sheet practice | `Output (captured 2026-10-07)` blocks in Task 4 (macOS) and `Output (captured 2026-10-07, Ubuntu 24.04 VM)` for the Linux-only commands |

## Deliverables

- `homework/session02-linux/README.md` – all four tasks: link experiments with real output and interview Q&A, adduser vs useradd run on an Ubuntu 24.04 VM, journalctl run against real services (docker, k3s) on the same VM, cheat-sheet table plus practised commands with captured output on macOS and the VM.
