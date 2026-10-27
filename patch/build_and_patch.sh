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
codesign -f -s - "$DIR/QuantumultXAPNs.dylib"

echo "=== 2. Extracting original IPA ==="
rm -rf "$BUILD_TMP"
mkdir -p "$BUILD_TMP"
unzip -q "$ORIGINAL_IPA" -d "$BUILD_TMP"

APP_PATH="$BUILD_TMP/Payload/Quantumult X.app"
FRAMEWORKS_PATH="$APP_PATH/Frameworks"
mkdir -p "$FRAMEWORKS_PATH"

echo "=== 3. Copying dylib to Frameworks ==="
cp "$DIR/QuantumultXAPNs.dylib" "$FRAMEWORKS_PATH/QuantumultXAPNs.dylib"

echo "=== 4. Injecting LC_LOAD_DYLIB into Mach-O ==="
python3 "$DIR/inject_dylib.py" "$APP_PATH/Quantumult X" "@executable_path/Frameworks/QuantumultXAPNs.dylib" "$APP_PATH/Quantumult X"

echo "=== 5. Patching Quantumult X Tunnel binary ==="
TUNNEL_APPEX="$APP_PATH/PlugIns/Quantumult X Tunnel.appex"
TUNNEL_BIN="$TUNNEL_APPEX/Quantumult X Tunnel"
python3 "$DIR/patch_tunnel.py" "$TUNNEL_BIN"

echo "=== 5.1. Injecting UIBackgroundModes into Quantumult X Info.plist ==="
python3 -c "
import plistlib
plist_path = '$APP_PATH/Info.plist'
with open(plist_path, 'rb') as f:
    plist = plistlib.load(f)
plist['UIBackgroundModes'] = ['audio', 'fetch', 'processing']
with open(plist_path, 'wb') as f:
    plistlib.dump(plist, f, fmt=plistlib.FMT_BINARY)
print('[build_and_patch] Successfully injected UIBackgroundModes: audio, fetch, processing')
"

echo "=== 6. Re-signing Tunnel Extension and App with Original Entitlements ==="
codesign -f -s - "$FRAMEWORKS_PATH/QuantumultXAPNs.dylib"
codesign -f -s - --entitlements "$DIR/tunnel.entitlements" "$TUNNEL_APPEX"
codesign -f -s - --entitlements "$DIR/app.entitlements" "$APP_PATH"

echo "=== 7. Packaging patched IPA ==="
rm -f "$OUTPUT_IPA"
cd "$BUILD_TMP"
zip -qry "$OUTPUT_IPA" Payload

echo "=== Done! Patched IPA created at: $OUTPUT_IPA ==="
