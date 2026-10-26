#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(cd "$DIR/.." && pwd)"
ORIGINAL_IPA="$PARENT_DIR/com.crossutility.quantumult-x_1.8.1_decrypted.ipa"
OUTPUT_IPA="$PARENT_DIR/com.crossutility.quantumult-x_1.8.1_apns_patched.ipa"
BUILD_TMP="/tmp/qx_apns_build"

echo "=== 1. Compiling QuantumultXAPNs.dylib for iOS (ARM64) ==="
clang -dynamiclib -target arm64-apple-ios14.0 \
  -Wl,-undefined,dynamic_lookup \
  -install_name "@executable_path/Frameworks/QuantumultXAPNs.dylib" \
  "$DIR/QuantumultXAPNs.m" -o "$DIR/QuantumultXAPNs.dylib"

echo "=== 2. Ad-hoc signing QuantumultXAPNs.dylib ==="
codesign -f -s - "$DIR/QuantumultXAPNs.dylib"

echo "=== 3. Extracting original IPA ==="
rm -rf "$BUILD_TMP"
mkdir -p "$BUILD_TMP"
unzip -q "$ORIGINAL_IPA" -d "$BUILD_TMP"

APP_PATH="$BUILD_TMP/Payload/Quantumult X.app"
FRAMEWORKS_PATH="$APP_PATH/Frameworks"
mkdir -p "$FRAMEWORKS_PATH"

echo "=== 4. Copying dylib to Frameworks ==="
cp "$DIR/QuantumultXAPNs.dylib" "$FRAMEWORKS_PATH/QuantumultXAPNs.dylib"

echo "=== 5. Injecting LC_LOAD_DYLIB into Mach-O ==="
python3 "$DIR/inject_dylib.py" "$APP_PATH/Quantumult X" "@executable_path/Frameworks/QuantumultXAPNs.dylib" "$APP_PATH/Quantumult X"

echo "=== 6. Re-signing App with FULL Original Entitlements ==="
# IMPORTANT: DO NOT re-sign Quantumult X Tunnel.appex to avoid breaking NetworkExtension entitlements.
# Only sign the injected dylib and the main app binary with its original entitlements preserved!
codesign -f -s - "$FRAMEWORKS_PATH/QuantumultXAPNs.dylib"
codesign -f -s - --entitlements "$DIR/app.entitlements" "$APP_PATH"

echo "=== 7. Packaging patched IPA ==="
cd "$BUILD_TMP"
zip -qry "$OUTPUT_IPA" Payload

echo "=== Done! Patched IPA created at: $OUTPUT_IPA ==="
