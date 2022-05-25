import numpy as np
from scipy import signal
import matplotlib.pyplot as plt


class Halfband:

    FFT_LENGTH = 2048

    def __init__(self, N):

        assert N % 2 == 1, 'length must be odd'

        self.N = N # Filter length (must be odd).

        # Generate an odd length symmetric window and prepend with a zero to make it length N.
        self.window = signal.chebwin(self.N, 80)
        bound = (self.N-1) / 4
        sinc_x = np.linspace(-bound, bound, self.N)
        self.coefficients = np.sinc(sinc_x) * self.window

        for i, coefficient in enumerate(self.coefficients[:N//2:2]):
            end = '\r\n' if (i + 1) % 8 == 0 else ' '
            print(f'x"{int(coefficient * 0x7FFF) & 0xFFFF:04X}",', end=end)


    def plot(self):

        psd_x = np.linspace(0, 0.5, self.FFT_LENGTH // 2 + 1)
        psd = 20 * np.log10(np.abs(np.fft.rfft(self.coefficients, n=self.FFT_LENGTH)))

        fig, axes = plt.subplots(3)
        axes[0].plot(self.window, '.-')
        axes[1].plot(self.coefficients, '.-')
        axes[2].plot(psd_x, psd)
        plt.show()



def main():
    hb = Halfband(63)
    hb.plot()


if __name__ == '__main__':
    main()
