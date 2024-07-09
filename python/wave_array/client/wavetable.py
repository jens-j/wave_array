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
        self.frames = [] # List of L0 frames for client-side visualization.
        
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

        logger.info(f'Read wavetable {descriptor.name} from [0x{descriptor.base_address:08x}]')

        data = client.read_sdram_words(descriptor.base_address, 4096 * 2**descriptor.n_frames_log2)

        return WaveTable(descriptor, data)
    

    def write_to_flash(self, client):
        """ Write wavetable to the FLASH. """

        logger.info(f'Write wavetable {self.descriptor.name} to [0x{self.descriptor.base_address:08x}]')
        
        # Extend table to sector size if smaller than 1 sector (8 frames).
        if self.descriptor.n_frames_log2 < 3:
            data_extended = np.concatenate((self.data, 
                                   np.zeros(4096 * (8 - 2**self.descriptor.n_frames_log2), dtype=np.int16)))
        else:
            data_extended = self.data
            
        n_sectors = len(data_extended) // 2**15

        # Write to SDRAM 
        client.write_sdram_words(self.descriptor.base_address, data_extended)
        
        # DMA SDRAM to FLASH
        client.dma_sdram_to_flash(self.descriptor.base_address, self.descriptor.base_address << 1, n_sectors)


class TableManager:
    """ Wavetable (mipmap) manager class. """

    # SDRAM addresses
    FLASH_DESCRIPTOR_START = 0x0
    FLASH_DESCRIPTOR_END = 0x8_000
    FLASH_TABLE_START = 0x8_000
    FLASH_TABLE_END = 0xC00_000


    def __init__(self, client):

        self.client = client
        self.descriptors = {}
        self.tables = {}
        self.base_address = self.FLASH_TABLE_START


    def add_table(self, table):
        """ Add a single WaveTable object to the manager. """

        self.tables[table.descriptor.name] = table
        self.descriptors[table.descriptor.name] = table.descriptor

    
    def read_from_directory(self, directory_path):
        """ Load all wavetables (mipmap) from a directory. """

        dirname = os.path.dirname(directory_path)

        for filename in os.listdir(directory_path):

            try:
                name, extension = filename.split('.')
            except ValueError:
                continue # invalid file or directory

            if extension != 'table':
                continue
            
            wavetable = WaveTable.from_file(os.path.join(dirname, filename), self.base_address)

            if wavetable.descriptor.n_frames_log2 <= 3:
                self.base_address += 0x8000 # 1 sector
            else:
                self.base_address += 0x10000 # 2 sectors

            logger.info(f'Read table {name} from file')
            self.add_table(wavetable)

        
    def read_from_sdram(self):
        """ Read table desriptors and all tables from the SDRAM. """

        self.read_table_descriptors()

        for desc in self.descriptors.values():
            self.tables[desc.name] = WaveTable.from_sdram(desc, self.client)

    
    def read_table_descriptors(self):
        """ Read all valid table descriptors from the SDRAM. """

        data = b''

        # Read table descriptors from SDRAM 
        data = self.client.read_sdram_bytes(
            self.FLASH_DESCRIPTOR_START, self.FLASH_DESCRIPTOR_END - self.FLASH_DESCRIPTOR_START)

        while len(data) >= 106:
            valid, frames_log2, base_address, raw_name = struct.unpack('>BBI100s', data[:106])
            name = raw_name.decode('ascii').rstrip('\0')
            if valid:
                self.descriptors[name] = TableDescriptor(name, frames_log2, base_address)
                self.tables[name] = None
                logger.info(f'read table descriptor {name} [0x{base_address:08X}]')
            else:
                break

            data = data[106:] 

        
    def write_table_descriptors(self):
        """ Write all loaded table descriptors to the FLASH. """

        data = b''
        address = 0

        for desc in self.descriptors.values():
            data += struct.pack('>BBI100s', 0x01, desc.n_frames_log2, desc.base_address, bytes(desc.name, 'ascii'))

        # Fill rest of descriptor section with zero's.
        data += b'\x00' * (2 * (self.FLASH_DESCRIPTOR_END - self.FLASH_DESCRIPTOR_START) - len(data))

        self.client.write_sdram_bytes(0, data)
        self.client.dma_sdram_to_flash(0, 0, 1)


    def write_tables(self):

        for table in self.tables.values():
            table.write_to_flash(self.client)

    
    def load_from_flash(self):
        """ Load table descriptors and all wavetables from flash to SDRAM. """

        self.client.dma_flash_to_sdram(0, 0, self.FLASH_TABLE_END // 2**15)


def main():

    import matplotlib.pyplot as plt

    logging.basicConfig(level=logging.INFO)

    client = WaveArray()
    tm = TableManager(client)

    # # Read wavetables from directory.
    # module_path = os.path.dirname(os.path.abspath(__file__))
    # table_path = os.path.join(module_path, '../../../data/wavetables/')
    # tm.read_from_directory(table_path)

    # # Write descriptor and tables to FLASH.
    # tm.write_table_descriptors()
    # tm.write_tables()

    # Load FLASH and read descriptors and tables from SDRAM.
    # tm.descriptors = {}
    # tm.tables = {}
    tm.load_from_flash()
    tm.read_from_sdram()

    print(tm.descriptors)
    # print(tm.tables)
    name = list(tm.descriptors.keys())[12]
    print(tm.descriptors[name].print())
    # print(tm.tables[0].data)

    plt.figure()
    plt.plot(tm.tables[name].data)
    plt.show()


if __name__ == '__main__':
    main()