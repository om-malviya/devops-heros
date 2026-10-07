# Session 04 – Networking
Student: Om Malviya | Enrollment No: 24BCS10448

All commands in Task 2 were really executed on my laptop (macOS, Wi-Fi `en0`) on 2026-10-07.
For privacy I replaced MAC addresses with `xx:xx:xx:xx:xx:xx` and my public IP with the
documentation address `203.0.113.37`; everything else is verbatim. `ip` and `ss` do not exist on
macOS, so the Linux equivalents are shown with `Expected output`.

## Task 1: Practice commands and repo shared in devops-hero github repo

### Summary of `session4-networking/ip.md`

- An **IP address** is the unique number that identifies a device on a network. IPv4 is 32 bits,
  written as four octets `0.0.0.0` – `255.255.255.255`.
- The address has a **network part** and a **host part**; the **subnet mask** tells which bits are
  which (1-bits = network, 0-bits = host).
- The notes use two notations for the same thing: dotted mask (`255.0.0.0`) and **CIDR** (`/8`).
- **Classful ranges** (by first octet) and their default masks:

| Class | First octet | Default mask | CIDR | Network bits | Host bits | Hosts per network (2^h − 2) |
|---|---|---|---|---|---|---|
| A | 1 – 127 | 255.0.0.0 | /8 | 8 | 24 | 16,777,214 |
| B | 128 – 191 | 255.255.0.0 | /16 | 16 | 16 | 65,534 |
| C | 192 – 223 | 255.255.255.0 | /24 | 24 | 8 | 254 |
| D | 224 – 239 | – (multicast) | – | – | – | – |
| E | 240 – 255 | – (experimental/reserved) | – | – | – | – |

- "−2" because the all-zeros host is the **network address** and the all-ones host is the
  **broadcast address**; neither can be given to a machine.
- `127.0.0.0/8` inside class A is loopback (`127.0.0.1` = this machine).
- **Private ranges** (RFC 1918, never routed on the internet; NAT is needed to go out):
  `10.0.0.0 – 10.255.255.255` (10/8, one class A), `172.16.0.0 – 172.31.255.255` (172.16/12, 16 class Bs),
  `192.168.0.0 – 192.168.255.255` (192.168/16, 256 class Cs). My lab Wi-Fi hands out `100.129.x.x`,
  which is the carrier-grade NAT range `100.64.0.0/10`, another non-public block.

### Worked subnetting examples (from the notes)

**Example 1 – `120.27.1.0/8` (class A, mask `255.0.0.0`)**

```text
IP        120 . 27 . 1 . 0
mask      255 .  0 . 0 . 0      -> /8 : 8 network bits, 32-8 = 24 host bits
network   120 .  0 . 0 . 0      (AND of IP and mask)
broadcast 120 .255.255.255      (host bits all 1)
hosts     2^24 = 16,777,216  ->  usable = 2^24 - 2 = 16,777,214
range     120.0.0.1  ..  120.255.255.254
```

**Example 2 – `197.23.45.10/24` (class C, mask `255.255.255.0`)**

```text
IP        197 . 23 . 45 . 10
mask      255 .255 .255 .  0    -> /24 : 24 network bits, 8 host bits
network   197 . 23 . 45 .  0
broadcast 197 . 23 . 45 .255
hosts     2^8 = 256 -> usable = 254   (197.23.45.1 .. 197.23.45.254)
```

**Example 3 – the same `120.27.1.0` as `/16`** (classless: I can cut a class A block with a class B mask)

```text
mask      255.255.0.0  -> network 120.27.0.0, broadcast 120.27.255.255, usable 2^16 - 2 = 65,534
```

**Example 4 – splitting `192.168.1.0/24` into four `/26` subnets** (borrow 2 host bits → 2^2 = 4 subnets, 6 host bits → 62 usable each)

