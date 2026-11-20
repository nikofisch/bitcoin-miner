import argparse
import hashlib
import sys
import time


def pad_message(message):


    message_bytes = len(message)


    # 55 bytes because you have 9 bytes that include message length in 8 bytes and 1 byte for when the padidng starts
    if message_bytes > 55:
        raise ValueError("Message must be at most 55 bytes")

    padded = message

    # add one byte for when the padding starts 
    padded = padded + b"\x80"

    # final bytes are used for the length
    zero_count = 64 - message_bytes - 1 - 8
    zero_bytes = b"\x00" * zero_count
    padded = padded + zero_bytes

    # message length in bits
    message_bits = message_bytes * 8

    # store that number using exactly 8 bytes.
    length_field = message_bits.to_bytes(8, "big")

    # add everything together
    return padded + length_field


# returns expected hash
def expected_hash(message):

    first_hash = hashlib.sha256(message).digest()

    second_hash = hashlib.sha256(first_hash).digest()


    return second_hash


def read_exact(port,size,timeout=5):
    received=bytearray()
    deadline=time.monotonic()+timeout

    while len(received)<size:
        
        if time.monotonic()>=deadline:
            raise TimeoutError(f'Expected {size} digest bytes, received {len(received)}. '
                               'Check the loaded design, wiring, clock, reset and baud rate.')
        
        chunk=port.read(size-len(received))
        received.extend(chunk)
    return bytes(received)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port',default='/dev/ttyUSB0',help='e.g. /dev/ttyUSB0 or COM5')
    parser.add_argument('--baud',type=int,default=115200)
    parser.add_argument('--message',help='UTF-8 message, max 55 BYTES; omit for five test cases')
    args=parser.parse_args()
    messages=([args.message.encode('utf-8')] if args.message is not None else
              [b'abc',b'hello FPGA',b'',b'A'*55,bytes(range(55))])
    # Reject an oversized message before writing anything to the FPGA.
    blocks=[pad_message(m) for m in messages]
    import serial
    passed=True
    try:
        with serial.Serial(args.port,args.baud,timeout=0.1,write_timeout=2) as fpga:
            fpga.reset_input_buffer()
            print('Connected. FPGA must be programmed with sha256_uart_top and reset with KEY0.')
            for index,(message,block) in enumerate(zip(messages,blocks),start=1):
                print(f'\nTest {index}: {message!r} ({len(message)} bytes)')
                written=fpga.write(block)
                if written!=64:
                    raise IOError(f'Only wrote {written}/64 bytes')
                fpga.flush()
                actual=read_exact(fpga,32)
                expected=expected_hash(message)
                match=actual==expected
                print('FPGA:  ',actual.hex())
                print('Python:',expected.hex())
                print('PASS' if match else 'FAIL')
                passed=passed and match
            print(f'\n{"ALL TESTS PASSED" if passed else "ONE OR MORE TESTS FAILED"}')
    except (serial.SerialException,TimeoutError,OSError) as error:
        print(f'ERROR: {error}',file=sys.stderr)
        print('After an interrupted request, press KEY0 before retrying.',file=sys.stderr)
        return 1
    return 0 if passed else 1


if __name__=='__main__':
    raise SystemExit(main())
