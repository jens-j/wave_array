import time
import logging
from wave_array.client.uart_protocol import UartProtocol

import numpy as np

class WaveArray:

    # Modulation source and destination indices.
    MODD_CUTOFF                 = 0 
    MODD_RESONANCE              = 1 
    MODD_FRAME                  = 2
    MODD_MIXER                  = 3

    MODS_NONE                   = 0
    MODS_POT                    = 1
    MODS_ENVELOPE               = 2
    MODS_LFO                    = 3

    MODS_LEN                    = 4
    MODD_LEN                    = 4
    MODS_LEN_log2               = int(np.ceil(np.log2(MODS_LEN)))
    MODD_LEN_log2               = int(np.ceil(np.log2(MODD_LEN)))

    # Register address map.
    REG_RESET                   = 0x00000000
    REG_FAULT                   = 0x00000001
    REG_LED                     = 0x00000002
    REG_VOICES                  = 0x00000003

    REG_DBG_WAVE_STATE_OFFLOAD  = 0x00000100
    REG_DBG_WAVE_STATE_SAMPLE   = 0x00000101
    REG_DBG_WAVE_FIFO           = 0x00000102
    REG_DBG_WAVE_TIMER          = 0x00000103
    REG_DBG_WAVE_FLAGS          = 0x00000104
    REG_DBG_UART_FLAGS          = 0x00000110

    REG_FRAME_CTRL              = 0x00000300

    REG_POTENTIOMETER           = 0x00000400

    REG_LFO_VELOCITY            = 0x00000500
    REG_LFO_WAVE                = 0x00000501

    REG_FILTER_CUTOFF           = 0x00000600
    REG_FILTER_RESONANCE        = 0x00000601
    REG_FILTER_SELECT           = 0x00000602 # Filter output select. 0 = LP, 1 = HP, 2 = BP, 3 = BS, 4 = bypass.

    REG_ENVELOPE_ATTACK         = 0x00000700
    REG_ENVELOPE_DECAY          = 0x00000701
    REG_ENVELOPE_SUSTAIN        = 0x00000702
    REG_ENVELOPE_RELEASE        = 0x00000703
    
    REG_MIXER_CTRL              = 0x00000800

    REG_HK_ENABLE               = 0x00000900
    REG_HK_PERIOD               = 0x00000901
    REG_WAVE_ENABLE             = 0x00000902
    REG_WAVE_PERIOD             = 0x00000903

    REG_MOD_MAP_BASE            = 0x00001000
    REG_MOD_DEST_BASE           = 0x00002000
    REG_TABLE_BASE              = 0x00003000

    def __init__(self, ao_callback, wave_callback, port='COM4'):
        self.dev = UartProtocol(port, 1000_000, ao_callback, wave_callback)

        self.n_voices = self.dev.read(self.REG_VOICES)
        self.n_voices_log2 = int(np.ceil(np.log2(self.n_voices)))

    def stop(self):
        self.dev.stop()

    def reset(self):
        self.dev.write(self.REG_ADDR_RESET, 0x01)

    def set_led(self, enable):
        self.dev.write(self.REG_ADDR_LED, int(enable))

    def get_led(self):
        return bool(self.dev.read(self.REG_ADDR_LED))

    def read_faults(self):
        return self.dev.read(self.REG_ADDR_FAULT)

    def write(self, address, value):
        print(f'[{address:08X}] <= {value:04X}')
        self.dev.write(address, value) 

    def read(self, address, log=True):
        value = np.uint16(self.dev.read(address))
        if log: 
            print(f'read [{address:08X}] = {value:04X}')
        return value

    def read_mod_source(self, destination, index):
        address = self.REG_MOD_MAP_BASE + destination * 8 + index * 2
        return self.read(address)

    def write_mod_source(self, destination, index, source):
        
        address = self.REG_MOD_MAP_BASE + destination * 8 + index * 2
        print(f'mod enable {destination} {index} {source} {address:08X}')
        self.write(address, source)

    def read_mod_amount(self, destination, index):
        address = self.REG_MOD_MAP_BASE + destination * 8 + index * 2 + 1
        return self.read(address)
    
    def write_mod_amount(self, destination, index, amount):
        address = self.REG_MOD_MAP_BASE + destination * 8 + index * 2 + 1
        self.write(address, amount)

    def read_mod_dest(self, destination, voice):
        address = self.REG_MOD_DEST_BASE + destination * 2**self.n_voices_log2 + voice
        return self.read(address)

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