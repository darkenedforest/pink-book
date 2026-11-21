#!/bin/sh
# Pure host test: mock both the tablet service manager and the reader.
set -eu

source_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
temp_dir=$(mktemp -d)
trap 'rm -r -- "$temp_dir"' 0
cp "$source_dir/run-on-tablet.sh" "$temp_dir/"
cd "$temp_dir"
export PATH="$temp_dir:$PATH"

cat > systemctl <<'MOCK'
#!/bin/sh
printf '%s\n' "$*" >> log
case "$1" in
    is-active) test "${MOCK_INACTIVE:-0}" = 0 ;;
    stop) test "${MOCK_STOP_FAIL:-0}" = 0 ;;
    start) test "${MOCK_START_FAIL:-0}" = 0 ;;
    *) exit 2 ;;
esac
MOCK
cat > pink-book-reader <<'MOCK'
#!/bin/sh
[ "$QT_QUICK_BACKEND" = epaper ] && [ "$*" = '-platform epaper' ] || exit 2
printf 'reader\n' >> log
if [ "${MOCK_INTERRUPT:-0}" = 1 ]; then
    kill -TERM "$PPID"
    sleep 1
fi
exit "${MOCK_READER_EXIT:-0}"
MOCK
chmod +x systemctl pink-book-reader

check() {
    expected=$1
    expected_log=$2
    shift 2
    : > log
    result=0
    env "$@" sh ./run-on-tablet.sh || result=$?
    [ "$result" -eq "$expected" ]
    [ "$(cat log)" = "$expected_log" ]
    [ ! -e .pink-book-reader.lock ]
}

probe='is-active --quiet xochitl.service'
stop='stop xochitl.service'
start='start xochitl.service'
full=$(printf '%s\n' "$probe" "$stop" reader "$start")
check 0 "$full"
check 42 "$full" MOCK_READER_EXIT=42
check 143 "$full" MOCK_INTERRUPT=1
check 1 "$probe" MOCK_INACTIVE=1
check 1 "$(printf '%s\n' "$probe" "$stop" "$start")" MOCK_STOP_FAIL=1
check 1 "$full" MOCK_START_FAIL=1
mkdir .pink-book-reader.lock
: > log
if sh ./run-on-tablet.sh; then
    echo "The existing lock was ignored" >&2
    exit 1
fi
[ ! -s log ]
printf '%s\n' 'Launcher tests passed (normal exit, reader error, interruption, inactive/failed stock UI, duplicate launch).'
