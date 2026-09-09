#!/system/bin/sh
set -eu
MODDIR=${0%/*}
. "$MODDIR/config.sh"
touch "$MODDIR/disable"
# Restore every existing namespace containing our APK mount. Processes that already
# loaded its DEX retain it until restarted; disabling and rebooting is the full reset.
seen=' '
for proc in /proc/[0-9]*; do
    pid=${proc##*/}
    ns=$(readlink "$proc/ns/mnt" 2>/dev/null) || continue
    case "$seen" in *" $ns "*) continue ;; esac
    seen="$seen$ns "
    $BB awk -v target="$TARGET" '$5 == target {found=1} END {exit !found}' "$proc/mountinfo" 2>/dev/null || continue
    if $BB nsenter -t "$pid" -m $BB umount "$TARGET"; then
        echo "Restored stock editor in namespace of PID $pid"
    fi
done
echo 'Module disabled. Restart affected apps, or reboot for a complete reset.'
