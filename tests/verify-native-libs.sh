#!/usr/bin/env bash
set -euo pipefail
task_repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
task_libs="${1:-$task_repo/opt/qemu/arm64-v8a/libs}"
: "${NDK_PATH:?Set NDK_PATH to the Android NDK directory}"
case "$(uname -s)" in
    Linux) task_host=linux-x86_64 ;;
    Darwin) task_host=darwin-x86_64 ;;
    *) printf 'Unsupported host\n' >&2; exit 1 ;;
esac
task_tools="$NDK_PATH/toolchains/llvm/prebuilt/$task_host/bin"
task_android30="$NDK_PATH/toolchains/llvm/prebuilt/$task_host/sysroot/usr/lib/aarch64-linux-android/30"
task_check=$(mktemp -d)
trap 'rm -rf "$task_check"' EXIT
for library in "$task_libs/"*.so; do
    "$task_tools/llvm-readelf" -h "$library" | grep -q 'Machine:.*AArch64'
    while read -r alignment; do
        if (( alignment < 16384 )); then
            printf 'Bad LOAD alignment: %s %s\n' "$library" "$alignment" >&2
            exit 1
        fi
    done < <("$task_tools/llvm-readelf" -l "$library" | awk '$1 == "LOAD" {print $NF}')
    while read -r dependency; do
        if [[ ! -f "$task_libs/$dependency" && ! -f "$task_android30/$dependency" ]]; then
            printf 'Missing runtime dependency: %s needs %s\n' "$library" "$dependency" >&2
            exit 1
        fi
    done < <("$task_tools/llvm-readelf" -d "$library" | sed -n 's/.*(NEEDED).*\[\(.*\)\].*/\1/p')
done
# Detect accidental use of APIs newer than the app's Android 11 minimum.
task_system_libs=()
for candidate in "$task_android30/"*.so; do
    # NDK's libc++.so is a linker script, not an ELF object. Its actual
    # shared implementation is already among the staged native libraries.
    if "$task_tools/llvm-readelf" -h "$candidate" >/dev/null 2>&1; then
        task_system_libs+=("$candidate")
    fi
done
"$task_tools/llvm-nm" -D --defined-only --format=posix "$task_libs/"*.so "${task_system_libs[@]}" |
    awk '$2 ~ /^[A-Za-z]$/ {sub(/@.*/, "", $1); print $1}' | sort -u > "$task_check/defined"
"$task_tools/llvm-nm" -D --undefined-only --format=posix "$task_libs/"*.so |
    awk '$2 == "U" {sub(/@.*/, "", $1); print $1}' | sort -u > "$task_check/required"
comm -23 "$task_check/required" "$task_check/defined" > "$task_check/missing"
if [[ -s "$task_check/missing" ]]; then
    printf 'Unresolved strong symbols against bundled libraries / Android API 30:\n' >&2
    head -n 60 "$task_check/missing" >&2
    exit 1
fi
"$task_tools/llvm-nm" -D --defined-only --format=posix "$task_libs/libqemu-system-x86_64.so" > "$task_check/qemu-symbols"
grep -q '^Java_com_vectras_qemu_jni_Loader_startQemu ' "$task_check/qemu-symbols"
grep -q '^android_qemu_start ' "$task_check/qemu-symbols"
"$task_tools/llvm-nm" -D --defined-only --format=posix "$task_libs/libqemu-img.so" > "$task_check/img-symbols"
grep -q '^main ' "$task_check/img-symbols"
printf 'Native audit passed: arm64, 16 KiB LOAD alignment, runtime dependencies, API 30 symbols, JNI exports.\n'
