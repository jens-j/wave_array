import os
import logging
import struct
from time import sleep

import numpy as np

from wave_array.client.client import WaveArray


logger = logging.getLogger(__name__)


class TableDescriptor:
    """ Wavetable descriptor class. """

    def __init__(self, name, n_frames_log2, base_address):

        self.name = name
        self.n_frames_log2 = n_frames_log2
        self.base_address = base_address

    def print(self):
        print(f'[0x{self.base_address:07X}] {self.name}')


class WaveTable:
    """ Wavetable (mipmap) class. """

    def __init__(self, descriptor, data):

        self.descriptor = descriptor
        self.data = data
        self.frames = [] # List of L0 frames for client side stuff.
        
        for i in range(2**self.descriptor.n_frames_log2):
            self.frames.append(data[i * 4096:i * 4096 + 2048])


    @classmethod 
    def from_file(cls, filepath, base_address):
        """ Create object from .table (mipmap) file """

        filename = os.path.basename(filepath)

        parts = filename.split('.')

        if len(parts) > 2:
            logger.error(f'Illegal wavetable file name {filename}')
            raise ValueError

        if parts[1] != 'table':
            logger.error(f'Wavetable file name has wrong extension {filename}')
            raise ValueError
        
        try:
            with open(filepath, 'r') as f:
                raw_data = f.read().split('\n')
        except:
            logger.error(f'Cannot open {filename}')
            raise IOError

        raw_data = list(filter(lambda x: x != '', raw_data))
        data = np.array([int(x, 16) for x in raw_data]).astype('int16')

        n_frames_log2 = np.log2(len(data) / 4096)

        if not n_frames_log2.is_integer():
            logger.error(f'Wavetable length in not a power of 2 * 4096 words (1 frame) {filename}')
            raise ValueError

        # Add number of frames to table name
        name = f'{parts[0]} ({int(2**n_frames_log2)})'
        
        return WaveTable.from_data(name, base_address, data)


    @classmethod
    def from_data(cls, name, base_address, data):
        """ Create object from raw mipmap data. """

        n_frames_log2 = np.log2(len(data) / 4096)
        assert n_frames_log2.is_integer() and 0 <= n_frames_log2 <= 4, f'Invalid wavetable length {len(data)}'

        descriptor = TableDescriptor(name, int(n_frames_log2), base_address)

        return WaveTable(descriptor, data)
    

    @classmethod
    def from_sdram(cls, descriptor, client):
        """ Read a wavetable from the SDRAM based on a descriptor. """

        data = client.read_sdram(descriptor.base_address, 4096 * 2**descriptor.n_frames_log2)

        return WaveTable(descriptor, data)
    

    def write_to_flash(self, client):
        """ Write wavetable to the FLASH. """
        
        # Write to SDRAM 
        client.write_sdram(self.descriptor.base_address, 4096 * 2**self.descriptor.n_frames_log2)

        n_sectors = self.data // 2**15

        # Extend table to sector size if smaller than 1 sector (8 frames).
        if self.descriptor.n_frames_log2 < 3:
            data = np.concatenate(data, np.zeros(4096 * (8 - 2**self.descriptor.n_frames_log2), type=np.int16))
        
        # DMA SDRAM to FLASH
        client.write(WaveArray.REG_DMA_SECTOR_N, n_sectors)
        client.write(WaveArray.REG_DMA_FLASH_ADDR_LO, self.descriptor.base_address & 0xFFFF)
        client.write(WaveArray.REG_DMA_FLASH_ADDR_HI, (self.descriptor.base_address >> 16) & 0xFFFF)
        client.write(WaveArray.REG_DMA_SDRAM_ADDR_LO, (self.descriptor.base_address >> 1) & 0xFFFF) # Convert to word address
        client.write(WaveArray.REG_DMA_SDRAM_ADDR_HI, (self.descriptor.base_address >> 17) & 0xFFFF) # Convert to word address
        client.write(WaveArray.REG_DMA_START_S2F, 1)

        # Wait for DMA transfer to complete.
        while client.read(WaveArray.REG_DMA_BUSY) != 0:
            logger.debug('DMA F->S busy...')
            sleep(0.01)


class TableManager:
    """ Wavetable (mipmap) manager class. """

    # SDRAM addresses
    FLASH_DESCRIPTOR_START = 0x0
    FLASH_DESCRIPTOR_END = 0x8_000
    FLASH_TABLE_START = 0x8_000
    FLASH_TABLE_END = 0xC_000_000


    def __init__(self, client):

        self.client = client
        self.descriptors = []
        self.tables = []
        self.base_address = self.FLASH_TABLE_START


    def add_table(self, table):
        """ Add a single WaveTable object to the manager. """

        self.tables.append(table)
        self.descriptors.append(table.descriptor)

    
    def read_directory(self, directory_path):
        """ Load all wavetables (mipmap) from a directory. """

        dirname = os.path.dirname(directory_path)

        for filename in os.listdir(directory_path):

            name, extension = filename.split('.')

            if extension != 'table':
                continue

            wavetable = WaveTable.from_file(os.path.join(dirname, filename), self.base_address)

            if wavetable.descriptor.n_frames_log2 <= 3:
                self.base_address += 0x8000 # 1 sector
            else:
                self.base_address += 0x10000 # 2 sectors

            logger.info(f'Read table {name}')
            self.add_table(wavetable)

    
    def read_table_descriptors(self):
        """ Read all valid table descriptors from the FLASH. """

        data = b''

        # Read table descriptors from SDRAM 
        data = self.client.read_sdram_bytes(
            self.FLASH_DESCRIPTOR_START, self.FLASH_DESCRIPTOR_END - self.FLASH_DESCRIPTOR_START)

        while len(data) >= 106:
            valid, frames_log2, base_address, raw_name = struct.unpack('>BBI100s', data[:106])
            name = raw_name.decode('ascii')
            if valid:
                self.descriptors.append(TableDescriptor(name, frames_log2, base_address))
                self.descriptors[-1].print()
            data = data[106:] 

        
    def write_table_descriptors(self):
        """ Write all loaded table descriptors to the FLASH. """

        data = b''
        address = 0

        for d in self.descriptors:
            d.print()
  
        for desc in self.descriptors:
            data += struct.pack('>BBI100s', 0x01, desc.n_frames_log2, desc.base_address, bytes(desc.name, 'ascii'))

        # Fill rest of descriptor section with zero's.
        data += b'\x00' * (2 * (self.FLASH_DESCRIPTOR_END - self.FLASH_DESCRIPTOR_START) - len(data))

        self.client.write_sdram_bytes(0, data)


def main():

    logging.basicConfig(level=logging.INFO)

    client = WaveArray()
    tm = TableManager(client)

    module_path = os.path.dirname(os.path.abspath(__file__))
    table_path = os.path.join(module_path, '../../../data/wavetables/')
    tm.read_directory(table_path)
    tm.write_table_descriptors()
    tm.read_table_descriptors()
    

if __name__ == '__main__':
    main()