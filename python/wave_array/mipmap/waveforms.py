import os

import numpy as np
from scipy.io import wavfile

from wave_array.mipmap.mipmap import Mipmap


def sine():
    return np.sin([x * 2 * np.pi / Mipmap.L0_SIZE for x in range (Mipmap.L0_SIZE)]) * Mipmap.SAMPLE_MAX

def triangle(): 
    
    wave = np.zeros(Mipmap.L0_SIZE)

    for i in range(Mipmap.L0_SIZE):

        if i < Mipmap.L0_SIZE // 4:
            wave[i] = i * 4 / Mipmap.L0_SIZE * Mipmap.SAMPLE_MAX

        elif i <= Mipmap.L0_SIZE * 3 // 4:
            wave[i] = ((i - Mipmap.L0_SIZE // 4) * -4 / Mipmap.L0_SIZE + 1) * Mipmap.SAMPLE_MAX

        else:
            wave[i] = ((i - Mipmap.L0_SIZE * 3 // 4) * 4 / Mipmap.L0_SIZE - 1) * Mipmap.SAMPLE_MAX

    return wave

def saw():
    return np.array([(2.0 * (i + 0.5) / Mipmap.L0_SIZE + 1.0) % 2 - 1.0
        for i in range(Mipmap.L0_SIZE)]) * Mipmap.SAMPLE_MAX

def square():
    return np.concatenate(
        (np.ones(Mipmap.L0_SIZE // 2), -np.ones(Mipmap.L0_SIZE // 2))) * Mipmap.SAMPLE_MAX

def acid():
    wave = wavfile.read(f"{os.path.dirname(__file__)}\Acid.wav")[1][:2048]
    wave *= Mipmap.SAMPLE_MAX / max(wave) # Normalize to sample size.
    return wave
