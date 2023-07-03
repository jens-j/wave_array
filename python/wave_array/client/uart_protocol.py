import logging
import struct

import numpy as np

from wave_array.client.uart import Uart, UartType


class UartProtocol:

    logger = logging.getLogger('UartProtocol')

    def __init__(self, port, baudrate, ao_callback, wave_callback):
        self.uart = Uart(port, baudrate, ao_callback, wave_callback)

    
    def stop(self):
        self.uart.stop()


    def read(self, address):
        self.logger.info(f'read [{address:04X}]')
        request = struct.pack('>BI', UartType.READ_REQ, address)
        reply = self.command(request)
        print(reply)
        opcode, data = struct.unpack('>Bh', reply)
        if opcode != UartType.READ_REP:
            raise Uart.UartException(f'received {opcode} instead of {UartType.READ_REP}')

        return np.uint16(data)


    def write(self, address, data):
        self.logger.info(f'write [{address:04X}] <= {data:04X}')
        request = struct.pack('>BIh', UartType.WRITE_REQ, address, np.int16(data))
        reply = self.command(request)
        opcode, = struct.unpack('>B', reply)
        if opcode != UartType.WRITE_REP:
            raise Uart.UartException(f'received {opcode} instead of {UartType.WRITE_REP}')


    def read_block(self, address, length):
        request = struct.pack('>BII', UartType.READ_BLOCK_REQ, address, length)
        reply = self.command(request)
        reply = list(struct.unpack(f'>B{length}h', reply))
        if reply[0] != UartType.READ_BLOCK_REP:
            raise Uart.UartException(f'received {reply[0]} instead of {UartType.READ_BLOCK_REP}')

        return list(reply)[1:]


    # Write a list of data to the SDRAM. Max length is 128 and addresses must be aligned to 128
    # word boundaries.
    def write_block(self, address, data):
        request = struct.pack(f'>BII{len(data)}h', UartType.WRITE_BLOCK_REQ, address, len(data), *data)
        reply = self.command(request)
        opcode, = struct.unpack('>B', reply)
        if opcode != UartType.WRITE_BLOCK_REP:
            raise Uart.UartException(f'received {opcode} instead of {UartType.WRITE_BLOCK_REP}')


    # Write request and read response.
    def command(self, request):

        self.logger.debug(f'send: {request.hex()}')
        self.uart.write_req(request)        
        response = self.uart.read_rep()
        self.logger.debug(f'recv ({len(response)}): {response.hex()}')
        return response
