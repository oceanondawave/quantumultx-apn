import struct, sys

def insert_load_dylib(macho_path, dylib_path, out_path):
    with open(macho_path, "rb") as f:
        data = bytearray(f.read())
    
    magic, cputype, cpusubtype, filetype, ncmds, sizeofcmds, flags, reserved = struct.unpack("<IIIIIIII", data[:32])
    assert magic == 0xfeedfacf, "Not 64-bit Mach-O"
    
    dylib_bytes = dylib_path.encode("utf-8") + b"\x00"
    # Command layout:
    # uint32 cmd (0xc)
    # uint32 cmdsize
    # uint32 stroff (24)
    # uint32 timestamp (2)
    # uint32 current_version (0)
    # uint32 compat_version (0)
    # string bytes...
    stroff = 24
    cmdsize = 24 + len(dylib_bytes)
    rem = cmdsize % 8
    if rem != 0:
        cmdsize += (8 - rem)
        dylib_bytes += b"\x00" * (8 - rem)
    
    cmd_bytes = struct.pack("<IIIIII", 0x0c, cmdsize, stroff, 2, 0x10000, 0x10000) + dylib_bytes
    
    offset_to_insert = 32 + sizeofcmds
    print(f"Original ncmds: {ncmds}, sizeofcmds: {sizeofcmds}")
    print(f"Inserting {cmdsize} bytes at 0x{offset_to_insert:x}")
    
    # Check if there is enough space (zeros)
    padding = data[offset_to_insert:offset_to_insert + cmdsize]
    assert all(b == 0 for b in padding), f"Not enough zero padding! Found: {padding[:20]}"
    
    # Write command into padding
    data[offset_to_insert:offset_to_insert + cmdsize] = cmd_bytes
    
    # Update header
    struct.pack_into("<II", data, 16, ncmds + 1, sizeofcmds + cmdsize)
    
    with open(out_path, "wb") as f:
        f.write(data)
    print("Success inserting load command!")

if __name__ == "__main__":
    insert_load_dylib(sys.argv[1], sys.argv[2], sys.argv[3])
