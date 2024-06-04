import logging
import struct

import numpy as np

from wave_array.client.uart import Uart, UartType, UartException


class UartProtocol:

    logger = logging.getLogger('UartProtocol')

    def __init__(self, port, baudrate, hk_signal, wave_signal):
        self.uart = Uart(port, baudrate, hk_signal, wave_signal)

    
    def stop(self):
        self.uart.stop()


    def read(self, address):
        
        request = struct.pack('>BI', UartType.READ_REQ, address)
        # self.logger.info(f'read request: {request}')
        reply = self.command(request)         
        # self.logger.info(f'read reply: {reply}')
        
        opcode, data = struct.unpack('>Bh', reply)

        if opcode != UartType.READ_REP:
            raise UartException(f'received {opcode} instead of {UartType.READ_REP}')

        self.logger.info(f'read  [{address:04X}] => {data:04X}')
        return np.uint16(data)


    def write(self, address, data):

        request = struct.pack('>BIh', UartType.WRITE_REQ, address, np.int16(data))
        # self.logger.info(f'write request: {request}')
        reply = self.command(request)
        # self.logger.info(f'write reply: {reply}')
        opcode, = struct.unpack('>B', reply)
        if opcode == UartType.ERROR_REP:
            raise UartException(f'write recieved error reply with code {opcode}')
        elif opcode != UartType.WRITE_REP:
            raise UartException(f'received {opcode} instead of {UartType.WRITE_REP}')
        
        self.logger.info(f'write [{address:04X}] <= {np.int16(data):04X}')


    def read_block(self, address, length):

        assert length % 8 == 0, 'block reads must be a multiple of 8 words'

        request = struct.pack('>BII', UartType.READ_BLOCK_REQ, address, length // 8)
        reply = self.command(request)
        fields = list(struct.unpack(f'>BI{length}h', reply))

        if fields[0] != UartType.READ_BLOCK_REP:
            raise UartException(f'received {reply[0]} instead of {UartType.READ_BLOCK_REP}')

        return np.array(fields[2:], dtype=np.int16)
    

    # Write a list of 16 bit words to the SDRAM. Max length is 128 and addresses must be aligned to 128
    # word boundaries.
    def write_block(self, address, data):
        assert len(data) % 8 == 0, 'block writes must be a multiple of 8 words'
        request = struct.pack(f'>BII{len(data)}h', UartType.WRITE_BLOCK_REQ, address, len(data) // 8, *data)
        reply = self.command(request)
        opcode, = struct.unpack('>B', reply)
        if opcode != UartType.WRITE_BLOCK_REP:
            raise UartException(f'received {opcode} instead of {UartType.WRITE_BLOCK_REP}')
        
        
    # Write request and read response.
    def command(self, request):

        self.logger.debug(f'send: {request.hex()}')
        
        self.uart.write_req(request)        
        response = self.uart.read_rep()

        self.logger.debug(f'recv ({len(response)}): {response.hex()}')

        # Check for error reply.
        if response[0] == UartType.ERROR_REP:
            # self.logger.error('error reply received')
            _, code = struct.unpack('>BB', response)
            raise UartException(f'received error response with code {code}')
        
        return response
