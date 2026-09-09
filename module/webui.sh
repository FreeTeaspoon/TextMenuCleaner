#!/system/bin/sh
MODDIR=${0%/*}

write_conf() {
    printf 'search=%s\ntranslate=%s\nask=%s\nai_rewrite=%s\nphrases=%s\n' \
        "${1:-1}" "${2:-1}" "${3:-1}" "${4:-1}" "${5:-1}" > "$MODDIR/menu.conf"
}

case "${1:-}" in
    status)
        if [ -f "$MODDIR/menu.conf" ]; then
            cat "$MODDIR/menu.conf"
        else
            write_conf 1 1 1 1 1
            cat "$MODDIR/menu.conf"
        fi
        printf '\n---\n'
        tail -n 1 "$MODDIR/status.log" 2>/dev/null || true
        ;;
    apply)
        write_conf "${2:-1}" "${3:-1}" "${4:-1}" "${5:-1}" "${6:-1}"
        /system/bin/sh "$MODDIR/apply.sh" >> "$MODDIR/status.log" 2>&1
        code=$?
        tail -n 1 "$MODDIR/status.log" 2>/dev/null || true
        exit "$code"
        ;;
    *)
        echo "Usage: webui.sh status|apply <search> <translate> <ask> <ai_rewrite> <phrases>" >&2
        exit 2
        ;;
esac
