import os
import time
import logging
from threading import Thread
from wave_array.client.uart_protocol import UartProtocol

import numpy as np

class WaveArray:

    # Register address map.
    REG_RESET                   = 0x00000000
    REG_FAULT                   = 0x00000001
    REG_LED                     = 0x00000002
    REG_VOICES                  = 0x00000003
    REG_POTENTIOMETER           = 0x00000004

    REG_DBG_WAVE_STATE_OFFLOAD  = 0x00000100
    REG_DBG_WAVE_STATE_SAMPLE   = 0x00000101
    REG_DBG_WAVE_FIFO           = 0x00000102
    REG_DBG_WAVE_TIMER          = 0x00000103
    REG_DBG_WAVE_FLAGS          = 0x00000104
    REG_DBG_UART_FLAGS          = 0x00000110

    REG_BINAURAL                = 0x00000200
    REG_UNISON_N                = 0x00000201
    REG_UNISON_SPREAD           = 0x00000202

    REG_FRAME_CTRL              = 0x00000300   

    REG_LFO_VELOCITY            = 0x00000500
    REG_LFO_WAVE                = 0x00000501
    REG_LFO_TRIGGER             = 0x00000502

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
    REG_FRAME_CTRL_BASE         = 0x00004000
    REG_MIX_CTRL_BASE           = 0x00005000
    REG_FREQ_CTRL_BASE          = 0x00006000 

    def __init__(self, hk_signal, wave_signal, port='COM4'):
        self.protocol = UartProtocol(port, 1000_000, hk_signal, wave_signal)

        # Stop HK to clear the input buffer.
        hk_enable = self.protocol.read(self.REG_HK_ENABLE)
        self.protocol.write(self.REG_HK_ENABLE, 0)
        self.protocol.uart.uart.reset_input_buffer()
        self.protocol.write(self.REG_HK_ENABLE, hk_enable)

        self.n_voices = self.protocol.read(self.REG_VOICES)
        self.n_voices_log2 = int(np.ceil(np.log2(self.n_voices)))

    def stop(self):
        self.protocol.stop()

    def reset(self):
        self.protocol.write(self.REG_RESET, 0x01)

    def set_led(self, enable):
        self.protocol.write(self.REG_LED, int(enable))

    def get_led(self):
        return bool(self.protocol.read(self.REG_LED))

    def read_faults(self):
        return self.protocol.read(self.REG_FAULT)

    def write(self, address, value):
        # print(f'[{address:08X}] <= {value:04X}')
        self.protocol.write(address, value) 

    def read(self, address, log=True):
        value = np.uint16(self.protocol.read(address))
        # if log: 
        #     print(f'read [{address:08X}] = {value:04X}')
        return value

    def read_mod_source(self, destination, index):
        address = self.REG_MOD_MAP_BASE + destination * 8 + index * 2
        return self.read(address)

    def write_mod_source(self, destination, index, source):
        address = self.REG_MOD_MAP_BASE + destination * 8 + index * 2
        # print(f'mod enable {destination} {index} {source} {address:08X}')
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
        # Stop HK during write.
        hk_enable = self.protocol.read(self.REG_HK_ENABLE)
        self.protocol.write(self.REG_HK_ENABLE, 0)
        self.protocol.write_block(address, data)
        self.protocol.write(self.REG_HK_ENABLE, hk_enable)


    def read_sdram(self, address, length):
        data = np.zeros(length).astype('int16')
        burst_address = address

        for i in range(len(data) // 128):
            data[i * 128:(i + 1) * 128] = self.protocol.read_block(burst_address, 128)
            burst_address += 128

        return data
    

def main():

    logging.basicConfig(level=logging.DEBUG)
    log = logging.getLogger(__name__)

    wave_array = WaveArray()

    # wave_array.set_led(True)
    # wave_array.get_led()

    wave_array.read(WaveArray.REG_HK_ENABLE)

    module_path = os.path.dirname(os.path.abspath(__file__))
    table_path = os.path.join(module_path, '../../../data/wavetables/saw.table')

    with open(table_path, 'r') as f:
        raw_data = f.read().split('\n')

    raw_data = list(filter(lambda x: x != '', raw_data))
    data = np.array([int(x, 16) for x in raw_data]).astype('int16')
    log.info(f'data length = {len(data)}')
    
    print(data)

    wave_array.write_sdram(0, data)

    log.info('sdram write complete')


    # try:
    #     wave_array.read(WaveArray.REG_FAULT)
    #     # wave_array.write(WaveArray.REG_FAULT, 0)
    # except:
    #     pass 

    # wave_array.write(WaveArray.REG_LED, 0)
    # wave_array.read(WaveArray.REG_LED)
    

if __name__ == '__main__':
    main()