```text
subnet 1  192.168.1.0/26     hosts .1  - .62    broadcast .63
subnet 2  192.168.1.64/26    hosts .65 - .126   broadcast .127
subnet 3  192.168.1.128/26   hosts .129- .190   broadcast .191
subnet 4  192.168.1.192/26   hosts .193- .254   broadcast .255
mask for /26 = 255.255.255.192   (11111111.11111111.11111111.11000000)
```

**CIDR → mask → usable hosts quick table**

| CIDR | Mask | Host bits | Usable hosts | Typical use |
|---|---|---|---|---|
| /8 | 255.0.0.0 | 24 | 16,777,214 | whole 10.0.0.0 private block |
| /16 | 255.255.0.0 | 16 | 65,534 | a VPC (e.g. 10.0.0.0/16) |
| /24 | 255.255.255.0 | 8 | 254 | one subnet / one office LAN |
| /25 | 255.255.255.128 | 7 | 126 | |
| /26 | 255.255.255.192 | 6 | 62 | |
| /27 | 255.255.255.224 | 5 | 30 | small AWS subnet |
| /28 | 255.255.255.240 | 4 | 14 | |
| /30 | 255.255.255.252 | 2 | 2 | point-to-point link |
| /32 | 255.255.255.255 | 0 | 1 (host route) | security-group rule for one IP |

**Method I use for any address:** write the mask in binary, AND it with the IP to get the network,
set the host bits to 1 for the broadcast, usable hosts = 2^(32 − prefix) − 2.

### Summary of `session4-networking/resources.md`

A GitHub list (`github.com/stars/Nency-Ravaliya/lists/networking`) with seven repositories. What I
took from each:

| Repository | Topic |
|---|---|
| Network-Troubleshooting | step-by-step approach: `ping` → `traceroute` → DNS (`dig`/`nslookup`) → ports (`ss`, `telnet`, `nc`) → `curl` |
| OSI-Network-devices | the 7 OSI layers and which device works at which layer (hub L1, switch L2, router L3, load balancer L4/L7) |
| Networking | basics: IP, MAC, DNS, DHCP, NAT, TCP vs UDP, ports |
| Subnetting | the classful/CIDR material summarised above with practice questions |
| IP-quest | IP-address quiz questions |
| IPFIX-NETFLOW-NTP | flow export protocols (NetFlow/IPFIX) for traffic accounting, and NTP for time sync |
| How-DHCP-Works | DORA: Discover → Offer → Request → Acknowledge; how a client gets IP, mask, gateway, DNS |

## Task 2: Execute the networking commands and explain each

### `ifconfig en0`

```bash
ifconfig en0
ifconfig | grep -E '^[a-z0-9]+:|inet ' | head -20
```

```text
Output (captured 2026-10-07)
en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
	options=6460<TSO4,TSO6,CHANNEL_IO,PARTIAL_CSUM,ZEROINVERT_CSUM>
	ether xx:xx:xx:xx:xx:xx
	inet6 fe80::870:f1ee:7cd2:8061%en0 prefixlen 64 secured scopeid 0xb
	inet 100.129.161.97 netmask 0xfffff000 broadcast 100.129.175.255
	nd6 options=201<PERFORMNUD,DAD>
	media: autoselect
	status: active

lo0: flags=8049<UP,LOOPBACK,RUNNING,MULTICAST> mtu 16384
	inet 127.0.0.1 netmask 0xff000000
gif0: flags=8010<POINTOPOINT,MULTICAST> mtu 1280
stf0: flags=0<> mtu 1280
anpi0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
en3: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
	inet 100.129.161.97 netmask 0xfffff000 broadcast 100.129.175.255
bridge0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
awdl0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
utun0: flags=8051<UP,POINTOPOINT,RUNNING,MULTICAST> mtu 1380
```

