# how to wake the server from hybernation

## option 1: Physical input: press the server’s power button or a keyboard key (if BIOS/firmware supports it). This is the simplest wake method.

## option 2: Wake-on-LAN (magic packet)
enable WOL on the server
```bash
# find interface and MAC, here it's Nr 2
$ ip link
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
2: enp6s0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP mode DEFAULT group default qlen 1000
    link/ether aa:aa:aa:aa:aa:aa brd ff:ff:ff:ff:ff:ff
3: docker0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP mode DEFAULT group default 
    link/ether bb:bb:bb:bb:bb:bb brd ff:ff:ff:ff:ff:ff
4: veth3039255@if2: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master docker0 state UP mode DEFAULT group default 
    link/ether xx:xx:xx:xx:xx:xx brd ff:ff:ff:ff:ff:ff link-netnsid 0

# you can double check it with the ip. i expect it to be the one with 102 and can confirm it here
$ ip -brief addr show
lo               UNKNOWN        127.0.0.1/8 ::1/128 
enp6s0           UP             192.168.1.102/24 metric 100 xxxx::xxxx:xxxx:xxxx:xxxx/64 
docker0          UP             172.17.0.1/16 xxxx:xxxxx:xxxx:xxxx:xxxx/64 
veth3039255@if2  UP             xxxx::xxxx:xxxx:xxxx:xxxx/64 

# check WOL support. 
# Supports Wake-on: pumbg. because there is a g in the output, it is supported.
# Wake-on: d. means it is disabeled
$ sudo ethtool enp6s0 | egrep -i 'Supported|Wake-on|Link detected'
        Supported ports: [ TP    MII ]
        Supported link modes:   10baseT/Half 10baseT/Full
        Supported pause frame use: Symmetric Receive-only
        Supported FEC modes: Not reported
        Supports Wake-on: pumbg
        Wake-on: d
        Link detected: yes

# enable WOL (example eth0)
$ sudo ethtool -s enp6s0 wol g

# verify
$ sudo ethtool enp6s0 | grep -i wake
        Supports Wake-on: pumbg
        Wake-on: g
```
now let's make the configuration persistent across reboots with systemd unit:
```bash
# write a new systemd unit file
$ sudo nano /etc/systemd/system/wol@.service
[Unit]
Description=Enable Wake-on-LAN on %i
After=network-pre.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/ethtool -s %i wol g
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```
install and enable the service
```bash
# reload systemd, enable and start the instance for your NIC (replace enp6s0 if different)
$ sudo systemctl daemon-reload
$ sudo systemctl enable --now wol@enp6s0.service
Created symlink /etc/systemd/system/multi-user.target.wants/wol@enp6s0.service → /etc/systemd/system/wol@.service.

# verify service and WOL state
$ sudo systemctl status wol@enp6s0.service --no-pager
● wol@enp6s0.service - Enable Wake-on-LAN on enp6s0
     Loaded: loaded (/etc/systemd/system/wol@.service; enabled; preset: enabled)
     Active: active (exited) since Tue 2025-09-16 00:17:42 CEST; 25s ago
    Process: 3680 ExecStart=/usr/sbin/ethtool -s enp6s0 wol g (code=exited, status=0/SUCCESS)
   Main PID: 3680 (code=exited, status=0/SUCCESS)
        CPU: 3ms

Sep 16 00:17:42 beefy systemd[1]: Starting wol@enp6s0.service - Enable Wake-on-LAN on enp6s0...
Sep 16 00:17:42 beefy systemd[1]: Finished wol@enp6s0.service - Enable Wake-on-LAN on enp6s0.

$ sudo ethtool enp6s0 | egrep -i 'Supports Wake-on|Wake-on'
        Supports Wake-on: pumbg
        Wake-on: g
```

### test WOL
on the server itself
```bash
# get the mac address and verify WOL is enabled
$ ip -br addr show enp6s0
enp6s0           UP             192.168.1.102/24 metric 100 xxxx::xxxx:xxxx:xxxx:xxxx/64 

$ cat /sys/class/net/enp6s0/address
zz:zz:zz:zz:zz:zz

# should contain g under Supports Wake on, g under Wake-on and Link detected: yes
$ sudo ethtool enp6s0 | egrep -i 'Supports Wake-on|Wake-on|Link detected'
        Supports Wake-on: pumbg
        Wake-on: g
        Link detected: yes

# send the server to hybernation. it will become non-responsive
$ sudo systemctl hibernate
```

