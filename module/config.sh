TARGET=/product/app/MiuixEditor/MiuixEditor.apk
EXPECTED_BUILD=OS4.0.0.24.XPKCNXM
STOCK_SHA=eae7c16ce451ca1ef5d3d1116582870617d597dad83d450470b356d68d1af29d
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
