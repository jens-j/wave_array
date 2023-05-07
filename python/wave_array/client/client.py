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

    REG_POTOENTIOMETER          = 0x00000400

    REG_LFO_VELOCITY            = 0x00000500
    
     

    def __init__(self, port='COM4'):
        self.dev = UartDevice(port, 1000000)

    def reset(self):
        self.dev.write(self.REG_ADDR_RESET, 0x01)

    def set_led(self, enable):
        self.dev.write(self.REG_ADDR_LED, int(enable))

    def get_led(self):
        return bool(self.dev.read(self.REG_ADDR_LED))

    def read_faults(self):
        return self.dev.read(self.REG_ADDR_FAULT)

    def write_sdram(self, address, data):

        burst_address = address

        for i in range(len(data) // 128):
            burst_data = data[i * 128:(i + 1) * 128]
            print(f'[{burst_address:08X}] = {burst_data}')
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

    wave_array.write_sdram(0, list(range(256)))

    try:
        read_data = wave_array.read_sdram(0, 256)
        print(read_data)
    except Exception as e:
        log.error(e)

    print(wave_array.dev.read(WaveArray.REG_FRAME_INDEX))
    print(wave_array.dev.read(WaveArray.REG_FRAME_POSITION))
    print(wave_array.dev.read(WaveArray.REG_FRAME_BANK))

    # with open('basic_table.data') as f:
    #     string_table = f.read().split('\n')
    #     string_table = list(filter(lambda x: x != '', string_table))
    #     table = np.array([int(x, 16) for x in string_table]).astype('int16')

    # print(table)

    # wave_array.write_sdram(0, table)

    # wave_array.dev.write(WaveArray.REG_TABLE_FRAMES, 4)
    # wave_array.dev.write(WaveArray.REG_TABLE_NEW, 1)

    # led_state = True
    # while True:
    #     wave_array.set_led(led_state)
    #     led_state = not led_state
    #     time.sleep(0.5)


if __name__ == '__main__':
    main()