on a second machine install a magic-package sender and send the package
```bash
$ sudo apt update
# alternative is etherwake
$ sudo apt install -y wakeonlan

# confirm the server is sleeping
$ ping -c 4 192.168.1.102
PING 192.168.1.102 (192.168.1.102) 56(84) bytes of data.

--- 192.168.1.102 ping statistics ---
4 packets transmitted, 0 received, 100% packet loss, time 3060ms

# confirm the server is sleeping
$ ssh buntu@beefy
ssh: connect to host beefy port 22: No route to host

# taking the mac from before, send the wakeonlan command
$ wakeonlan zz:zz:zz:zz:zz:zz
Sending magic packet to 255.255.255.255:9 with zz:zz:zz:zz:zz:zz

# confirm the server woke
# first ping, immediatly after wake on lan magic package will fail
$ ping -c 4 192.168.1.102
PING 192.168.1.102 (192.168.1.102) 56(84) bytes of data.
From 192.168.1.100 icmp_seq=1 Destination Host Unreachable
From 192.168.1.100 icmp_seq=2 Destination Host Unreachable
From 192.168.1.100 icmp_seq=3 Destination Host Unreachable
From 192.168.1.100 icmp_seq=4 Destination Host Unreachable

--- 192.168.1.102 ping statistics ---
4 packets transmitted, 0 received, +4 errors, 100% packet loss, time 3075ms
pipe 3

# after some time the server is again online
$ ping -c 4 192.168.1.102
PING 192.168.1.102 (192.168.1.102) 56(84) bytes of data.
64 bytes from 192.168.1.102: icmp_seq=1 ttl=64 time=0.269 ms
64 bytes from 192.168.1.102: icmp_seq=2 ttl=64 time=0.159 ms
64 bytes from 192.168.1.102: icmp_seq=3 ttl=64 time=0.139 ms
64 bytes from 192.168.1.102: icmp_seq=4 ttl=64 time=0.146 ms

--- 192.168.1.102 ping statistics ---
4 packets transmitted, 4 received, 0% packet loss, time 3050ms
rtt min/avg/max/mdev = 0.139/0.178/0.269/0.052 ms

# also ssh now works again
$ ssh buntu@beefy
```

### Troubleshooting high CPU usage after wake up, resulting in very high power usage

in btop we can nicely see, that all cores are above 95% usage. this is insane.

There is no easy way to copy paste btop output, so here is the output from mpstat:
```bash
$ mpstat -P ALL
Linux 6.8.0-79-generic (beefy) 	09/16/2025 	_x86_64_	(12 CPU)

01:10:27 AM  CPU    %usr   %nice    %sys %iowait    %irq   %soft  %steal  %guest  %gnice   %idle
01:10:28 AM  all    2.16    0.00   97.26    0.00    0.00    0.00    0.00    0.00    0.00    0.58
01:10:28 AM    0    3.00    0.00   96.00    0.00    0.00    0.00    0.00    0.00    0.00    1.00
01:10:28 AM    1    1.98    0.00   97.03    0.00    0.00    0.00    0.00    0.00    0.00    0.99
01:10:28 AM    2    2.00    0.00   97.00    0.00    0.00    0.00    0.00    0.00    0.00    1.00
01:10:28 AM    3    2.00    0.00   98.00    0.00    0.00    0.00    0.00    0.00    0.00    0.00
01:10:28 AM    4    2.00    0.00   98.00    0.00    0.00    0.00    0.00    0.00    0.00    0.00
01:10:28 AM    5    2.00    0.00   97.00    0.00    0.00    0.00    0.00    0.00    0.00    1.00
01:10:28 AM    6    2.00    0.00   98.00    0.00    0.00    0.00    0.00    0.00    0.00    0.00
01:10:28 AM    7    2.94    0.00   96.08    0.00    0.00    0.00    0.00    0.00    0.00    0.98
01:10:28 AM    8    2.94    0.00   96.08    0.00    0.00    0.00    0.00    0.00    0.00    0.98
01:10:28 AM    9    1.01    0.00   98.99    0.00    0.00    0.00    0.00    0.00    0.00    0.00
01:10:28 AM   10    2.00    0.00   98.00    0.00    0.00    0.00    0.00    0.00    0.00    0.00
01:10:28 AM   11    1.96    0.00   97.06    0.00    0.00    0.00    0.00    0.00    0.00    0.98
```

