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


    def __init__(self, name, waveform, prefilter=False):

        assert len(waveform) == self.L0_SIZE

        self.name = name
        self.waveform = waveform # Should be in range [-1, 1].
        self.prefilter = prefilter

        self.spectra = [] # List of spectra for each mipmap level.
        self.subtables = [] # List of mipmap subtables

        self.mipmap_table = self._create_table() # Flattened mipmap table.


    def _create_table(self):

        mipmap_table = np.array([])
        fft_size = self.L0_SIZE

        # Create prefilter.
        prefilter_coeffs = signal.remez(self.N_COEFF, [0, 0.490, 0.499, 0.5], [1, 0])

        # Create halfband filter.
        hb_filter_coeffs = signal.remez(self.N_COEFF, [0, 0.245, 0.255, 0.5], [1, 0])

        offset = self.N_COEFF // 2

        # w, h = signal.freqz(hb_filter_coeffs, [1], worN=2000)
        # fig, axis = plt.subplots(1)
        # axis.plot(w / (2 * np.pi), 20 * np.log10(np.abs(h)))

        # Add the unfiltered L0 spectrum.
        self.subtables.append(self.waveform)

        # prefiltering the table is useful for waveforms generated in code. Sampled waveforms
        # should not have to be prefiltered.
        if self.prefilter:
            filtered_table = np.convolve(self.subtables[0], prefilter_coeffs)
            filtered_table = filtered_table * Mipmap.SAMPLE_MAX / np.max(np.abs(filtered_table)) # Normalize to avoid overflow
            self.subtables[0] = filtered_table[offset:-offset].astype(int)


        self.spectra.append(np.fft.rfft(self.waveform / self.SAMPLE_MAX, fft_size))

        for level in range(0, self.L0_SIZE_LOG2 - 2):

            # filter and downsample to create next subtable
            filtered_table = np.convolve(self.subtables[-1], hb_filter_coeffs)

            # Normalize to avoid overflow
            filtered_table = filtered_table * Mipmap.SAMPLE_MAX / np.max(np.abs(filtered_table))

            self.subtables.append(filtered_table[offset:-offset:2].astype(int))
            self.spectra.append(np.fft.rfft(
                self.subtables[-1] / self.SAMPLE_MAX, 2**(self.L0_SIZE_LOG2 - level)))


            mipmap_table = np.append(mipmap_table, self.subtables[-1])

        # Pad mipmap with zero's to power of two
        pad_length = 2**self.L0_SIZE_LOG2 * 2 - len(mipmap_table)
        mipmap_table = np.append(mipmap_table, [0] * pad_length)

        return mipmap_table


    def plot(self):

        fig, axes = plt.subplots(self.L0_SIZE_LOG2 - 1, 2)
        fig.suptitle(self.name)

        spectrum_x = np.array(range(self.L0_SIZE // 2 + 1))

        # print(self.spectra)

        for level in range(0, self.L0_SIZE_LOG2 - 1):

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


    def write_table(self, filename=None):

        print(self.subtables[0])

        counter = 0
        mode = 'a' if filename else 'w'
        filename = filename if filename else f"{self.name}_mipmap.data"
        with open(filename, mode) as f:
            for subtable in self.subtables:
                print(subtable)
                for value in subtable:
                    # f.write(f"{value & 0xFFFF:04X}")
                    # f.write(f"{value & 0xFFFF:04X}")
                    # f.write(f"{value & 0xFFFF:04X}")
                    f.write(f"{value & 0xFFFF:04X}\n")
                    counter += 1

            for i in range(4096 - counter):
                # f.write(f"0000000000000000\n")
                f.write(f"0000\n")


def main():

    from wave_array.mipmap import waveforms

    # Generate some waveforms.
    saw = waveforms.saw()
    square = waveforms.square()
    acid = waveforms.acid()

    mm = Mipmap('saw', saw, prefilter=True)
    mm.plot()
    mm.write_table()


if __name__ == '__main__':
    main()
