#!/system/bin/sh
[ "$KSU" = true ] || [ -n "${MAGISK_VER:-}" ] || [ "${APATCH:-}" = true ] || \
    abort 'This package requires KernelSU, Magisk, or APatch.'
. "$MODPATH/config.sh"
value=$($BB nsenter -t 1 -m $BB sha256sum "$TARGET")
[ "${value%% *}" = "$STOCK_SHA" ] || abort 'Original Miuix Editor does not match this patch.'
set_perm_recursive "$MODPATH" 0 0 0755 0644
for file in "$MODPATH"/*.sh; do set_perm "$file" 0 0 0755; done
# Magisk/KernelSU apply webroot context after this script. Leave that directory alone.
mkdir -p "$MODPATH/payload"
ui_print 'Tap Open in Magisk or KernelSU to choose which Xiaomi actions to hide.'
ui_print 'Applies after boot to new app processes. Restart apps after changes.'
