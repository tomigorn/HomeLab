# Hybernation of Ubuntu Server

The goal is that the server can go to deep sleep hybernation

## 1. try the easy way
```bash
$ cat /sys/power/state
freeze mem disk

$ swapon --show
NAME      TYPE SIZE USED PRIO
/swap.img file   8G   0B   -2

$ systemctl hibernate
Call to Hibernate failed: Not enough suitable swap space for hibernation available on compatible block devices and file systems
```

## 2. Delete old, small Swap and create a new bigger one
As it didn't work, we need to configure everything by hand.

```bash
# show RAM. here it's 62Gi
$ free -h
               total        used        free      shared  buff/cache   available
Mem:            62Gi       2.6Gi        59Gi       1.8Mi       1.3Gi        59Gi
Swap:          8.0Gi          0B       8.0Gi

# disable current swap
$ sudo swapoff /swap.img

# delete the old swap and create a new one 64G (adjust size >= your RAM)
$ sudo rm /swap.img
$ sudo fallocate -l 64G /swap.img || sudo dd if=/dev/zero of=/swap.img bs=1M count=$((64*1024))

# secure and enable
$ sudo chmod 600 /swap.img
$ sudo mkswap /swap.img
Setting up swapspace version 1, size = 64 GiB (68719472640 bytes)
no label, UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
$ sudo swapon /swap.img

# verify
$ swapon --show
NAME      TYPE SIZE USED PRIO
/swap.img file  64G   0B   -2
$ free -h
               total        used        free      shared  buff/cache   available
Mem:            62Gi       5.0Gi        56Gi       1.8Mi       1.3Gi        57Gi
Swap:           63Gi          0B        63Gi
```
Check that it is mounted at boot in /etc/fstab. check for the following line
```bash
$ sudo nano /etc/fstab
# swap partition is mounted on boot
/swap.img       none    swap    sw      0       0
```

## 3. Compute resume_offset and find the block device UUID
Check that filefrag is installed and set it up
```bash
$ sudo apt update
$ sudo apt install e2fsprogs
0 upgraded, 0 newly installed, 0 to remove and 6 not upgraded.

# get physical start offset (resume_offset)
$ OFFSET=$(sudo filefrag -v /swap.img | awk '/^ *0:/ {print $4}' | cut -d'.' -f1)
$ echo "resume_offset=$OFFSET"
resume_offset=4831232

# find the block device that contains /swap.img and its UUID
$ DEVICE=$(df --output=source /swap.img | tail -n1)
$ UUID=$(sudo blkid -s UUID -o value "$DEVICE")
$ echo "device=$DEVICE"
device=/dev/mapper/ubuntu--vg-ubuntu--lv
$ echo "uuid=$UUID"
uuid=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```
edit the grub file with the values you got before
```bash
$ sudo nano /etc/default/grub
# make sure to add rume=UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx and resume_offset=4831232
GRUB_CMDLINE_LINUX_DEFAULT="resume=UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx resume_offeset=4831232"
```
update boot/initramfs and reboot
```bash
$ sudo update-grub
Sourcing file `/etc/default/grub'
Generating grub configuration file ...
Found linux image: /boot/vmlinuz-6.8.0-79-generic
Found initrd image: /boot/initrd.img-6.8.0-79-generic
Warning: os-prober will not be executed to detect other bootable partitions.
Systems on them will not be added to the GRUB boot configuration.
Check GRUB_DISABLE_OS_PROBER documentation entry.
Adding boot menu entry for UEFI Firmware Settings ...
done

$ sudo update-initramfs -u -k all
update-initramfs: Generating /boot/initrd.img-6.8.0-79-generic

$ sudo reboot
```

## 4. Verify that it all worked

```bash
# confirm the kernel command line conaints resume args we added before
$ cat /proc/cmdline
BOOT_IMAGE=/vmlinuz-6.8.0-79-generic root=/dev/mapper/ubuntu--vg-ubuntu--lv ro resume=UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx resume_offeset=4831232

# confirm that swap is active
$ swapon --show
NAME      TYPE SIZE USED PRIO
/swap.img file  64G   0B   -2

# confirm that hybernation is supported. should contain "disk"
$ cat /sys/power/state
freeze mem disk

# if your over SSH, this will kill the connection. but this command will now put it to hybernation
$ systemctl hibernate
```
