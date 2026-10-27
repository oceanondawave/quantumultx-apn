#!/usr/bin/env python3
import sys
import os

def patch_tunnel_binary(tunnel_path):
    if not os.path.isfile(tunnel_path):
        print(f"Error: Tunnel binary not found at {tunnel_path}")
        sys.exit(1)

    with open(tunnel_path, "r+b") as f:
        # Patch 1: Enforce includeAllNetworks = YES permanently
        # Target instruction at 0x1e9848 in __TEXT, __text:
        # -[QTXPacketTunnelProvider handleNetworkEvent]_block_invoke_5
        # Original: 0x52800002 (mov w2, #0x0) -> [protocolConfiguration setIncludeAllNetworks:NO]
        # Patched:  0x52800022 (mov w2, #0x1) -> [protocolConfiguration setIncludeAllNetworks:YES]
        offset = 0x1e9848
        f.seek(offset)
        current_bytes = f.read(4)

        if current_bytes == bytes.fromhex("02008052"):
            f.seek(offset)
            f.write(bytes.fromhex("22008052"))
            print(f"[patch_tunnel] Successfully patched offset {hex(offset)}: mov w2, #0x0 -> mov w2, #0x1 (includeAllNetworks permanently YES)")
        elif current_bytes == bytes.fromhex("22008052"):
            print(f"[patch_tunnel] Offset {hex(offset)} already patched (mov w2, #0x1).")
        else:
            print(f"[patch_tunnel] Unexpected instruction at {hex(offset)}: {current_bytes.hex()}. Aborting!")
            sys.exit(1)

        # Patch 2: Disable sleepWithCompletionHandler: so iOS never suspends the tunnel on lock screen (matching Stash behavior)
        # Selector string at 0x57afab in __TEXT, __objc_methname:
        # Original: "sleepWithCompletionHandler:\0"
        # Patched:  "_leepWithCompletionHandler:\0"
        str_offset = 0x57afab
        f.seek(str_offset)
        curr_str = f.read(28)
        if curr_str == b"sleepWithCompletionHandler:\x00":
            f.seek(str_offset)
            f.write(b"_leepWithCompletionHandler:\x00")
            print(f"[patch_tunnel] Successfully disabled sleepWithCompletionHandler: (tunnel runs continuously 24/7 like Stash)")
        elif curr_str == b"_leepWithCompletionHandler:\x00":
            print(f"[patch_tunnel] sleepWithCompletionHandler: already disabled.")
        else:
            print(f"[patch_tunnel] Warning: Unexpected selector string at {hex(str_offset)}: {curr_str}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 patch_tunnel.py <path_to_Quantumult_X_Tunnel>")
        sys.exit(1)
    patch_tunnel_binary(sys.argv[1])
