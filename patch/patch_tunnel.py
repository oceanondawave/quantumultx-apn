#!/usr/bin/env python3
import sys
import os

def patch_tunnel_binary(tunnel_path):
    if not os.path.isfile(tunnel_path):
        print(f"Error: Tunnel binary not found at {tunnel_path}")
        sys.exit(1)

    with open(tunnel_path, "r+b") as f:
        nop = bytes.fromhex("1f2003d5")

        # -------------------------------------------------------------------------
        # Patch 1: NOP out [protocolConfiguration setIncludeAllNetworks:] in handleNetworkEvent
        # -------------------------------------------------------------------------
        offset = 0x1e9848
        f.seek(offset)
        curr_8 = f.read(8)
        nop_8 = bytes.fromhex("1f2003d51f2003d5")

        if curr_8 in [bytes.fromhex("02008052f55b0d94"), bytes.fromhex("22008052f55b0d94")]:
            f.seek(offset)
            f.write(nop_8)
            print(f"[patch_tunnel] Successfully NOPed out setIncludeAllNetworks: at {hex(offset)}.")
        elif curr_8 == nop_8:
            print(f"[patch_tunnel] Offset {hex(offset)} already NOPed.")
        else:
            print(f"[patch_tunnel] Notice: Instructions at {hex(offset)}: {curr_8.hex()}. Writing NOPs.")
            f.seek(offset)
            f.write(nop_8)

        # -------------------------------------------------------------------------
        # Patch 2: SOCKS5 Proxy Server (Port 9988) - Guaranteed 24/7 Always-On
        # -------------------------------------------------------------------------
        # 2a. startTunnelWithOptions (0x1dfb30): NOP out tbnz w24, #0, 0x1001e11dc (stop branch)
        f.seek(0x1dfb30)
        curr = f.read(4)
        if curr == bytes.fromhex("78b50037"):
            f.seek(0x1dfb30)
            f.write(nop)
            print("[patch_tunnel] Patched 0x1dfb30: SOCKS5 proxy always starts on tunnel launch.")
        elif curr == nop:
            print("[patch_tunnel] 0x1dfb30 already NOPed.")

        # 2b. handleNetworkEvent_block_invoke_5 (0x1e98f0): NOP out cbz w23, 0x1001e9914 (skip branch)
        f.seek(0x1e98f0)
        curr = f.read(4)
        if curr == bytes.fromhex("37010034"):
            f.seek(0x1e98f0)
            f.write(nop)
            print("[patch_tunnel] Patched 0x1e98f0: SOCKS5 proxy always starts on network event.")
        elif curr == nop:
            print("[patch_tunnel] 0x1e98f0 already NOPed.")

        # 2c. nw_path_monitor update handler (0x1e5c1c): NOP out cbz w21, 0x1001e5c40 (skip branch)
        f.seek(0x1e5c1c)
        curr = f.read(4)
        if curr == bytes.fromhex("35010034"):
            f.seek(0x1e5c1c)
            f.write(nop)
            print("[patch_tunnel] Patched 0x1e5c1c: SOCKS5 proxy always starts on path change.")
        elif curr == nop:
            print("[patch_tunnel] 0x1e5c1c already NOPed.")

        # 2d. Hardcode SOCKS5 port to 9988 (0x2704 -> mov w3, #9988) at 0xc14e4
        f.seek(0xc14e4)
        curr = f.read(4)
        if curr == bytes.fromhex("833e0012"):
            f.seek(0xc14e4)
            f.write(bytes.fromhex("83e08452"))
            print("[patch_tunnel] Patched 0xc14e4: SOCKS5 port fixed to 9988 (acceptOnInterface:nil port:9988).")
        elif curr == bytes.fromhex("83e08452"):
            print("[patch_tunnel] 0xc14e4 already set to port 9988.")

        # -------------------------------------------------------------------------
        # Patch 3: HTTP Proxy Server (Port 8899) - Guaranteed 24/7 Always-On
        # -------------------------------------------------------------------------
        # 3a. startTunnelWithOptions (0x1e0d28): NOP out tbnz w24, #0, 0x1001e122c (stop branch)
        f.seek(0x1e0d28)
        curr = f.read(4)
        if curr == bytes.fromhex("38280037"):
            f.seek(0x1e0d28)
            f.write(nop)
            print("[patch_tunnel] Patched 0x1e0d28: HTTP proxy always starts on tunnel launch.")
        elif curr == nop:
            print("[patch_tunnel] 0x1e0d28 already NOPed.")

        # 3b. handleNetworkEvent_block_invoke_5 (0x1e989c): NOP out cbz w23, 0x1001e98c0 (skip branch)
        f.seek(0x1e989c)
        curr = f.read(4)
        if curr == bytes.fromhex("37010034"):
            f.seek(0x1e989c)
            f.write(nop)
            print("[patch_tunnel] Patched 0x1e989c: HTTP proxy always starts on network event.")
        elif curr == nop:
            print("[patch_tunnel] 0x1e989c already NOPed.")

        # 3c. nw_path_monitor update handler (0x1e5bc8): NOP out cbz w21, 0x1001e5bec (skip branch)
        f.seek(0x1e5bc8)
        curr = f.read(4)
        if curr == bytes.fromhex("35010034"):
            f.seek(0x1e5bc8)
            f.write(nop)
            print("[patch_tunnel] Patched 0x1e5bc8: HTTP proxy always starts on path change.")
        elif curr == nop:
            print("[patch_tunnel] 0x1e5bc8 already NOPed.")

        # 3d. Hardcode HTTP port to 8899 (0x22c3 -> mov w3, #8899) at 0x23554
        f.seek(0x23554)
        curr = f.read(4)
        if curr == bytes.fromhex("833e0012"):
            f.seek(0x23554)
            f.write(bytes.fromhex("63588452"))
            print("[patch_tunnel] Patched 0x23554: HTTP port fixed to 8899 (acceptOnInterface:nil port:8899).")
        elif curr == bytes.fromhex("63588452"):
            print("[patch_tunnel] 0x23554 already set to port 8899.")

        # -------------------------------------------------------------------------
        # Patch 4: Restore sleepWithCompletionHandler: for clean sleep/wake handling
        # -------------------------------------------------------------------------
        str_offset = 0x57afab
        f.seek(str_offset)
        curr_str = f.read(28)
        if curr_str == b"_leepWithCompletionHandler:\x00":
            f.seek(str_offset)
            f.write(b"sleepWithCompletionHandler:\x00")
            print(f"[patch_tunnel] Restored sleepWithCompletionHandler: for clean sleep/wake handling.")
        elif curr_str == b"sleepWithCompletionHandler:\x00":
            print(f"[patch_tunnel] sleepWithCompletionHandler: intact.")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 patch_tunnel.py <path_to_Quantumult_X_Tunnel>")
        sys.exit(1)
    patch_tunnel_binary(sys.argv[1])
