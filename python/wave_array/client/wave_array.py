import time
import logging
import uart

class WaveArray:

    REG_ADDR_RESET              = 0x00000000
    REG_ADDR_FAULT              = 0x00000001
    REG_ADDR_LED                = 0x00000002
    REG_DEBUG_UART_COUNT        = 0x00000100
    REG_DEBUG_UART_FIFO_COUNT   = 0x00000101
    REG_DEBUG_UART_STATE        = 0x00000102
    REG_DEBUG_SDRAM_COUNT       = 0x00000110
    REG_DEBUG_SDRAM_STATE       = 0x00000111

    def __init__(self, port='COM4'):
        self.dev = uart.UartDevice(port, 1000000)

    def reset(self):
        self.dev.write(self.REG_ADDR_RESET, 0x01)

    def set_led(self, enable):
        self.dev.write(self.REG_ADDR_LED, int(enable))

    def get_led(self):
        return bool(self.dev.read(self.REG_ADDR_LED))

    def read_faults(self):
        return self.dev.read(self.REG_ADDR_FAULT)

    def get_uart_count(self):
        return self.dev.read(self.REG_DEBUG_UART_FIFO)

    def get_uart_fifo_count(self):
        return self.dev.read(self.REG_DEBUG_UART_COUNT)

    def write_sdram(self, address, data):
        self.dev.write_block(address, data)

    def read_sdram(self, address, length):
        return self.dev.read_block(address, length)



if __name__ == '__main__':

    logging.basicConfig(level=logging.DEBUG)
    log = logging.getLogger(__name__)

    wave_array = WaveArray()

    # wave_array.set_led(True)
    # wave_array.get_led()

    wave_array.write_sdram(0, list(range(16)))

    try:
        read_data = wave_array.read_sdram(0, 16)
    except Exception as e:
        log.error(f'read_error: {e}')

    print(wave_array.dev.read(WaveArray.REG_DEBUG_UART_STATE))
    print(wave_array.dev.read(WaveArray.REG_DEBUG_UART_COUNT))
    print(wave_array.dev.read(WaveArray.REG_DEBUG_UART_FIFO_COUNT))
    print(wave_array.dev.read(WaveArray.REG_DEBUG_SDRAM_COUNT))
    print(wave_array.dev.read(WaveArray.REG_DEBUG_SDRAM_STATE))


    try:
        read_data = wave_array.read_sdram(1, 16)
    except Exception as e:
        log.error(f'read_error: {e}')

    try:
        read_data = wave_array.read_sdram(12, 4)
    except Exception as e:
        log.error(f'read_error: {e}')


    # led_state = True
    # while True:
    #     wave_array.set_led(led_state)
    #     led_state = not led_state
    #     time.sleep(0.5)
