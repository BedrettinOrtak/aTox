#!/usr/bin/env bash
# BTOX Android build script (Linux/macOS/WSL)
set -euo pipefail

PROFILE="${1:-release}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
RUST_DIR="$ROOT/rust"
JNI="$ROOT/flutter/android/app/src/main/jniLibs"

if [ -z "${ANDROID_NDK_HOME:-}" ]; then
  for c in "$HOME/Android/Sdk/ndk" "$ANDROID_HOME/ndk" "$ANDROID_SDK_ROOT/ndk"; do
    if [ -d "$c" ]; then
      ANDROID_NDK_HOME="$(ls -1d "$c"/* | sort -V | tail -1)"
      export ANDROID_NDK_HOME
      break
    fi
  done
fi
[ -n "${ANDROID_NDK_HOME:-}" ] || { echo "ANDROID_NDK_HOME yok. NDK kur."; exit 1; }
echo "NDK: $ANDROID_NDK_HOME"

ARGS=(ndk -t arm64-v8a -t armeabi-v7a -t x86_64 -t x86 -o "$JNI" build)
[ "$PROFILE" = "release" ] && ARGS+=(--release)

(cd "$RUST_DIR" && cargo "${ARGS[@]}")

echo
echo "Olusturulan kutuphaneler:"
find "$JNI" -name 'libbtox_core.so' -printf '  %-12P  %10s bytes\n'

