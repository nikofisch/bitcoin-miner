# imports
import argparse, hashlib, time
import serial


# genesis block + tail
HEADER_NO_NONCE = bytes.fromhex(
    "0100000000000000000000000000000000000000000000000000000000000000000000003ba3edfd7a7b12b27ac72c3e67768f617fc81bc3888a51323a9fb8aa4b1e5e4a29ab5f49ffff001d")




# reads bytes from the fpga port until you have n bytes exactly
def read_exact(ser, n):
    buf = b""
    while len(buf) < n:
        chunk = ser.read(n - len(buf))
        if chunk:
            buf += chunk
    return buf



# counts how many leading bit
def leading_zero_bits(hash_bytes):

    # total number of bits
    total_bits = len(hash_bytes) * 8


    # number of bytes without the 0
    hash_number = int.from_bytes(hash_bytes, "big")
    bits_without_leading_zeros = hash_number.bit_length()



    # check difference
    return total_bits - bits_without_leading_zeros



# check fpga function
# report sohuld be 36 bytes 4 from nonce + 32 from 
def check(report):

    # nonce from the fpga
    nonce = int.from_bytes(report[:4], "big")

    # board hash
    board_hash = report[4:]

    # makes the offical header with genenisis block and tail
    header = HEADER_NO_NONCE + nonce.to_bytes(4, "little")    

    # double sha256 algo using library
    pc_hash = hashlib.sha256(hashlib.sha256(header).digest()).digest()[::-1]
    return nonce, board_hash, pc_hash


def main():


    # arugment parser
    ap = argparse.ArgumentParser()
    ap.add_argument("port")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--again", type=int, default=0, help="restart the board this many extra times")
    a = ap.parse_args()


    # open serial port
    with serial.Serial(a.port, a.baud, timeout=1) as ser:


        for run in range(a.again + 1):
            if run > 0:
                ser.write(b"r")



            print(f"[run {run + 1}] waiting for the board to find a nonce...")


            # start time
            t0 = time.time()



            report = read_exact(ser, 36)

            result = check(report)
            nonce, board_hash, pc_hash = result


            if (board_hash == pc_hash):
                ok = True
            
            else:
                ok = False
            
            print(f"  nonce     : {nonce} (0x{nonce:08x})   after {time.time() - t0:.1f}s")
            print(f"  board hash: {board_hash.hex()}")
            print(f"  pc hash   : {pc_hash.hex()}")
            print(f"  zero bits : {leading_zero_bits(pc_hash)}")
            print("  RESULT    :", "MATCH" if ok else "MISMATCH")


if __name__ == "__main__":
    main()