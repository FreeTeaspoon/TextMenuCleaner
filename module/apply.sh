#!/system/bin/sh
set -eu
MODDIR=${0%/*}
. "$MODDIR/config.sh"
fail() { echo "SKIPPED: $*"; exit 1; }
[ ! -e "$MODDIR/disable" ] && [ ! -e "$MODDIR/remove" ] || fail 'module disabled'
[ "$(getprop sys.boot_completed)" = 1 ] || fail 'boot not completed'
[ "$(getprop ro.build.version.incremental)" = "$EXPECTED_BUILD" ] || fail 'firmware changed'
[ -x "$BB" ] || fail 'KernelSU BusyBox missing'
editor_path=''
for attempt in 1 2 3 4 5; do
    editor_path=$(pm path com.miuix.editor 2>/dev/null) || editor_path=''
    [ -n "$editor_path" ] && break
    sleep 2
done
[ "$editor_path" = "package:$TARGET" ] || fail 'editor path changed or Package Manager unavailable'
stock=$($BB nsenter -t 1 -m $BB sha256sum "$TARGET")
[ "${stock%% *}" = "$STOCK_SHA" ] || fail 'stock editor hash changed'
mkdir -p "$MODDIR/payload"
$BB nsenter -t 1 -m $BB cat "$TARGET" > "$MODDIR/payload/MiuixEditor.apk"
copied=$($BB sha256sum "$MODDIR/payload/MiuixEditor.apk")
[ "${copied%% *}" = "$STOCK_SHA" ] || fail 'failed to copy stock editor'
hide_any=0
if [ -f "$MODDIR/menu.conf" ]; then
    while IFS='=' read -r key value || [ -n "$key" ]; do
        case "$key" in
            search|translate|ask|ai_rewrite|phrases)
                value=${value%$'\r'}
                case "$value" in 1|true|TRUE) hide_any=1 ;; esac
                ;;
        esac
    done < "$MODDIR/menu.conf"
else
    hide_any=1
fi
unmount_editor() {
    init_ns=$(readlink /proc/1/ns/mnt)
    for pid in $(pidof zygote64 zygote); do
        ns=$(readlink "/proc/$pid/ns/mnt")
        [ "$ns" != "$init_ns" ] || continue
        $BB nsenter -t "$pid" -m $BB umount "$TARGET" 2>/dev/null || true
    done
}
if [ "$hide_any" -eq 0 ]; then
    unmount_editor
    echo "ACTIVE: no Xiaomi actions hidden. $(date)"
    exit 0
fi
APP_PROCESS=/system/bin/app_process64
[ -x "$APP_PROCESS" ] || APP_PROCESS=/system/bin/app_process
[ -x "$APP_PROCESS" ] || fail 'app_process missing'
[ -f "$MODDIR/payload/patcher.jar" ] || fail 'menu patcher missing'
[ -f "$MODDIR/payload/offsets.txt" ] || fail 'patch offsets missing'
CLASSPATH="$MODDIR/payload/patcher.jar"
export CLASSPATH
"$APP_PROCESS" /system/bin MenuPatcher \
    "$MODDIR/payload/MiuixEditor.apk" \
    "$MODDIR/menu.conf" \
    "$MODDIR/payload/offsets.txt" || fail 'menu patch failed'
patched=$($BB sha256sum "$MODDIR/payload/MiuixEditor.apk")
[ "${patched%% *}" != "$STOCK_SHA" ] || fail 'patch produced an unchanged editor'
chmod 644 "$MODDIR/payload/MiuixEditor.apk"
chcon u:object_r:system_file:s0 "$MODDIR/payload/MiuixEditor.apk"
PATCH_SHA=${patched%% *}
init_ns=$(readlink /proc/1/ns/mnt)
count=0
for pid in $(pidof zygote64 zygote); do
    ns=$(readlink "/proc/$pid/ns/mnt")
    [ "$ns" != "$init_ns" ] || fail 'zygote shares init mount namespace'
    current=$($BB nsenter -t "$pid" -m $BB sha256sum "$TARGET")
    case "${current%% *}" in
        "$PATCH_SHA") echo "Already active in zygote $pid" ;;
        "$STOCK_SHA")
            $BB nsenter -t "$pid" -m $BB mount --bind "$MODDIR/payload/MiuixEditor.apk" "$TARGET"
            ;;
        *)
            $BB nsenter -t "$pid" -m $BB umount "$TARGET" 2>/dev/null || true
            $BB nsenter -t "$pid" -m $BB mount --bind "$MODDIR/payload/MiuixEditor.apk" "$TARGET"
            ;;
    esac
    result=$($BB nsenter -t "$pid" -m $BB sha256sum "$TARGET")
    [ "${result%% *}" = "$PATCH_SHA" ] || fail "mount verification failed for $pid"
    count=$((count + 1))
done
[ "$count" -gt 0 ] || fail 'no zygote found'
echo "ACTIVE: $count zygote namespace(s). Restart already-running apps. $(date)"
