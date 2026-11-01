#!/usr/bin/env python3
import sys
import os

def patch_tunnel_binary(tunnel_path):
    if not os.path.isfile(tunnel_path):
        print(f"Error: Tunnel binary not found at {tunnel_path}")
        sys.exit(1)

    with open(tunnel_path, "r+b") as f:
        # Patch 1: NOP out [protocolConfiguration setIncludeAllNetworks:] in handleNetworkEvent
        # Target instructions at 0x1e9848 - 0x1e984f in __TEXT, __text:
        # -[QTXPacketTunnelProvider handleNetworkEvent]_block_invoke_5
        # 0x1e9848: mov w2, #0x0 (0x52800002) or patched mov w2, #0x1 (0x52800022)
        # 0x1e984c: bl setIncludeAllNetworks: (0x940d5bf5)
        # We NOP both instructions (0xd503201f 0xd503201f -> 1f2003d5 1f2003d5 in little-endian)
        # so that handleNetworkEvent never mutates includeAllNetworks on network events.
        # The configuration set by NETunnelProviderManager (QuantumultXAPNsManager)
        # remains permanently active and clean, matching Stash's native architecture.
        offset = 0x1e9848
        f.seek(offset)
        curr_8 = f.read(8)
        nop_8 = bytes.fromhex("1f2003d51f2003d5")

        if curr_8 in [bytes.fromhex("02008052f55b0d94"), bytes.fromhex("22008052f55b0d94")]:
            f.seek(offset)
            f.write(nop_8)
            print(f"[patch_tunnel] Successfully NOPed out setIncludeAllNetworks: at {hex(offset)} (preserves protocolConfiguration).")
        elif curr_8 == nop_8:
            print(f"[patch_tunnel] Offset {hex(offset)} already NOPed.")
        else:
            print(f"[patch_tunnel] Notice: Instructions at {hex(offset)}: {curr_8.hex()}. Writing NOPs.")
            f.seek(offset)
            f.write(nop_8)

        # Patch 2: Disable sleepWithCompletionHandler: so iOS never suspends the tunnel on lock screen
        # In Stash iOS, sleepWithCompletionHandler: is NOT implemented, so the tunnel runs 24/7.
        # In Quantumult X, sleepWithCompletionHandler: pauses internal engines and calls completionHandler(),
        # which lets iOS put the tunnel to sleep during long lock screen periods.
        # Renaming this selector to _leepWithCompletionHandler: ensures iOS never invokes sleep
        # on QTXPacketTunnelProvider, keeping APNs packet processing running continuously 24/7!
        str_offset = 0x57afab
        f.seek(str_offset)
        curr_str = f.read(28)
        if curr_str == b"sleepWithCompletionHandler:\x00":
            f.seek(str_offset)
            f.write(b"_leepWithCompletionHandler:\x00")
            print(f"[patch_tunnel] Successfully disabled sleepWithCompletionHandler: (runs continuously 24/7 like Stash).")
        elif curr_str == b"_leepWithCompletionHandler:\x00":
            print(f"[patch_tunnel] sleepWithCompletionHandler: already disabled.")
        else:
            print(f"[patch_tunnel] Notice: Selector string at {hex(str_offset)}: {curr_str}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 patch_tunnel.py <path_to_Quantumult_X_Tunnel>")
        sys.exit(1)
    patch_tunnel_binary(sys.argv[1])
