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