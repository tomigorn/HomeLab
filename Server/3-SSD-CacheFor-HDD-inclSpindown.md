# SSD as cache for HDD, HDD with spindown
The goal is to set one SSD as the cache for an HDD and to let the HDD spindown whenever possible.

The Hardware is one 8TB SSD and one 30TB HDD.

> This process will delete everything on both drives!

## 1. Identify the devices

```bash
$ lsblk
NAME                      MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
sda                         8:0    0  27.3T  0 disk 
└─sda1                      8:1    0  27.3T  0 part 
sdb                         8:16   0   7.3T  0 disk 
└─sdb1                      8:17   0   7.3T  0 part 
nvme0n1                   259:0    0 931.5G  0 disk 
├─nvme0n1p1               259:1    0     1G  0 part /boot/efi
├─nvme0n1p2               259:2    0     2G  0 part /boot
└─nvme0n1p3               259:3    0 928.5G  0 part 
  └─ubuntu--vg-ubuntu--lv 252:0    0   100G  0 lvm  /
```

## 2. Install required tools

```bash
$ sudo apt update
$ sudo apt install -y bcache-tools hdparm util-linux wipefs xfsprogs
E: Unable to locate package wipefs
$ which wipefs
/usr/sbin/wipefs
```

Don't worry about this error message as wipefs is already part of Ubuntu and installed in the base system

## 3. Wipe all data on both drives

```bash
$ sudo wipefs -a /dev/sda1
/dev/sda1: 16 bytes were erased at offset 0x00001018 (bcache): c6 85 73 f6 4e 1a 45 ca 82 65 f5 7f 48 ba 6d 81

$ sudo wipefs -a /dev/sdb1
```

## 4. Set the SSD as the cache drive for the HDD

```bash
$ sudo make-bcache -C /dev/sda1 -B /dev/sdb1
UUID:                   REDACTED
Set UUID:               REDACTED
version:                0
nbuckets:               57221119
block_size:             1
bucket_size:            1024
nr_in_set:              1
nr_this_dev:            0
first_bucket:           1
UUID:                   REDACTED
Set UUID:               REDACTED
version:                1
block_size:             1
data_offset:            16

```

## 5. Verify the bcache device now exists

```bash
$ ls -l /dev/bcache*
brw-rw---- 1 root disk 251, 0 Sep 15 00:01 /dev/bcache0
/dev/bcache:
total 0
drwxr-xr-x 2 root root 60 Sep 15 00:01 by-uuid

$ cat /sys/block/bcache0/bcache/cache_mode
[writethrough] writeback writearound none

```

## 6. Tune sequential cutoff

```bash
$ echo writearound | sudo tee /sys/block/bcache0/bcache/cache_mode
writearound

$ cat /sys/block/bcache0/bcache/cache_mode
writethrough writeback [writearound] none

$ echo 0 | sudo tee /sys/block/bcache0/bcache/sequential_cutoff
0
```

## 7. Make filesystem and mount

```bash
$ sudo mkfs.xfs -f /dev/bcache0
meta-data=/dev/bcache0           isize=512    agcount=8, agsize=268435455 blks
         =                       sectsz=512   attr=2, projid32bit=1
         =                       crc=1        finobt=1, sparse=1, rmapbt=1
         =                       reflink=1    bigtime=1 inobtcount=1 nrext64=0
data     =                       bsize=4096   blocks=1953506302, imaxpct=5
         =                       sunit=0      swidth=0 blks
naming   =version 2              bsize=4096   ascii-ci=0, ftype=1
log      =internal log           bsize=4096   blocks=521728, version=2
         =                       sectsz=512   sunit=0 blks, lazy-count=1
realtime =none                   extsz=4096   blocks=0, rtextents=0
Discarding blocks...Done.



$ sudo mkdir -p /mnt/storage

$ sudo mount -o noatime,nodiratime /dev/bcache0 /mnt/storage
```

## 8. Get the UUID and add it to /etc/fstab
```bash
$ sudo blkid /dev/bcache0
/dev/bcache0: UUID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" BLOCK_SIZE="512" TYPE="xfs"

$ sudo nano /etc/fstab
# /etc/fstab: static file system information.
#
# Use 'blkid' to print the universally unique identifier for a
# device; this may be used with UUID= as a more robust way to name devices
# that works even if disks are added and removed. See fstab(5).
#
# <file system> <mount point>   <type>  <options>       <dump>  <pass>

# SSD Cache for HDD Drive 
UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx /mnt/storage xfs noatime,nodiratime,defaults 0 0
```