**What I understood:** `ifconfig` lists every interface. `en0` is my Wi-Fi card: it has a MAC
(`ether`), an IPv4 `100.129.161.97` with mask `0xfffff000` = `255.255.240.0` = **/20**, so the
broadcast is `100.129.175.255` (exactly the subnetting math from Task 1: 12 host bits, 4094 usable
hosts). `lo0` is loopback `127.0.0.1`; `utun*` are VPN tunnels; `mtu 1500` is the normal Ethernet
frame payload size.

### `ipconfig getifaddr en0`

```bash
ipconfig getifaddr en0
ipconfig getoption en0 router; ipconfig getoption en0 domain_name_server
```

```text
Output (captured 2026-10-07)
100.129.161.97
100.129.160.1
100.129.160.1
```

**What I understood:** the macOS `ipconfig` (not the Windows one) asks the DHCP client for just the
IP, and `getoption` shows what DHCP handed out: the default gateway and DNS server are both the
router `100.129.160.1`. Linux equivalent: `hostname -I` or `ip -4 addr show eth0`.

### `netstat -rn`

```bash
netstat -rn | head -15
```

```text
Output (captured 2026-10-07)
Routing tables

Internet:
Destination        Gateway            Flags               Netif Expire
default            100.129.160.1      UGScg                 en0
100.129.160/20     link#11            UCS                   en0      !
100.129.160.1/32   link#11            UCS                   en0      !
100.129.160.1      xx:xx:xx:xx:xx:xx  UHLWIir               en0   1181
100.129.160.16     xx:xx:xx:xx:xx:xx  UHLWI                 en0   1083
100.129.160.36     xx:xx:xx:xx:xx:xx  UHLWI                 en0    295
100.129.160.44     xx:xx:xx:xx:xx:xx  UHLWI                 en0   1125
```

**What I understood:** the routing table decides where a packet goes. `default` (0.0.0.0/0) → gateway
`100.129.160.1` via `en0` means "anything not local goes to the router". `100.129.160/20 link#11` is my
directly connected subnet (no gateway, delivered by ARP). Flags: U up, G gateway, H host route,
S static, L link-layer. `-n` skips DNS lookups so it is fast.

### `netstat -an`

```bash
netstat -an | head -15
```

```text
Output (captured 2026-10-07)
Active Internet connections (including servers)
Proto Recv-Q Send-Q  Local Address          Foreign Address        (state)
tcp4       0      0  100.129.161.97.57807   3.236.94.240.443       ESTABLISHED
tcp4       0      0  100.129.161.97.57806   3.236.94.240.443       ESTABLISHED
tcp4       0      0  127.0.0.1.57805        127.0.0.1.8765         SYN_SENT
tcp4       0      0  *.8765                 *.*                    CLOSED
tcp4       0      0  100.129.161.97.57801   3.236.94.240.443       ESTABLISHED
tcp4       0   1296  100.129.161.97.57799   18.172.64.38.443       ESTABLISHED
tcp4       0      0  100.129.161.97.57795   142.251.223.238.443    ESTABLISHED
tcp4       0      0  100.129.161.97.57760   185.199.108.133.443    ESTABLISHED
```

**What I understood:** every socket on the machine. `-a` includes listening servers, `-n` numeric.
Each line is a 4-tuple `local-ip.port ↔ remote-ip.port`; my side uses ephemeral ports (57xxx) and the
remote side is 443 (HTTPS). `ESTABLISHED` is an open TCP connection, `SYN_SENT` means the 3-way
handshake was started but not answered yet, `LISTEN` would be a server waiting. `185.199.108.133` is
GitHub, `142.251.x.x` is Google.

### `ping -c 3 8.8.8.8` and `ping -c 3 google.com`

```bash
ping -c 3 8.8.8.8
ping -c 3 google.com
```

