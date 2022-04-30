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

    N_COEFF = 399 # Must be uneven.


    def __init__(self, name, waveform):

        assert len(waveform) == self.L0_SIZE

        self.name = name
        self.waveform = waveform # Should be in range [-1, 1].

        self.spectra = [] # List of spectra for each mipmap level.
        self.subtables = [] # List of mipmap subtables

        self.mipmap_table = self._create_table() # Flattened mipmap table.


    def _create_table(self):

        mipmap_table = np.array([])
        fft_size = self.L0_SIZE

        # Create halfband filter.
        filter_coeffs = signal.remez(self.N_COEFF, [0, 0.490, 0.499, 0.5], [1, 0])

        # w, h = signal.freqz(filter_coeffs, [1], worN=2000)
        # fig, axis = plt.subplots(1)
        # axis.plot(w / (2 * np.pi), 20 * np.log10(np.abs(h)))

        # Add the unfiltered L0 spectrum.
        self.subtables.append(self.waveform)
        self.spectra.append(np.fft.rfft(self.waveform / self.SAMPLE_MAX, fft_size))

        print(self.spectra)

        for level in range(0, self.L0_SIZE_LOG2 - 1):

            offset = self.N_COEFF // 2

            # filter and downsample to create next subtable
            filtered_table = np.convolve(self.subtables[-1], filter_coeffs)
            self.subtables.append(filtered_table[offset:-offset:2])
            self.spectra.append(np.fft.rfft(
                self.subtables[-1] / self.SAMPLE_MAX, 2**(self.L0_SIZE_LOG2 - level)))


            mipmap_table = np.append(mipmap_table, self.subtables[-1])

        # Pad mipmap with zero's to power of two
        pad_length = 2**self.L0_SIZE_LOG2 * 2 - len(mipmap_table)
        mipmap_table = np.append(mipmap_table, [0] * pad_length)

        return mipmap_table


    def plot(self):

        fig, axes = plt.subplots(self.L0_SIZE_LOG2, 2)
        fig.suptitle(self.name)

        spectrum_x = np.array(range(self.L0_SIZE // 2 + 1))

        print(self.spectra)

        for level in range(0, self.L0_SIZE_LOG2):

            # spectrum = np.abs(self.spectra[level])
            spectrum = 20 * np.log10(np.abs(self.spectra[level])**2)

            # Plot spectra
            axes[level, 0].set_title('L{} spectrum'.format(level))

            axes[level, 0].plot(spectrum)
            axes[level, 0].plot(spectrum, 'ro', markersize=2)

            # axes[level, 0].plot(spectrum_x[:(self.L0_SIZE // 2**(level + 1) + 1)],
            #                     spectrum[:(self.L0_SIZE // 2**(level + 1) + 1)])
            #
            # axes[level, 0].plot(spectrum_x[:(self.L0_SIZE // 2**(level + 1) + 1)],
            #                     spectrum[:(self.L0_SIZE // 2**(level + 1) + 1)],
            #                     'ro', markersize=2)

            # axes[level, 0].set_yscale("log");
            # axes[level, 0].plot(spectrum_x[:8], np.abs(self.spectra[level][:8] / self.L0_SIZE)**2)#, 'ro', markersize=2)

            # axes[level, 1].set_title('L{} waveform'.format(level))
            # axes[level, 1].plot(self.filtered_tables[level])

            axes[level, 1].set_title('L{} table'.format(level))
            axes[level, 1].plot(self.subtables[level])
            axes[level, 1].plot(self.subtables[level], 'ro', markersize=2)

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

    mm = Mipmap('acid', acid)
    mm.plot()
    mm.write_table()


if __name__ == '__main__':
    main()
