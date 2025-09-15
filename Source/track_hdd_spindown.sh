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