```text
Output (captured 2026-10-07)
PING 8.8.8.8 (8.8.8.8): 56 data bytes
64 bytes from 8.8.8.8: icmp_seq=0 ttl=118 time=74.578 ms
64 bytes from 8.8.8.8: icmp_seq=1 ttl=118 time=14.524 ms
64 bytes from 8.8.8.8: icmp_seq=2 ttl=118 time=94.863 ms

--- 8.8.8.8 ping statistics ---
3 packets transmitted, 3 packets received, 0.0% packet loss
round-trip min/avg/max/stddev = 14.524/61.322/94.863/34.111 ms

PING google.com (192.178.174.139): 56 data bytes
64 bytes from 192.178.174.139: icmp_seq=0 ttl=112 time=390.441 ms
64 bytes from 192.178.174.139: icmp_seq=1 ttl=112 time=314.574 ms
64 bytes from 192.178.174.139: icmp_seq=2 ttl=112 time=126.445 ms

--- google.com ping statistics ---
3 packets transmitted, 3 packets received, 0.0% packet loss
round-trip min/avg/max/stddev = 126.445/277.153/390.441/110.977 ms
```

**What I understood:** `ping` sends ICMP echo requests and measures round-trip time. Pinging the IP
`8.8.8.8` first tests raw connectivity; pinging `google.com` additionally tests DNS (the name was
resolved to `192.178.174.139` before the first packet). `ttl=118` tells me the reply crossed
128 − 118 = 10 routers (Google starts at 128; Linux hosts start at 64). 0% loss but a jittery RTT
(14 → 94 ms) shows a busy Wi-Fi link, not a broken one. `-c 3` stops after 3 packets (on Linux
`ping` otherwise runs forever).

### `traceroute -m 8 google.com`

```bash
traceroute -m 8 -w 2 -q 1 google.com
```

```text
Output (captured 2026-10-07)
traceroute: Warning: google.com has multiple addresses; using 192.178.174.113
traceroute to google.com (192.178.174.113), 8 hops max, 40 byte packets
 1  wifi.height8tech.com (100.129.160.1)  74.174 ms
 2  202.131.133.5.convergentindia.com (202.131.133.5)  13.635 ms
 3  115.117.125.189.static-mumbai.vsnl.net.in (115.117.125.189)  29.454 ms
 4  *
 5  115.112.15.114.static-chennai.vsnl.net.in (115.112.15.114)  140.796 ms
 6  lcbomo-in-f113.1e100.net (192.178.174.113)  106.294 ms
```

**What I understood:** traceroute sends packets with TTL 1, 2, 3… and each router that drops the
packet reports back, so I see the path: my Wi-Fi router → the ISP (Convergent India) → Tata/VSNL
backbone in Mumbai → Chennai → Google's edge (`1e100.net`) in 6 hops. Hop 4 is `*` because that
router does not answer ICMP time-exceeded, which is normal. `-m 8` caps the hops, `-w 2` waits
2 s per probe and `-q 1` sends one probe per hop so the command finishes quickly. Linux: same
command (`traceroute` or `mtr` for a live view).

### `nslookup google.com`

```bash
nslookup google.com
```

```text
Output (captured 2026-10-07)
Server:		8.8.8.8
Address:	8.8.8.8#53

Non-authoritative answer:
Name:	google.com
Address: 192.178.174.138
Name:	google.com
Address: 192.178.174.100
Name:	google.com
Address: 192.178.174.113
Name:	google.com
Address: 192.178.174.101
Name:	google.com
Address: 192.178.174.102
Name:	google.com
Address: 192.178.174.139
```

**What I understood:** DNS resolution. The query went to resolver `8.8.8.8` on UDP port 53 and
returned six A records (Google load-balances by handing out several IPs; that is why `ping` and
`traceroute` picked different ones). "Non-authoritative" means the answer came from a cache, not
Google's own name servers.

### `dig google.com +short` and `dig MX google.com`

```bash
dig google.com +short
dig MX google.com +noall +answer
```

```text
Output (captured 2026-10-07)
192.178.174.100
192.178.174.113
192.178.174.101
192.178.174.102
192.178.174.139
192.178.174.138

; <<>> DiG 9.10.6 <<>> MX google.com +noall +answer
;; global options: +cmd
google.com.		300	IN	MX	10 smtp.google.com.
```

