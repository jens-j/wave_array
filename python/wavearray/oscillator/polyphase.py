import numpy as np
from scipy import signal
import matplotlib.pyplot as plt

class PolyphaseFilter:

    FFT_LENGTH = 4096

    def __init__(self, taps, phases, cutoff):

        self.N = taps
        self.M = phases
        self.L = phases * taps
        self.fc = cutoff

        self.filterbank = []
        self.offsets = []
        self.window = None
        self.sinc_x = None
        self.sinc = None

        self.init()


    def init(self):
        """ Create an L length windowed sinc filter. The filter is made symmetric around zero by
            making the first filter coefficient zero.
        """

        # Generate an odd length symmetric window and prepend with a zero to make it length L.
        self.window = signal.chebwin(self.L - 1, 80)
        self.window = np.insert(self.window, 0, 0) #

        # Create the interleaved sync filter
        self.sinc_x = (np.array(range(self.L)) - self.L // 2) * 2 * self.fc / self.M

        self.sinc = np.sinc(self.sinc_x)
        self.sinc[0] = 0 # set first index to zero even though the window will already make it zero.
        # self.remez = signal.remez(self.L, [0, 0.35, 0.45, 0.5], [1, 0])

        # Split the phases into individual filters of length N.
        for i, phase in enumerate(list(range(self.M))):
            self.offsets.append(self.sinc_x[i::self.M])

            self.filterbank.append(self.sinc[i::self.M] * self.window[i::self.M])
            # self.filterbank.append(self.remez[i::self.M])


    def plot(self):

        fig, axes = plt.subplots(2)

        # Plot the filterbank.
        for offset, coefficients in zip(self.offsets, self.filterbank):
            axes[0].plot(offset, coefficients, 'x')

        # Plot the filter window.
        axes[0].plot(self.sinc_x, self.window, 'black')

        # Generate and plot the power spectrum.
        psd_x = np.linspace(0, 0.5, self.FFT_LENGTH // 2 + 1)

        # for i in range(self.M):
        #     psd = 20 * np.log10(np.abs(np.fft.rfft(self.filterbank[i], n=self.FFT_LENGTH)))
        #     axes[1].plot(psd_x, psd)

        psd = 20 * np.log10(np.abs(np.fft.rfft(self.filterbank[0], n=self.FFT_LENGTH)))
        axes[1].plot(psd_x, psd)

        axes[1].grid()
        plt.show()


def main():
    pfb = PolyphaseFilter(16, 4, 0.25)
    pfb.plot()


if __name__ == '__main__':
    main()
