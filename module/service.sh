#!/system/bin/sh
MODDIR=${0%/*}
# KernelSU also runs boot-completed.sh after BOOT_COMPLETED.
[ "$KSU" = true ] && exit 0
while [ "$(getprop sys.boot_completed)" != 1 ]; do
    sleep 1
done
sleep 2
/system/bin/sh "$MODDIR/apply.sh" >> "$MODDIR/status.log" 2>&1
