import os 
from scipy.io import wavfile
import matplotlib.pyplot as plt
import numpy as np

from wave_array.mipmap.mipmap import Mipmap

module_path = os.path.dirname(os.path.abspath(__file__))
directory_in = os.path.join(module_path, '../../../data/wav/Analog/')
directory_out = os.path.join(module_path, '../../../data/wavetables/')

for filename in os.listdir(directory_in):

    samplerate, data = wavfile.read(os.path.join(directory_in, filename))
    name, extension = filename.split('.')

    if extension != 'wav':
        continue

   
    max_power = int(np.floor(np.log2(len(data) // 2048)))
    frames = []
    tables = np.array([], dtype=np.int16)

    decimation = 1             
    if max_power > 4: # Max 16 frames / table
        decimation = 2**(max_power - 4) 

    # print(samplerate)
    # print(len(data) // 2048)
    # print(max_power)
    # print(decimation)

    for i in range(0, 2**max_power, decimation):
    # for i in range(min(2**max_power, 16)):   

        frame = data[i * 2048:i * 2048 + 2048]
        frames.extend(frame)

        mm = Mipmap('', frame)
        tables = np.concatenate((tables, np.int16(mm.mipmap_table)))

    with open(os.path.join(directory_out, f'{name}.table'), 'w') as f:
        for x in tables:
            f.write(f'{np.uint16(x):04X}\n') # Write as uint for correct formatting.

    print(f'written {name}')

    # if name == "4088":
    #     fig = plt.figure()
    #     axes = fig.subplots(3)
    #     axes[0].plot(data)
    #     axes[1].plot(frames)
    #     axes[2].plot(tables)
    #     plt.show()
    #     exit()