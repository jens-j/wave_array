import numpy as np
import matplotlib.pyplot as plt
from scipy import signal
from scipy.io.wavfile import read

class Mipmap:
    """ This class creates a mipmap table from a 2048 sample long waveform. """

    L0_SIZE_LOG2 = 11
    L0_SIZE = 2**L0_SIZE_LOG2 # FFT size always same as wavetable

    SAMPLE_MIN = -2**15
    SAMPLE_MAX = 2**15 - 1


    def __init__(self, name, waveform):

        assert len(waveform) == self.L0_SIZE

        self.name = name
        self.waveform = waveform # Should be in range [-1, 1].

        self.spectra = [] # List of spectra for each mipmap level.
        self.filtered_tables = [] # list of filtered waveforms for each mipmap level.
        self.decimated_tables = [] # list of filtered and decimated waveforms for each mipmap level.

        self.mipmap_table = self._create_table() # Flattened mipmap table.


    def _create_table(self):

        mipmap_table = []
        fft_size = self.L0_SIZE

        self.spectra.append(np.fft.fft(self.waveform, fft_size) / self.SAMPLE_MAX / fft_size)

        # print(self.waveform)
        # print('sum(psd(f)) =', sum(np.abs(self.spectra[0])**2))

        # print(self.spectra[0])

        for level in range(0, self.L0_SIZE_LOG2 - 1):

            # Filter above 1/2 Fs for L0. The cutoff is halved for each succesive table
            self.spectra.append(self.spectra[0].copy())
            self.spectra[level][int(np.ceil(self.L0_SIZE / (2 * 2**level)) + 1):] = 0+0j # 1E-9+1E-9j

            # Perform the IFFT of the modified spectrum to get the table.
            self.filtered_tables.append(
                np.fft.irfft(self.spectra[level], n=int(self.L0_SIZE)) * fft_size * self.SAMPLE_MAX)
            self.decimated_tables.append(
                np.fft.irfft(self.spectra[level], n=int(self.L0_SIZE / 2**level))
                * fft_size * self.SAMPLE_MAX / 2**level)

            # # Normalize the table
            # scale = self.SAMPLE_MAX / np.max(np.abs(self.decimated_tables[-1]))
            # self.decimated_tables[-1] *= scale

            mipmap_table.extend(self.decimated_tables[-1])

        # Pad mipmap with zero's to power of two
        pad_length = 2**self.L0_SIZE_LOG2 * 2 - len(mipmap_table)
        mipmap_table.extend([0] * pad_length)

        return mipmap_table


    def plot(self):

        fig, axes = plt.subplots(self.L0_SIZE_LOG2 - 1, 3)
        fig.suptitle(self.name)

        spectrum_x = np.array(range(self.L0_SIZE // 2 + 1))

        for level in range(0, self.L0_SIZE_LOG2 - 1):

            # spectrum = np.abs(self.spectra[level])
            spectrum = 20 * np.log10(np.abs(self.spectra[level]) / self.SAMPLE_MAX)

            # Plot tables
            axes[level, 0].set_title('L{} spectrum'.format(level))

            axes[level, 0].plot(spectrum_x[:(self.L0_SIZE // 2**(level + 1) + 1)],
                                spectrum[:(self.L0_SIZE // 2**(level + 1) + 1)])

            axes[level, 0].plot(spectrum_x[:(self.L0_SIZE // 2**(level + 1) + 1)],
                                spectrum[:(self.L0_SIZE // 2**(level + 1) + 1)],
                                'ro', markersize=2)

            # axes[level, 0].set_yscale("log");
            # axes[level, 0].plot(spectrum_x[:8], np.abs(self.spectra[level][:8] / self.L0_SIZE)**2)#, 'ro', markersize=2)

            axes[level, 1].set_title('L{} waveform'.format(level))
            axes[level, 1].plot(self.filtered_tables[level])

            axes[level, 2].set_title('L{} table'.format(level))
            axes[level, 2].plot(self.decimated_tables[level])
            axes[level, 2].plot(self.decimated_tables[level], 'ro', markersize=2)

        plt.show()


    def write_table(self):

        filename = f"{self.name}_mipmap.data"
        with open(filename, 'w') as f:
            for value in self.mipmap_table:
                f.write(f"{int(value) & 0xFFFF:04X}\n")


def main():

    # Generate some waveforms.
    saw = np.array([(2.0 * (i + 0.5) / Mipmap.L0_SIZE + 1.0) % 2 - 1.0
        for i in range(Mipmap.L0_SIZE)])

    square = np.concatenate(
        (np.ones(Mipmap.L0_SIZE // 2), -np.ones(Mipmap.L0_SIZE // 2))) * Mipmap.SAMPLE_MAX

    acid = read("Acid.wav")[1][:2048]

    mm = Mipmap('square', square)
    mm.plot()
    mm.write_table()


if __name__ == '__main__':
    main()
