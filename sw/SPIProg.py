import argparse
import serial
import time

class SPIProg:
    def __init__(self, port, baud=115200, timeout=2.0):
        self.ser = serial.Serial(
            port=port,
            baudrate=baud,
            timeout=timeout,
            write_timeout=timeout,
        )

        time.sleep(0.1)
        self.ser.reset_input_buffer()
        self.ser.reset_output_buffer()

    def close(self):
        self.ser.close()

    def read_exactly(self, count):
        data = bytearray()

        while len(data) < count:
            chunk = self.ser.read(count - len(data))
            if not chunk:
                raise TimeoutError(
                    f"Expected {count} response bytes, "
                    f"received {len(data)}"
                )
            data.extend(chunk)

        return bytes(data)

    def transfer(self, tx_data):
        tx_data = bytes(tx_data)
        length = len(tx_data)

        if length == 0:
            return b""

        if length > 0xFFFF:
            raise ValueError("SPI transaction cannot exceed 65535 bytes")

        packet = bytes([
            (length >> 8) & 0xFF,
            length & 0xFF,
        ]) + tx_data

        # Only clear stale data before beginning a new transaction.
        self.ser.reset_input_buffer()

        self.ser.write(packet)
        self.ser.flush()

        return self.read_exactly(length)

    def write_mem(self, address, data):
        payload = bytes([
            0x02,
            (address >> 8) & 0xFF,
            address & 0xFF,
        ]) + bytes(data)

        return self.transfer(payload)

    def read_mem_byte(self, address):
        rx = self.transfer([
            0x03,
            (address >> 8) & 0xFF,
            address & 0xFF,
            0x00,
        ])

        return rx[3]

    def read_mem(self, address, length):
        result = bytearray()

        for offset in range(length):
            result.append(self.read_mem_byte(address + offset))

        return bytes(result)


def parse_hex_bytes(values):
    return bytes(int(value, 16) for value in values)


def main():
    parser = argparse.ArgumentParser(
        description="UART-controlled FPGA SPI master"
    )
    parser.add_argument("port", help="COM4 or /dev/ttyUSB0")
    parser.add_argument(
        "bytes",
        nargs="+",
        help="Bytes to transfer, for example: 03 00 10 00",
    )
    parser.add_argument("--baud", type=int, default=115200)
    args = parser.parse_args()

    tx = parse_hex_bytes(args.bytes)
    spi = SPIProg(args.port, args.baud)

    try:
        rx = spi.transfer(tx)

        print("TX:", " ".join(f"{byte:02X}" for byte in tx))
        print("RX:", " ".join(f"{byte:02X}" for byte in rx))
    finally:
        spi.close()


if __name__ == "__main__":
    main()