import serial
import time

message = b"matthew"

with serial.Serial("/dev/ttyUSB0", baudrate=115200, timeout=2, write_timeout=2) as fpga:

    fpga.reset_input_buffer()
    received = bytearray()

    # Send one byte, then wait for the FPGA to echo it.
    for value in message:
        fpga.write(bytes([value]))
        fpga.flush()

        reply = fpga.read(1)

        if not reply:
            raise TimeoutError("No reply from the FPGA")

        received.extend(reply)

        time.sleep(1)

print("Sent:    ", message)
print("Received:", bytes(received))
print("PASS" if bytes(received) == message else "FAIL")