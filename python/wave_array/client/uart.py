import logging
import serial
import struct
from time import sleep

class UartException(Exception):
    pass

class UartType:
    READ_REQ        = 0
    READ_REP        = 1
    WRITE_REQ       = 2
    WRITE_REP       = 3
    READ_BLOCK_REQ  = 4
    READ_BLOCK_REP  = 5
    WRITE_BLOCK_REQ = 6
    WRITE_BLOCK_REP = 7
    ERROR_REP       = 8


class UartDevice:

    logger = logging.getLogger('UartDevice')

    def __init__(self, port, baudrate):
        self.uart = serial.Serial(port, baudrate=baudrate, timeout=1)


    def read(self, address):
        request = struct.pack('>BI', UartType.READ_REQ, address)
        reply = self.command(request, 3)
        opcode, data = struct.unpack('>Bh', reply)
        if opcode != UartType.READ_REP:
            raise UartException(f'received {opcode} instead of {UartType.READ_REP}')

        return data


    def write(self, address, data):
        request = struct.pack('>BIh', UartType.WRITE_REQ, address, data)
        reply = self.command(request, 1)
        opcode, = struct.unpack('>B', reply)
        if opcode != UartType.WRITE_REP:
            raise UartException(f'received {opcode} instead of {UartType.WRITE_REP}')


    def read_block(self, address, length):
        request = struct.pack('>BII', UartType.READ_BLOCK_REQ, address, length)
        reply = self.command(request, 1 + 2 * length)
        reply = list(struct.unpack(f'>B{length}h', reply))
        if reply[0] != UartType.READ_BLOCK_REP:
            raise UartException(f'received {reply[0]} instead of {UartType.READ_BLOCK_REP}')

        return list(reply)[1:]

    # Write a list of data to the SDRAM. Max length is 128 and addresses must be aligned to 128
    # word boundaries.
    def write_block(self, address, data):
        request = struct.pack(f'>BII{len(data)}h', UartType.WRITE_BLOCK_REQ, address, len(data), *data)
        reply = self.command(request, 1)
        opcode, = struct.unpack('>B', reply)
        if opcode != UartType.WRITE_BLOCK_REP:
            raise UartException(f'received {opcode} instead of {UartType.WRITE_BLOCK_REP}')


    # Write request, read reply and check for errors.
    def command(self, request, return_length):

        self.logger.debug(f'send: {request.hex()}')

        self.uart.write(request)

        try:
            reply = self.uart.read(size=return_length)
        except:
            raise UartException('reply timeout')

        self.logger.debug(f'recv ({len(reply)}): {reply.hex()}')
        return reply
