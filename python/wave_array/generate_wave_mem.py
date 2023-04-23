import numpy as np
import matplotlib.pyplot as plt

from wave_array.mipmap.mipmap import Mipmap
from wave_array.mipmap import waveforms

# Generate some mipmap tables.
frame_tables = []
frame_tables.append(Mipmap('frame_0', waveforms.sine(), prefilter=True))
frame_tables.append(Mipmap('frame_1', waveforms.triangle(), prefilter=True))
frame_tables.append(Mipmap('frame_2', waveforms.saw(), prefilter=True))
frame_tables.append(Mipmap('frame_3', waveforms.square(), prefilter=True))

counter = 0


with open('osc_wave_memory.coe', 'w') as f:

    # for sub_frame_0, sub_frame_1 in zip(wave_0_table.subtables, wave_1_table.subtables):
    #     for frame_0_sample, frame_1_sample in zip(sub_frame_0, sub_frame_1):
    
    #         # f.write("0000000000000000\n")
    #         # f.write("00000000")
    #         f.write(f"{int(wave_1_sample) & 0xFFFF:04X}")
    #         f.write(f"{int(wave_0_sample) & 0xFFFF:04X}")
    #         f.write(f"{int(wave_1_sample) & 0xFFFF:04X}")
    #         f.write(f"{int(wave_0_sample) & 0xFFFF:04X}\n")
    #         counter += 1

    for level in range(len(frame_tables[0].subtables)):

        for sample in range(len(frame_tables[0].subtables[level])):

            for i in range(4):
                f.write(f"{int(frame_tables[i].subtables[level][sample]) & 0xFFFF:04X}") 

            f.write('\n')   
            counter += 1

 

    # Pad with zero's
    for i in range(4096 - counter):
        f.write(f"0000000000000000\n")
