#!/system/bin/sh
MODDIR=${0%/*}
/system/bin/sh "$MODDIR/apply.sh" >> "$MODDIR/status.log" 2>&1
