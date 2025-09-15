#!/usr/bin/env bash
set -euo pipefail

# Usage: track_hdd_spindown.sh /dev/disk/by-id/ata-... [logfile]
# Checks HDD power state without forcing spinup. Prefers smartctl, falls back to sdparm/hdparm.

# Hardcoded target device (replace with your chosen persistent by-id)
HDD_BY_ID="/dev/disk/by-id/ata-ST30000NM004K-3RM133_K1S05Y9M"
LOGFILE="${1:-$HOME/Documents/hdd_spindown.log}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

STATE=""

# Helper: run a command as root. Try sudo -n (no prompt) first; if that fails, fall back to sudo (may prompt).
run_cmd() {
  if sudo -n true 2>/dev/null; then
    sudo -n bash -c "$1"
  else
    sudo bash -c "$1"
  fi
}

# 1) Try smartctl (preferred: non-spinning check with -n standby)
if command -v smartctl >/dev/null 2>&1; then
  out=$(run_cmd "smartctl -n standby -i '$HDD_BY_ID'" 2>/dev/null || true)
  STATE=$(printf "%s" "$out" | awk 'BEGIN{IGNORECASE=1} /Device is in/ {sub(/.*Device is in[[:space:]]*/,"",$0); print; exit} /Power mode was:/ {sub(/.*Power mode was:[[:space:]]*/,"",$0); print; exit} /Power mode is:/ {sub(/.*Power mode is:[[:space:]]*/,"",$0); print; exit}')
fi

# 2) Try sdparm (useful for SCSI/SAS/backplane devices)
if [ -z "$STATE" ] && command -v sdparm >/dev/null 2>&1; then
  out=$(run_cmd "sdparm --get=STANDBY '$HDD_BY_ID'" 2>/dev/null || true)
  STATE=$(printf "%s" "$out" | sed -n 's/.*\(STANDBY\|standby\).*:\s*\([^ ]*\).*/\2/p' | head -n1 || true)
fi

# 3) Fallback to hdparm -C
if [ -z "$STATE" ] && command -v hdparm >/dev/null 2>&1; then
  out=$(run_cmd "hdparm -C '$HDD_BY_ID'" 2>/dev/null || true)
  STATE=$(printf "%s" "$out" | sed -n 's/.*drive state is:[[:space:]]*//Ip' | head -n1 || true)
fi

# Normalize/cleanup
STATE=$(printf "%s" "$STATE" | sed 's/^\s*//;s/\s*$//')
if [ -z "$STATE" ]; then
  STATE="State unknown"
fi

mkdir -p "$(dirname "$LOGFILE")"
echo "$TIMESTAMP - $STATE" >> "$LOGFILE"
echo "$TIMESTAMP - $STATE"
