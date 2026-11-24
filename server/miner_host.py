#!/usr/bin/env python3
"""Host side of the FPGA miner.

The board mines on its own and shows the nonce on HEX. When it finds one it sends
36 bytes over UART: 4-byte nonce (big-endian) + 32-byte hash (Bitcoin display order).
This script reads them and re-checks the hash with hashlib.

  pip install pyserial
  python miner_host.py COM5            # wait for one result
  python miner_host.py COM5 --again 3  # then send a byte to make the board search again, 3 more times
"""
import argparse, hashlib, time
import serial

# Must match the header hardcoded in top_miner.v (Bitcoin genesis block, nonce field zeroed)
HEADER_NO_NONCE = bytes.fromhex(
    "0100000000000000000000000000000000000000000000000000000000000000000000003ba3edfd7a7b12b27ac72c3e67768f617fc81bc3888a51323a9fb8aa4b1e5e4a29ab5f49ffff001d")


def read_exact(ser, n):
    buf = b""
    while len(buf) < n:
        chunk = ser.read(n - len(buf))
        if chunk:
            buf += chunk
    return buf


def leading_zero_bits(h):
    return 256 - int.from_bytes(h, "big").bit_length()


def check(report):
    nonce = int.from_bytes(report[:4], "big")
    board_hash = report[4:]
    header = HEADER_NO_NONCE + nonce.to_bytes(4, "little")      # header stores nonce little-endian
    pc_hash = hashlib.sha256(hashlib.sha256(header).digest()).digest()[::-1]
    return nonce, board_hash, pc_hash


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("port")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--again", type=int, default=0, help="restart the board this many extra times")
    a = ap.parse_args()

    with serial.Serial(a.port, a.baud, timeout=1) as ser:
        for run in range(a.again + 1):
            if run:
                ser.write(b"r")                                 # any byte restarts the search
            print(f"[run {run + 1}] waiting for the board to find a nonce...")
            t0 = time.time()
            nonce, board_hash, pc_hash = check(read_exact(ser, 36))
            ok = board_hash == pc_hash
            print(f"  nonce     : {nonce} (0x{nonce:08x})   after {time.time() - t0:.1f}s")
            print(f"  board hash: {board_hash.hex()}")
            print(f"  pc hash   : {pc_hash.hex()}")
            print(f"  zero bits : {leading_zero_bits(pc_hash)}")
            print("  RESULT    :", "MATCH" if ok else "MISMATCH")


if __name__ == "__main__":
    main()