**What I understood:** `dig` is the scriptable DNS tool. `+short` prints only the answer section,
ideal in shell scripts. Asking for the `MX` record shows where mail for `google.com` is delivered
(`smtp.google.com`, priority 10) with a TTL of 300 s, i.e. resolvers may cache it for 5 minutes.
Other useful record types: `NS`, `TXT`, `CNAME`, `AAAA`; `dig @1.1.1.1 example.com` queries a specific
server; `dig -x 8.8.8.8` does a reverse lookup.

### `host github.com`

```bash
host github.com
host -t A github.com 8.8.8.8
```

```text
Output (captured 2026-10-07)
github.com has address 20.207.73.82
github.com mail is handled by 0 github-com.mail.protection.outlook.com.

Using domain server:
Name: 8.8.8.8
Address: 8.8.8.8#53
Aliases:

github.com has address 20.207.73.82
```

**What I understood:** `host` is the simplest resolver: it prints A, AAAA and MX records in one line
each. GitHub's A record resolves to an Azure IP (`20.207.73.82`, India region) and its mail goes to
Microsoft 365. My first attempt returned `;; connection timed out; no servers could be reached` because
the Wi-Fi DNS hiccuped; re-running (and pointing at `8.8.8.8` explicitly) worked, which is itself a
useful troubleshooting lesson: when a name fails, try another resolver before blaming the site.

### `curl -I https://github.com`

```bash
curl -sI https://github.com | head -12
```

```text
Output (captured 2026-10-07)
HTTP/2 200
date: Wed, 07 Oct 2026 16:58:55 GMT
content-type: text/html; charset=utf-8
content-language: en-US
vary: X-PJAX, X-PJAX-Container, Turbo-Visit, Turbo-Frame, X-Requested-With, X-GitHub-Client-Version, Accept-Language, Sec-Fetch-Site,Accept-Encoding, Accept, X-Requested-With
etag: W/"f71a4317be42d38104287999d62bf3e8"
cache-control: max-age=0, private, must-revalidate
strict-transport-security: max-age=31536000; includeSubdomains; preload
x-frame-options: deny
x-content-type-options: nosniff
x-xss-protection: 0
referrer-policy: origin-when-cross-origin, strict-origin-when-cross-origin
```

**What I understood:** `-I` sends a HEAD request, so I get only the response headers: status
`200` over `HTTP/2`, content type, caching headers, and security headers (HSTS, `x-frame-options:
deny`). This is the fastest way to check "is the web app up and what is it returning" from a
server without a browser; `-v` would also show the TLS handshake, `-L` follows redirects,
`-o /dev/null -w '%{http_code}'` gives just the code for scripts.

### `curl -s ifconfig.me`

```bash
curl -s ifconfig.me; echo
```

```text
Output (captured 2026-10-07)
203.0.113.37      <- real public IP redacted; it was a 202.131.x.x address owned by my ISP
```

