import os
import time
import logging
import serial
import struct
from threading import Thread
from queue import Queue, Empty


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
    AUTO_OFFLOAD    = 9

class Uart:

    logger = logging.getLogger('Uart')

    T_SLEEP = 0.001 # s

    def __init__(self, port, baudrate, ao_callback):

        self.ao_callback = ao_callback
        self.uart = serial.Serial(port, baudrate=baudrate, timeout=self.T_SLEEP)
        self.rep_queue = Queue()
        self.ao_queue = Queue()
        self.stop_thread = False

        self.uart.reset_input_buffer()
        self.uart.reset_output_buffer()
        
        self.thread = Thread(target=self._run)
        self.thread.start()

    
    def stop(self):
        self.stop_thread = True


    def write_req(self, packet):

        # self.logger.info(f'send: {packet}')
        self.uart.write(packet)


    def read_rep(self):

        packet = self.rep_queue.get()
        # self.logger.info(f'recv: {packet}')

        return packet

    
    def _read_bytes(self, amount):

        # self.logger.info(f'_read_bytes({amount})')

        b = b''

        while True:
            b += self.uart.read(size=(amount - len(b)))
            if len(b) >= amount:
                return b
            time.sleep(0.001)


    def _run(self):
            
        while not self.stop_thread:
            try: 
                header = self._read_bytes(1) 

                if len(header) == 0:
                    continue

                # self.logger.info(f'opcode = {header}')

                opcode = int.from_bytes(header, 'big')

                if opcode == UartType.READ_REP:
                    data = self._read_bytes(2)
                    self.rep_queue.put(header + data)
                
                elif opcode == UartType.WRITE_REP:
                    self.rep_queue.put(header)

                elif opcode == UartType.READ_BLOCK_REP:
                    length = self._read_bytes(4)
                    data = self._read_bytes(int.from_bytes(length, 'big') * 2)
                    self.rep_queue.put(header + length + data)

                elif opcode == UartType.WRITE_BLOCK_REP:
                    self.rep_queue.put(header)

                elif opcode == UartType.ERROR_REP:
                    code = self._read_bytes(1)
                    self.rep_queue.put(header + code)

                elif opcode == UartType.AUTO_OFFLOAD:
                    channel = self._read_bytes(1)
                    length = self._read_bytes(2)

                    # l = struct.unpack('I', length)

                    # self.logger.info(f'channel= {int.from_bytes(channel, "big")}')
                    # self.logger.info(f'length = {int.from_bytes(length, "big")} ({length})')

                    data = self._read_bytes(int.from_bytes(length, 'big') * 2)

                    packet = header + channel + length + data

                    # print(len(packet))
                    # print(packet)

                    self.ao_callback(packet)
                    # self.ao_queue.put(packet)
                else:
                    self.logger.warning(f'unknown opcode received from device: {header}')

            except serial.SerialTimeoutException:
                pass 
            except TypeError:
                os._exit(1)

                

                