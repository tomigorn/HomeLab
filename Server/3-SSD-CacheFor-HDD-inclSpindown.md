# SSD as cache for HDD, HDD with spindown
The goal is to set one SSD as the cache for an HDD and to let the HDD spindown whenever possible.

The Hardware is one 8TB SSD and one 30TB HDD.

> This process will delete everything on both drives!

## 1. Identify the devices (use stable identifiers)

Device node names like `/dev/sda` and `/dev/sdb` can change across reboots. Always map transient names to stable identifiers before doing destructive operations.

Get a human-friendly list of block devices:

```bash
$ lsblk -o NAME,MAJ:MIN,RM,SIZE,RO,TYPE,MOUNTPOINT,LABEL
NAME                      MAJ:MIN RM   SIZE RO TYPE MOUNTPOIN LABEL
sda                         8:0    0   7.3T  0 disk           
└─sda1                      8:1    0   7.3T  0 part           
sdb                         8:16   0  27.3T  0 disk           
└─sdb1                      8:17   0  27.3T  0 part           
nvme0n1                   259:0    0 931.5G  0 disk           
├─nvme0n1p1               259:1    0     1G  0 part /boot/efi 
├─nvme0n1p2               259:2    0     2G  0 part /boot     
└─nvme0n1p3               259:3    0 928.5G  0 part           
  └─ubuntu--vg-ubuntu--lv 252:0    0   100G  0 lvm  /    
```

List persistent by-id links (recommended for scripts):

```bash
$ ls -l /dev/disk/by-id
```

Get filesystem UUIDs (useful for fstab and consistent referencing):

```bash
$ sudo blkid
```

Example mapping workflow (record these before making changes):

```bash
# see transient device nodes
$ lsblk

# see persistent identifiers for the same device
$ ls -l /dev/disk/by-id | grep -i 'Samsung'   # or grep the model you expect

# find which by-id entry points at /dev/sda1 (example)
$ readlink -f /dev/disk/by-id/ata-Samsung_SSD_870_XXXXXXXXX-part1
/dev/sda1

# get the PARTUUID/UUID for fstab stable mounts
$ sudo blkid /dev/sda1
/dev/sda1: UUID="XXXXXXXX-..." TYPE="bcache" PARTUUID="XXXXXXXX-..."
```

Record the `by-id` path or the UUID and use that in later commands instead of `/dev/sd*`.

Examples in this document will show the persistent form: `/dev/disk/by-id/<...>` or `UUID=<...>`.

## 2. Install required tools

```bash
$ sudo apt update
$ sudo apt install -y bcache-tools hdparm util-linux wipefs xfsprogs
E: Unable to locate package wipefs
$ which wipefs
/usr/sbin/wipefs
```

Don't worry about this error message as wipefs is already part of Ubuntu and installed in the base system

## 3. Wipe all data on both drives (use stable ids)

Warning: This will destroy data on the referenced devices. Use the `by-id` path or UUID you recorded earlier.

Using `/dev/disk/by-id`:

```bash
# example: replace with the by-id path you recorded
$ sudo wipefs -a /dev/disk/by-id/ata-Samsung_SSD_870_XXXXXXXXX-part1
/dev/disk/by-id/ata-Samsung_SSD_870_CCCXXXXX-part1: 16 bytes were erased at offset 0x00001018 (bcache): ...

$ sudo wipefs -a /dev/disk/by-id/ata-WDC_WD30_...-part1
```

Or use the PARTUUID/UUID form (handy for fstab and systemd):

```bash
# use the printed UUID from blkid; this identifies the filesystem/superblock, not the block device node
$ sudo wipefs -a /dev/disk/by-uuid/XXXXXXXXX
```

If you prefer to clear entire partition tables (destructive):

```bash
$ sudo sgdisk --zap-all /dev/disk/by-id/ata-WDC_WD30_...   # operates on whole disk device
```

# Example: use persistent by-id devices for make-bcache

