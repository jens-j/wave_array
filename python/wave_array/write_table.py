import os 
import logging 

import numpy as np
import matplotlib.pyplot as plt

from wave_array.client.client import WaveArray


logging.basicConfig(level=logging.DEBUG)
log = logging.getLogger(__name__)

wave_array = WaveArray(None, None)

filepath = os.path.join(os.path.dirname(__file__), '../../data/wavetables/basic.table')

with open(filepath) as f:

    string_table = f.read().split('\n')
    string_table = list(filter(lambda x: x != '', string_table))
    table_in = np.array([int(x, 16) for x in string_table]).astype('int16')

    print(table_in)

    log.info('write table')
    wave_array.write_sdram(0, table_in)

# table_in = np.zeros(0x5000).astype('uint16')
# wave_array.write_sdram(0, table_in)

table_out = wave_array.read_sdram(0, 0x5000)

# print(wave_array.dev.read(WaveArray.REG_TABLE_BASE_L))
# print(wave_array.dev.read(WaveArray.REG_TABLE_FRAMES))

wave_array.dev.write(WaveArray.REG_TABLE_BASE_L, 0x0000)
wave_array.dev.write(WaveArray.REG_TABLE_BASE_H, 0x0000)
wave_array.dev.write(WaveArray.REG_TABLE_FRAMES, 2)
wave_array.dev.write(WaveArray.REG_TABLE_NEW, 1)

fig = plt.figure()
plt.plot(table_in.astype('int32'))
plt.plot(table_out.astype('int32') + 0x200)
plt.show()