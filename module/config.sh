TARGET=/product/app/MiuixEditor/MiuixEditor.apk
# Compatibility follows the editor bytes, not the firmware build number.
STOCK_SHA=16cd2f078ac58c79be684ed210049dfad9fe59db681cb2ef66c0e50220ab3a29
BB=/data/adb/ksu/bin/busybox
for candidate in \
    /data/adb/ksu/bin/busybox \
    /data/adb/magisk/busybox \
    /data/adb/ap/bin/busybox
do
    if [ -x "$candidate" ]; then
        BB=$candidate
        break
    fi
done
