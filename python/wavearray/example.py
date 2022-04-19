import numpy as np
import matplotlib.pyplot as plt

fc = 0.2  # Cutoff frequency as a fraction of the sampling rate (in (0, 0.5)).
N = 25    # Number of coefficients.
L = 1024  # Length of frequency response.

# Compute sinc filter with Hamming window.
n = np.arange(N)
h = np.sinc(2 * fc * (n - (N - 1) / 2)) * np.hamming(N)
h /= np.sum(h)

# Pad filter with zeros.
h_padded = np.zeros(L)
h_padded[0 : N] = h

# Compute frequency response; only keep first half.
H = np.abs(np.fft.fft(h_padded))[0 : L // 2 + 1]

# Plot frequency response (in dB).
plt.figure()
# plt.plot(np.linspace(0, 0.5, len(H)), 20 * np.log10(H))
plt.plot(h, 'x')
plt.xlabel('Normalized frequency')
plt.ylabel('Gain [dB]')
# plt.ylim([-100, 10])
plt.grid()
plt.show()