**What I understood:** `ifconfig.me` echoes back the source address it saw. It is **not** my
`100.129.161.97` interface address: the router/ISP performs NAT, so the whole lab shares one public
IP. The address matched hop 2 of the traceroute (my ISP's network), which confirms NAT happens at the
ISP (carrier-grade NAT, hence the `100.64/10` private-like range inside).

### `arp -a`

```bash
arp -an | head -6
```

```text
Output (captured 2026-10-07)
? (100.129.160.1) at xx:xx:xx:xx:xx:xx on en0 ifscope [ethernet]
? (100.129.160.16) at xx:xx:xx:xx:xx:xx on en0 ifscope [ethernet]
? (100.129.160.36) at xx:xx:xx:xx:xx:xx on en0 ifscope [ethernet]
? (100.129.160.44) at xx:xx:xx:xx:xx:xx on en0 ifscope [ethernet]
? (100.129.160.56) at xx:xx:xx:xx:xx:xx on en0 ifscope [ethernet]
? (100.129.160.94) at xx:xx:xx:xx:xx:xx on en0 ifscope [ethernet]
```

**What I understood:** ARP maps IPv4 → MAC on the local segment (OSI layer 2/3 boundary). The first
entry is my gateway. `-n` avoids reverse-DNS lookups (plain `arp -a` was very slow here because it
tried to resolve every neighbour's name). Linux equivalent: `ip neigh`.

### `lsof -i -P`

```bash
lsof -i -P -n | head -8
```

```text
Output (captured 2026-10-07)
COMMAND     PID USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
rapportd    425   om    3u  IPv6 0x71058bedcb484466      0t0  TCP *:58665 (LISTEN)
rapportd    425   om   15u  IPv4 0x726817d7f9550401      0t0  TCP *:57083 (LISTEN)
rapportd    425   om   16u  IPv6 0xcd386935ec01a51b      0t0  TCP *:57083 (LISTEN)
rapportd    425   om   19u  IPv6  0x3a59698cb1c6284      0t0  TCP *:58666 (LISTEN)
rapportd    425   om   23u  IPv6 0xed6760b4cc7aba33      0t0  TCP *:58859 (LISTEN)
rapportd    425   om   26u  IPv6 0x467207eb4d90a1b9      0t0  TCP *:58860 (LISTEN)
identitys   454   om    7u  IPv4 0xa53c41ec45f16b02      0t0  UDP *:*
```

**What I understood:** `lsof -i` lists which **process** owns which socket, the thing `netstat` cannot
show on macOS. `-P` keeps port numbers numeric, `-n` keeps IPs numeric. `*:58665 (LISTEN)` means the
process accepts connections on all interfaces. This is how I answer "what is running on port 8080?"
(`lsof -i :8080`). Linux: `ss -tulpn` or `lsof -i :8080`.

### `scutil --dns`

```bash
scutil --dns | head -20
```

```text
Output (captured 2026-10-07)
DNS configuration

resolver #1
  nameserver[0] : 100.129.160.1
  nameserver[1] : 8.8.8.8
  if_index : 11 (en0)
  flags    : Request A records
  reach    : 0x00020002 (Reachable,Directly Reachable Address)

resolver #2
  domain   : local
  options  : mdns
  timeout  : 5
  flags    : Request A records
  reach    : 0x00000000 (Not Reachable)
  order    : 300000
```

**What I understood:** macOS keeps a list of resolvers instead of a single `/etc/resolv.conf`.
Resolver #1 is used for everything: the router first, then Google `8.8.8.8` as a fallback (which is
why `nslookup` showed `8.8.8.8` as the server when the router was slow). Resolver #2 handles
`.local` names via multicast DNS (Bonjour). Linux equivalent: `resolvectl status` or `cat /etc/resolv.conf`.

### `networksetup -listallhardwareports`

```bash
networksetup -listallhardwareports | head -20
```

```text
Output (captured 2026-10-07)
Hardware Port: Ethernet Adapter (en3)
Device: en3
Ethernet Address: xx:xx:xx:xx:xx:xx

Hardware Port: Ethernet Adapter (en4)
Device: en4
Ethernet Address: xx:xx:xx:xx:xx:xx

Hardware Port: Thunderbolt Bridge
Device: bridge0
Ethernet Address: xx:xx:xx:xx:xx:xx

Hardware Port: Wi-Fi
Device: en0
Ethernet Address: xx:xx:xx:xx:xx:xx

Hardware Port: Thunderbolt 1
Device: en1
Ethernet Address: xx:xx:xx:xx:xx:xx
```

**What I understood:** this maps the human names ("Wi-Fi", "Thunderbolt Bridge") to the BSD device
names (`en0`, `bridge0`) that `ifconfig` uses, plus each port's MAC. It confirmed `en0` is Wi-Fi,
which is why I used `en0` in the earlier commands. Linux equivalent: `ip link` / `nmcli device`.

### Linux equivalents: `ip addr`, `ip route`, `ss -tulpn`

macOS does not ship `iproute2` or `ss`. These are the commands from the course's "Linux Networking
Cheat Sheet" that I would run on an Ubuntu server, with the net-tools ↔ iproute2 mapping.

| net-tools (old, macOS has these) | iproute2 (modern Linux) |
|---|---|
| `ifconfig -a` | `ip addr` / `ip a` |
| `ifconfig eth0 up/down` | `ip link set eth0 up/down` |
| `ifconfig eth0 192.168.1.1 netmask 255.255.255.0` | `ip addr add 192.168.1.1/24 dev eth0` |
| `route` / `netstat -rn` | `ip route` |
| `route add default gw 192.168.1.1` | `ip route add default via 192.168.1.1` |
| `arp -a` | `ip neigh` |
| `netstat -tulnp` | `ss -tulpn` |
| `netstat -g` | `ip maddr` |

```bash
ip addr
ip route
ip neigh
ss -tulpn
```

```text
Expected output
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
    link/ether 02:42:ac:11:00:02 brd ff:ff:ff:ff:ff:ff
    inet 192.168.1.50/24 brd 192.168.1.255 scope global dynamic eth0
       valid_lft 86213sec preferred_lft 86213sec

default via 192.168.1.1 dev eth0 proto dhcp src 192.168.1.50 metric 100
192.168.1.0/24 dev eth0 proto kernel scope link src 192.168.1.50 metric 100

192.168.1.1 dev eth0 lladdr 00:11:22:33:44:55 REACHABLE
192.168.1.20 dev eth0 lladdr 00:11:22:33:44:66 STALE

Netid State  Recv-Q Send-Q Local Address:Port  Peer Address:Port Process
udp   UNCONN 0      0      127.0.0.53%lo:53    0.0.0.0:*         users:(("systemd-resolve",pid=612,fd=13))
tcp   LISTEN 0      511    0.0.0.0:80          0.0.0.0:*         users:(("nginx",pid=2457,fd=6),("nginx",pid=2456,fd=6))
tcp   LISTEN 0      128    0.0.0.0:22          0.0.0.0:*         users:(("sshd",pid=1123,fd=3))
tcp   LISTEN 0      128    [::]:22             [::]:*            users:(("sshd",pid=1123,fd=4))
```

**What I understood:** `ip addr` = `ifconfig` (shows CIDR directly, `/24`, instead of a hex mask),
`ip route` = `netstat -rn`, `ip neigh` = `arp -a`. `ss -tulpn` = TCP (`t`), UDP (`u`), listening
(`l`), process (`p`), numeric (`n`): the one command I would run first on any server to see which
services are exposed.

### Overall takeaways

1. Connectivity problems are debugged layer by layer: interface up? (`ifconfig`/`ip a`) → route?
   (`netstat -rn`/`ip route`) → gateway reachable? (`ping` gateway) → internet by IP? (`ping 8.8.8.8`)
   → DNS? (`dig`/`nslookup`) → service? (`curl -I`, `ss`/`lsof`).
2. My laptop sits behind two levels of NAT (home router + ISP CGNAT), which is why the interface IP,
   the DHCP range, and the public IP are all different.
3. DNS answers are cached (TTL) and can come from different resolvers; always know which server
   answered (`scutil --dns`, `resolv.conf`).

## Screenshots

| Spec item | Stand-in in this README |
|---|---|
| Output/screenshot of each networking command | `Output (captured 2026-10-07)` block under each command in Task 2 |
| Linux `ip` / `ss` commands | `Expected output` block in the "Linux equivalents" subsection |

## Deliverables

- `homework/session04-networking/README.md` – Task 1 summary of the IP/subnetting notes and resource repos with worked subnetting examples; Task 2 every networking command executed with real output and a "What I understood" explanation, plus Linux equivalents.
