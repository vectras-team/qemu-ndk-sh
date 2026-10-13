#!/usr/bin/env bash
set -euo pipefail
task_repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
task_spice="${SPICE_SERVER_SRC:-$task_repo/build/_src/spice-0.15.2}"
task_protocol="${SPICE_PROTOCOL_ROOT:-$task_repo/build/sysroot-${APP_ABI:-arm64-v8a}/include/spice-1}"
task_test=$(mktemp -d)
trap 'rm -rf "$task_test"' EXIT
cc -g -fsanitize=address,undefined -fno-omit-frame-pointer \
    -include "$task_repo/tests/memslot-test-env.h" \
    -I"$task_repo/tests" -I"$task_spice" -I"$task_spice/server" \
    -I"$task_spice/subprojects/spice-common" -I"$task_protocol" \
    $(pkg-config --cflags glib-2.0) \
    "$task_repo/tests/memslot-crash-test.c" "$task_spice/server/memslot.c" \
    $(pkg-config --libs glib-2.0) -o "$task_test/memslot-crash-test"
"$task_test/memslot-crash-test"
