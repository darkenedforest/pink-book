#!/bin/sh
# Run the reader in the foreground over a USB SSH session; do not enable at boot.
set -eu

if [ "$#" -ne 0 ]; then
    printf '%s\n' "Usage: sh $0" >&2
    exit 2
fi

cd "$(dirname "$0")"
if [ ! -x ./pink-book-reader ]; then
    printf '%s\n' 'The executable pink-book-reader must be beside this script.' >&2
    exit 1
fi

lock=.pink-book-reader.lock
if ! mkdir "$lock" 2>/dev/null; then
    printf '%s\n' "Cannot acquire $lock; check whether the reader is already running." >&2
    exit 1
fi

child=''
restore_stock=0
cleanup() {
    result=$?
    trap - 0
    trap '' HUP INT TERM

    if [ -n "$child" ]; then
        kill -TERM "$child" 2>/dev/null || :
        wait "$child" 2>/dev/null || :
    fi
    if [ "$restore_stock" -eq 1 ]; then
        if ! systemctl start xochitl.service; then
            printf '%s\n' 'Could not restore the stock UI. Try: systemctl start xochitl.service' >&2
            result=1
        fi
    fi
    rmdir "$lock" || result=1
    exit "$result"
}
trap cleanup 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# If the stock UI is already off, another app could own the display.
if ! systemctl is-active --quiet xochitl.service; then
    printf '%s\n' 'The stock reMarkable UI is not running. Restore it before launching.' >&2
    exit 1
fi

# Mark restoration necessary before stopping the service, including stop errors.
restore_stock=1
systemctl stop xochitl.service
QT_QUICK_BACKEND=epaper ./pink-book-reader -platform epaper &
child=$!
result=0
wait "$child" || result=$?
child=''
exit "$result"
