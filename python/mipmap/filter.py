import numpy as np
import matplotlib.pyplot as plt
from scipy import signal

TABLE_SIZE = 2048
FFT_SIZE = TABLE_SIZE


waveform = [(i / TABLE_SIZE * 2**16) % 2**16 for i in range(TABLE_SIZE)]
waveform = np.array(waveform, dtype=np.int16)

print(waveform)

# # b, a = signal.butter(40, 1/3, 'low')
# b = signal.firwin(2**16, 2/3000, window='hamming')
# w, h = signal.freqz(b)
#
# # plt.plot(waveform)
# plt.plot(w / np.pi, 20 * np.log10(abs(h)))
# plt.show()


spectrum = np.fft.rfft(waveform, FFT_SIZE)
spectrum_x = np.linspace(0, 1, FFT_SIZE // 2 + 1)
power = np.abs(spectrum)

spectrum_trunc = spectrum.copy()
spectrum_trunc[(FFT_SIZE // 6):] = 0.+0.j
power_trunc = np.abs(spectrum_trunc)

waveform_filt = np.fft.irfft(spectrum_trunc, n=TABLE_SIZE)

scale = (2**15 - 1) / np.max(waveform_filt)

waveform_filt *= scale

print(waveform_filt.dtype)
print(waveform_filt)

fig, axes = plt.subplots(4)
axes[0].plot(waveform)
axes[1].vlines(spectrum_x, 0, power)
axes[2].vlines(spectrum_x, 0, power_trunc)
axes[3].plot(waveform_filt)

plt.show()
