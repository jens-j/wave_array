import time
import logging
from wave_array.client.uart import UartDevice

import numpy as np

class WaveArray:

    REG_ADDR_RESET              = 0x00000000
    REG_ADDR_FAULT              = 0x00000001
    REG_ADDR_LED                = 0x00000002

    REG_DBG_UART_COUNT          = 0x00000100
    REG_DBG_UART_FIFO           = 0x00000101
    REG_DBG_UART_STATE          = 0x00000102

    REG_TABLE_BASE_L            = 0x00000200
    REG_TABLE_BASE_H            = 0x00000201
    REG_TABLE_FRAMES            = 0x00000202
    REG_TABLE_NEW               = 0x00000203

    REG_FRAME_INDEX             = 0x00000300
    REG_FRAME_POSITION          = 0x00000301
    REG_FRAME_BANK              = 0x00000302

    REG_POTENTIOMETER           = 0x00000400

    REG_LFO_VELOCITY            = 0x00000500

    REG_FILTER_CUTOFF           = 0x00000600
    REG_FILTER_RESONANCE        = 0x00000601
    REG_FILTER_SELECT           = 0x00000602 # Filter output select. 0 = LP, 1 = HP, 2 = BP, 3 = BS, 4 = bypass.

    REG_ENVELOPE_ATTACK         = 0x00000700
    REG_ENVELOPE_DECAY          = 0x00000701
    REG_ENVELOPE_SUSTAIN        = 0x00000702
    REG_ENVELOPE_RELEASE        = 0x00000703
    
         

    def __init__(self, port='COM4'):
        self.dev = UartDevice(port, 1000_000)

    def reset(self):
        self.dev.write(self.REG_ADDR_RESET, 0x01)

    def set_led(self, enable):
        self.dev.write(self.REG_ADDR_LED, int(enable))

    def get_led(self):
        return bool(self.dev.read(self.REG_ADDR_LED))

    def read_faults(self):
        return self.dev.read(self.REG_ADDR_FAULT)

    def write(self, address, value, convert=False):
        raw_value = np.uint16(value * 0x7FFF) if convert else value 
        print(f'[{address:08X}] <= {raw_value:04X}')
        self.dev.write(address, raw_value) 

    def read(self, address, convert=False):
        raw_value = np.uint16(self.dev.read(address))
        #print(f'read [{address:08X}] = {raw_value:04X}')
        return raw_value / 0x7FFF if convert else raw_value

    def write_sdram(self, address, data):

        burst_address = address

        for i in range(len(data) // 128):
            burst_data = data[i * 128:(i + 1) * 128]

            print(f'[{burst_address:08X}] <=',
                f'{burst_data[0] & 0xFFFF:04X}, {burst_data[1] & 0xFFFF:04X}, {burst_data[2] & 0xFFFF:04X}, ...', 
                f'{burst_data[-3] & 0xFFFF:04X}, {burst_data[-2] & 0xFFFF:04X}, {burst_data[-1] & 0xFFFF:04X}')

            self.dev.write_block(burst_address, burst_data)
            burst_address += 128

    def read_sdram(self, address, length):

        data = np.zeros(length).astype('int16')
        burst_address = address

        for i in range(len(data) // 128):
            data[i * 128:(i + 1) * 128] = self.dev.read_block(burst_address, 128)
            burst_address += 128

        return data



def main():

    logging.basicConfig(level=logging.DEBUG)
    log = logging.getLogger(__name__)

    wave_array = WaveArray()

    wave_array.set_led(True)
    wave_array.get_led()

    wave_array.write(WaveArray.REG_FILTER_CUTOFF, 0x2000)
    wave_array.write(WaveArray.REG_FILTER_RESONANCE, 0x4000)


if __name__ == '__main__':
    main()