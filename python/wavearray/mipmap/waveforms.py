import numpy as np
from wavearray.mipmap.mipmap import Mipmap
from scipy.io import wavfile


def saw():
    return np.array([(2.0 * (i + 0.5) / Mipmap.L0_SIZE + 1.0) % 2 - 1.0
        for i in range(Mipmap.L0_SIZE)]) * Mipmap.SAMPLE_MAX

def square():
    square = np.concatenate(
        (np.ones(Mipmap.L0_SIZE // 2), -np.ones(Mipmap.L0_SIZE // 2))) * Mipmap.SAMPLE_MAX

def acid():
    acid = wavfile.read("Acid.wav")[1][:2048]
    acid *= Mipmap.SAMPLE_MAX / max(acid) # Normalize to sample size.
    return acid