if we have a look at what this huge usage is caused by, we can see that it is the vscode server doing a workspace search / indexing after being resumed. The hot processes are ripgrep (rg) and node instances started by VS Code server.
```bash
top -b -n1 -o %CPU | sed -n '1,20p'
top - 00:44:35 up 12 min,  2 users,  load average: 21.89, 17.80, 9.85
Tasks: 246 total,   3 running, 243 sleeping,   0 stopped,   0 zombie
%Cpu(s):  2.5 us, 97.5 sy,  0.0 ni,  0.0 id,  0.0 wa,  0.0 hi,  0.0 si,  0.0 st 
MiB Mem :  64115.8 total,  56519.5 free,   7357.1 used,    961.2 buff/cache     
MiB Swap:  65536.0 total,  65536.0 free,      0.0 used.  56758.7 avail Mem 

    PID USER      PR  NI    VIRT    RES    SHR S  %CPU  %MEM     TIME+ COMMAND
   2906 buntu     20   0  262592  29336   3200 S 516.7   0.0  61:43.90 rg
   3121 buntu     20   0   92608  11160   3200 S 450.0   0.0  21:54.54 rg
   2546 buntu     20   0   15.0g   3.1g  51968 R  58.3   4.9   7:17.32 node
     17 root      20   0       0      0      0 I   8.3   0.0   0:00.37 rcu_pre+
   2733 buntu     20   0   54.4g   2.6g  60232 R   8.3   4.2   1:18.09 node
   3910 buntu     20   0   11904   5504   3456 R   8.3   0.0   0:00.01 top
      1 root      20   0   22216  12792   9336 S   0.0   0.0   0:01.84 systemd
      2 root      20   0       0      0      0 S   0.0   0.0   0:00.00 kthreadd
      3 root      20   0       0      0      0 S   0.0   0.0   0:00.00 pool_wo+
      4 root       0 -20       0      0      0 I   0.0   0.0   0:00.00 kworker+
      5 root       0 -20       0      0      0 I   0.0   0.0   0:00.00 kworker+
      6 root       0 -20       0      0      0 I   0.0   0.0   0:00.00 kworker+
      7 root       0 -20       0      0      0 I   0.0   0.0   0:00.00 kworker+
buntu@beefy:/$ ps -eo pid,ppid,cmd,%cpu,%mem --sort=-%cpu | head -n20
    PID    PPID CMD                         %CPU %MEM
   2906    2733 /home/buntu/.vscode-server/  805  0.0
   3121    2733 /home/buntu/.vscode-server/  452  0.0
   2546       1 /home/buntu/.vscode-server/ 85.6  4.9
   2733    1754 /home/buntu/.vscode-server/ 16.5  4.2
   2744    1754 /home/buntu/.vscode-server/  1.9  0.1
   1754    1750 /home/buntu/.vscode-server/  0.3  0.1
      1       0 /sbin/init                   0.2  0.0
    110       2 [kworker/5:1-events_freezab  0.1  0.0
     49       2 [kworker/5:0-i915-unordered  0.1  0.0
   1807    1754 /home/buntu/.vscode-server/  0.1  0.1
   2700    2682 /home/buntu/.vscode-server/  0.1  0.0
```

To make this not recur after waking up from hybernation, we can exclude our very large 8TB & 30TB mount. we can create the file /home/buntu/.vscode-server/data/Machine/settings.json and add this:
```bash
{
  "files.watcherExclude": {
    "/mnt/storage/**": true
  },
  "search.exclude": {
    "/mnt/storage": true
  },
  "search.followSymlinks": false
}
```
 and after we can either reboot or restart the vscode-server
 ```bash
 pkill -f "vscode-server" || true
 ```
 after the next wake up from hybernation the issue will be resolved