## 9. Persistent cache settings across boot
```bash
$ sudo nano /etc/systemd/system/bcache-tune.service
[Unit]
Description=Tune bcache parameters
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo writearound > /sys/block/bcache0/bcache/cache_mode; echo 0 > /sys/block/bcache0/bcache/sequential_cutoff'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

And enable it:

```bash
$ sudo systemctl daemon-reload
$ sudo systemctl enable --now bcache-tune.service
Created symlink /etc/systemd/system/multi-user.target.wants/bcache-tune.service → /etc/systemd/system/bcache-tune.service.
```

## 10. Configure HDD spindown to be 10mins
```bash
$ sudo hdparm -S 120 /dev/sdb
/dev/sdb:
 setting standby to 120 (10 minutes)

$ sudo hdparm -C /dev/sdb
/dev/sdb:
 drive state is:  active/idle
```

Make it permanent by editing /etc/hdparm.conf :

```bash
$ sudo nano /etc/hdparm.conf
/dev/sdb {
    spindown_time = 120
}
```

Check that SMART monitoring is either disabled or doesn't even come up.

```bash
$ sudo systemctl stop smartd
Failed to stop smartd.service: Unit smartd.service not loaded.
$ sudo systemctl disable smartd
Failed to disable unit: Unit file smartd.service does not exist.

$ systemctl list-units | grep -i smart
$ systemctl list-unit-files | grep -i smart
smartcard.target                                                              static          -

$ grep -r updatedb /etc/cron*
$ systemctl list-timers | grep updatedb
```

## 11. disable additional things

only if you don't have a desktop. since we're on a server, that's ok.
```bash
$ systemctl status udisks2.service
● udisks2.service - Disk Manager
     Loaded: loaded (/usr/lib/systemd/system/udisks2.service; enabled; preset: enabled)
     Active: active (running) since Sun 2025-09-14 21:53:23 UTC; 2h 35min ago
       Docs: man:udisks(8)
   Main PID: 909 (udisksd)
      Tasks: 6 (limit: 76842)
     Memory: 10.0M (peak: 11.1M)
        CPU: 762ms
     CGroup: /system.slice/udisks2.service
             └─909 /usr/libexec/udisks2/udisksd

Sep 14 21:53:22 beefy systemd[1]: Starting udisks2.service - Disk Manager...
Sep 14 21:53:22 beefy udisksd[909]: udisks daemon version 2.10.1 starting
Sep 14 21:53:23 beefy systemd[1]: Started udisks2.service - Disk Manager.
Sep 14 21:53:23 beefy udisksd[909]: Acquired the name org.freedesktop.UDisks2 on the system message bus


$ sudo systemctl disable --now udisks2.service
Removed "/etc/systemd/system/graphical.target.wants/udisks2.service".
```

## 12. make sure no logs are written to /mnt/storage
The second output is empty, which is good.

The Journal tells us, there is no Storage= configured, which is also good.
```bash
$ mount | grep /mnt/storage
/dev/bcache0 on /mnt/storage type xfs (rw,noatime,nodiratime,attr2,inode64,logbufs=8,logbsize=32k,noquota)

$ sudo lsof +D /mnt/storage


$ cat /etc/systemd/journald.conf | grep -v '^#'
[Journal]


# check both files, that there are no rules that write logs to /mnt/storage
$ nano /etc/rsyslog.conf
$ nano /etc/rsyslog.d/
```

## 13. Write a file tracknig the state of the HDD
```bash
$ sudo apt update
$ sudo apt install -y smartmontools

$ mkdir -p ~/Documents
```

```bash
$ nano ~/Projects/Source/track_hdd_spindown.sh
#!/bin/bash

# Log file
LOGFILE=~/Documents/hdd_spindown.log

# Get timestamp
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Check HDD state without spinning it up
STATE=$(sudo smartctl -n standby -i /dev/sdb | grep -i "Device is in")

# Fallback: if no match, just say unknown
if [ -z "$STATE" ]; then
    STATE="State unknown"
fi

# Write to log
echo "$TIMESTAMP - $STATE" >> "$LOGFILE"
```
```bash
$ chmod +x ~/Projects/Source/track_hdd_spindown.sh

# Test manually
$ ~/Projects/Source/track_hdd_spindown.sh
$ cat ~/Documents/hdd_spindown.log

```