## 4. Set the SSD as the cache drive for the HDD (persistent device paths)

```bash
# replace the by-id paths with the ones you recorded earlier
$ sudo make-bcache -C /dev/disk/by-id/ata-Samsung_SSD_870_XXXXXXXXXX-part1 \
  -B /dev/disk/by-id/ata-WDC_WD30_XXXXXXXX-part1

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
$ echo writeback | sudo tee /sys/block/bcache0/bcache/cache_mode
writeback

$ cat /sys/block/bcache0/bcache/cache_mode
writethrough [writeback] writearound none

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

## Troubleshooting: `hdparm -C` reports "drive state is: unknown"

Sometimes `hdparm -C /dev/…` reports `drive state is: unknown`. This is often benign — it usually means the CHECK POWER MODE ATA command is not supported or is blocked by the controller/enclosure. Recommended checks and fallbacks:

1) Confirm you're addressing the whole-disk device (use by-id):

```bash
readlink -f /dev/disk/by-id/ata-...  # should point to /dev/sdX
```

2) Prefer `smartctl -n standby -i` for read-only, non-spinning checks (used by our tracking script):

```bash
sudo smartctl -n standby -i /dev/disk/by-id/ata-... 
# look for 'Device is in' or 'Power mode was:' in the output
```

3) Use `sdparm` for SCSI devices/enclosures if available:

```bash
sudo sdparm --get=STANDBY /dev/disk/by-id/...
```

4) If the disk is behind a RAID/HBA or an enclosure that doesn't passthrough ATA commands, configure spindown in the controller/firmware or use vendor tools.

5) If you must spin down immediately and it's safe (no mounted filesystems / no I/O), `sudo hdparm -y /dev/disk/by-id/ata-...` forces the disk to standby. Use with caution.

The `track_hdd_spindown.sh` script prefers `smartctl` and falls back to `hdparm` so it works across a wide range of hardware.

````markdown

## Fixing permissions for /mnt/storage (non-root write access)

If `/mnt/storage` is owned by `root:root` (the common default), unprivileged users won't be able to create files there. You have three low-risk options depending on how you want to manage access:

1) Change ownership to a specific user (simple, single-user systems)

```bash
# make the directory owned by the desired user
sudo chown alice:alice /mnt/storage

# verify
ls -ld /mnt/storage
# drwxr-xr-x 2 alice alice 4096 Sep 15 02:13 /mnt/storage
```

2) Use a dedicated group and setgid so new files inherit the group (recommended for multi-user systems)

```bash
# create a group, add users to it, set group ownership and setgid bit
sudo groupadd storageusers || true
sudo usermod -aG storageusers alice
sudo chown root:storageusers /mnt/storage
sudo chmod 2775 /mnt/storage   # setgid bit (2) + rwxrwxr-x (775)

# verify
ls -ld /mnt/storage
# drwxrwsr-x 2 root storageusers 4096 Sep 15 02:13 /mnt/storage
```

3) Use POSIX ACLs for fine-grained control (if you need per-user permissions)

```bash
# give user 'alice' full access while keeping root as owner
sudo setfacl -m u:alice:rwx /mnt/storage

# show ACLs
getfacl /mnt/storage
# file: mnt/storage
# owner: root
# group: root
# user::rwx
# user:alice:rwx
# group::r-x
# mask::rwx
# other::r-x
```

Notes and safety:
- If the filesystem is mounted by UUID in `/etc/fstab`, you can make these changes once and they will persist across reboots.
- Avoid making the mount world-writable (`chmod 777`) unless you understand the security implications.
- If multiple services write to `/mnt/storage` as different POSIX users (e.g., system services), prefer the group+setgid or ACL approaches and add service users to the group.

After applying one of the above, non-root users should be able to create files under `/mnt/storage`. If you still see permission errors, re-check the effective user/group of the process trying to write (for system services check the unit's `User=`/`Group=` in its systemd service file).
````