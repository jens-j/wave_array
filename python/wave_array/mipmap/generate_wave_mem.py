import numpy as np
import matplotlib.pyplot as plt

from wave_array.mipmap.mipmap import Mipmap
from wave_array.mipmap import waveforms

# Generate some waveforms.
wave_a = waveforms.saw()
wave_b = waveforms.acid()

wave_a_table = Mipmap('wave_a', wave_a, prefilter=True)
wave_b_table = Mipmap('wave_b', wave_b)
counter = 0

# Write a table with the saw mipmap in position 0, sqaure in position 1 and zeros in position 2 and 3.
with open('osc_wave_memory.coe', 'w') as f:
    for sub_wave_a, sub_wave_b in zip(wave_a_table.subtables, wave_b_table.subtables):
        for wave_a_sample, wave_b_sample in zip(sub_wave_a, sub_wave_b):
            f.write("00000000")
            f.write(f"{int(wave_b_sample) & 0xFFFF:04X}")
            f.write(f"{int(wave_a_sample) & 0xFFFF:04X}\n")
            counter += 1

    # Pad with zero's
    for i in range(4096 - counter):
        f.write(f"0000000000000000\n")
