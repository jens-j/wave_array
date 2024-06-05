import struct
import logging
from time import sleep
from threading import Thread
from wave_array.client.uart_protocol import UartProtocol

import numpy as np


# # Convert 16 bit 2s complement value to integer.
# def twoscomp16(raw):

#     if raw & 0x8000:
#         return raw - 0x10000
#     else:
#         return raw
    

logger = logging.getLogger(__name__)


class WaveArray:

    # Register address map.
    REG_RESET                   = 0x00000000
    REG_FAULT                   = 0x00000001
    REG_LED                     = 0x00000002
    REG_VOICES                  = 0x00000003
    REG_UNISON_MAX              = 0x00000004
    REG_ENVELOPE_N              = 0x00000005
    REG_LFO_N                   = 0x00000006
    REG_MIDI_CHANNEL            = 0x00000007
    
    REG_DBG_WAVE_STATE_OFFLOAD  = 0x00000100
    REG_DBG_WAVE_STATE_SAMPLE   = 0x00000101
    REG_DBG_WAVE_FIFO           = 0x00000102
    REG_DBG_WAVE_TIMER          = 0x00000103
    REG_DBG_WAVE_FLAGS          = 0x00000104
    REG_DBG_UART_FLAGS          = 0x00000110

    REG_BINAURAL                = 0x00000200
    REG_UNISON_N                = 0x00000201
    REG_UNISON_SPREAD           = 0x00000202

    REG_NOISE_SELECT            = 0x00000300
    
    REG_FILTER_CUTOFF           = 0x00000600
    REG_FILTER_RESONANCE        = 0x00000601
    REG_FILTER_SELECT           = 0x00000602 # Filter output select. 0 = LP, 1 = HP, 2 = BP, 3 = BS, 4 = bypass.

    REG_DMA_BUSY                = 0x00000700
    REG_DMA_START_S2F           = 0x00000701
    REG_DMA_START_F2S           = 0x00000702
    REG_DMA_FLASH_ADDR_LO       = 0x00000703
    REG_DMA_FLASH_ADDR_HI       = 0x00000704
    REG_DMA_SDRAM_ADDR_LO       = 0x00000705
    REG_DMA_SDRAM_ADDR_HI       = 0x00000706
    REG_DMA_SECTOR_N            = 0x00000707
    
    REG_VOLUME_CTRL             = 0x00000800

    REG_HK_ENABLE               = 0x00000900
    REG_HK_PERIOD               = 0x00000901
    REG_WAVE_ENABLE             = 0x00000902
    REG_WAVE_PERIOD             = 0x00000903

    REG_QSPI_JEDEC_VENDOR       = 0x00000A00
    REG_QSPI_JEDEC_DEVICE       = 0x00000A01
    REG_QSPI_STATUS             = 0x00000A02
    REG_QSPI_CONFIG             = 0x00000A03
    
    REG_MOD_MAP_BASE            = 0x00001000
    REG_MOD_DEST_BASE           = 0x00002000
    REG_TABLE_BASE              = 0x00003000
    REG_FRAME_CTRL_BASE         = 0x00004000
    REG_MIX_CTRL_BASE           = 0x00005000
    REG_FREQ_CTRL_BASE          = 0x00006000 
    REG_ENVELOPE_CTRL_BASE      = 0x00007000
    REG_LFO_CTRL_BASE           = 0x00008000

    def __init__(self, hk_signal=None, wave_signal=None, port='COM3'):
        self.protocol = UartProtocol(port, 2_000_000, hk_signal, wave_signal)

        # Disable HK and oscilloscope
        self.write(WaveArray.REG_HK_ENABLE, 0)
        self.write(WaveArray.REG_WAVE_ENABLE, 0)

        # Stop HK to clear the input buffer.
        # hk_enable = self.protocol.read(self.REG_HK_ENABLE)
        # self.protocol.write(self.REG_HK_ENABLE, 0)
        self.protocol.uart.uart.reset_input_buffer()
        # self.protocol.write(self.REG_HK_ENABLE, hk_enable)

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

    def read(self, address, signed=False):
        raw_value = self.protocol.read(address)
        return np.int16(raw_value) if signed else np.uint16(raw_value)

    def read_mod_source(self, destination, index):
        address = self.REG_MOD_MAP_BASE + destination * 8 + index * 2
        return self.read(address)

    def write_mod_source(self, destination, index, source):
        address = self.REG_MOD_MAP_BASE + destination * 8 + index * 2
        # print(f'mod enable {destination} {index} {source} {address:08X}')
        self.write(address, source)

    def read_mod_amount(self, destination, index):
        address = self.REG_MOD_MAP_BASE + destination * 8 + index * 2 + 1
        return self.read(address, signed=True)
        
    def write_mod_amount(self, destination, index, amount):
        address = self.REG_MOD_MAP_BASE + destination * 8 + index * 2 + 1
        self.write(address, amount)

    def read_mod_dest(self, destination, voice):
        address = self.REG_MOD_DEST_BASE + destination * 2**self.n_voices_log2 + voice
        return self.read(address)
    
    def write_sdram_bytes(self, address, data):
        n_words = len(data) // 2
        words = struct.unpack(f'>{n_words}h', data)
        self.write_sdram_words(address, words)

    def write_sdram_words(self, address, data):       
        # Stop HK during write.
        hk_enable = self.protocol.read(self.REG_HK_ENABLE)
        self.protocol.write(self.REG_HK_ENABLE, 0)
        self.protocol.write_block(address, data)
        self.protocol.write(self.REG_HK_ENABLE, hk_enable)

    def read_sdram_bytes(self, address, length):
        byteData = b''
        words = self.read_sdram_words(address, length // 2).astype(np.uint16)
        
        for w in words:
            byteData += int(w >> 8).to_bytes(1, byteorder='big') + int(w & 0xFF).to_bytes(1, byteorder='big')

        return byteData

    def read_sdram_words(self, address, length):
        # Stop HK during write.
        hk_enable = self.protocol.read(self.REG_HK_ENABLE)
        self.protocol.write(self.REG_HK_ENABLE, 0)

        # Reads must be split into 1024 word block to avoid overflowing the uart fifo.
        data = np.array([], dtype=np.int16)

        while length > 0:
            chunk = min(length, 1024)
            data = np.concatenate((data, self.protocol.read_block(address, chunk)))
            address += chunk
            length -= chunk

        self.protocol.write(self.REG_HK_ENABLE, hk_enable)
        return data
    
    def dma_flash_to_sdram(self, flash_address, sdram_address, sectors):
        """ DMA FLASH to the SDRAM. """

        logger.info(f'DMA {sectors} sectors from FLASH 0x{flash_address:08X} to SDRAM 0x{sdram_address:08x}')

        self.write(WaveArray.REG_DMA_SECTOR_N, sectors)
        self.write(WaveArray.REG_DMA_FLASH_ADDR_LO, flash_address & 0xFFFF)
        self.write(WaveArray.REG_DMA_FLASH_ADDR_HI, (flash_address >> 16) & 0xFFFF)
        self.write(WaveArray.REG_DMA_SDRAM_ADDR_LO, sdram_address & 0xFFFF)
        self.write(WaveArray.REG_DMA_SDRAM_ADDR_HI, (sdram_address >> 16) & 0xFFFF)
        self.write(WaveArray.REG_DMA_START_F2S, 1)

        # Wait for DMA transfer to complete.
        while self.read(WaveArray.REG_DMA_BUSY) != 0:
            logger.debug('DMA F->S busy...')
            sleep(0.1)

    def dma_sdram_to_flash(self, sdram_address, flash_address, sectors):
        """ DMA SDRAM to FLASH. """

        logger.info(f'DMA {sectors} sectors from SDRAM 0x{sdram_address:08X} to FLASH 0x{flash_address:08x}')

        self.write(WaveArray.REG_DMA_SECTOR_N, sectors)
        self.write(WaveArray.REG_DMA_FLASH_ADDR_LO, flash_address & 0xFFFF)
        self.write(WaveArray.REG_DMA_FLASH_ADDR_HI, (flash_address >> 16) & 0xFFFF)
        self.write(WaveArray.REG_DMA_SDRAM_ADDR_LO, sdram_address & 0xFFFF)
        self.write(WaveArray.REG_DMA_SDRAM_ADDR_HI, (sdram_address >> 16) & 0xFFFF)
        self.write(WaveArray.REG_DMA_START_S2F, 1)

        # Wait for DMA transfer to complete.
        while self.read(WaveArray.REG_DMA_BUSY) != 0:
            logger.debug('DMA S->F busy...')
            sleep(0.1)

    

def main():

    logging.basicConfig(level=logging.DEBUG)
    log = logging.getLogger(__name__)

    wave_array = WaveArray()


    write_data_words = np.int16(list(range(64)))

    log.info(f'data length = {len(write_data_words)}')
    wave_array.write_sdram_words(0, write_data_words)
    log.info('sdram write complete')

    read_data_words = wave_array.read_sdram_words(0, len(write_data_words))
    log.info('sdram read complete')

    for i, (wdata, rdata) in enumerate(zip(write_data_words, read_data_words)):
        if wdata != rdata:
            log.info(f'{i:4d} {wdata} != {rdata}') 

    write_data_bytes = bytes(list(range(16)))
    print('write_data_bytes:', write_data_bytes)
    wave_array.write_sdram_bytes(0, write_data_bytes)
    read_data_bytes = wave_array.read_sdram_bytes(0, 16)
    print('read_data_bytes:', read_data_bytes)
    

if __name__ == '__main__':
    main()