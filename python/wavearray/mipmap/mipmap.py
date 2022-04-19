import numpy as np
import matplotlib.pyplot as plt
from scipy import signal
from scipy.io.wavfile import read

class Mipmap:

    SAMPLE_RATE = 48000

    L0_SIZE_LOG2 = 11
    L0_SIZE = 2**L0_SIZE_LOG2 # FFT size always same as wavetable

    FFT_SIZE_LOG2 = 12
    FFT_SIZE = 2**FFT_SIZE_LOG2

    MIPMAP_LIMITS = [0x20000, 0x10000, 0x8000, 0x4000, 0x2000, 0x1000, 0x800, 0x400, 0x200]
    MIPMAP_OFFSETS = [0x000, 0x800, 0XC00, 0xE00, 0xF00, 0xF80, 0xFC0, 0xFE0, 0xFF0, 0xFF8]


    def __init__(self, name, waveform):

        assert len(waveform) == self.L0_SIZE

        self.name = name
        self.waveform_orig = waveform
        self.mipmap_table = self._create_table()
        self._write_table()


    def _create_table(self):

        mipmap_table = []

        spectrum_orig = np.fft.rfft(self.waveform_orig, self.L0_SIZE)
        spectrum_tables = []
        spectrum_x = np.array(range(self.L0_SIZE // 2 + 1))

        fig, axes = plt.subplots(self.L0_SIZE_LOG2 - 1, 3)
        fig.suptitle(self.name)

        for level in range(0, self.L0_SIZE_LOG2 - 1):

            # Filter above 1/2 Fs for L0. The cutoff is halved for each succesive table
            spectrum_tables.append(spectrum_orig.copy())
            spectrum_tables[level][int(np.ceil(self.L0_SIZE / (2 * 2**level)) + 1):] = 1E-9+1E-9j

            # print(len(spectrum_tables[level]))
            # print(int(np.ceil(self.L0_SIZE / (2 * 2**level))))
            # print(spectrum_tables[level][int(np.ceil(self.L0_SIZE / (2 * 2**level))):])
            # exit()

            # Perform the IFFT of the modified spectrum to get the table.
            full_table = np.fft.irfft(spectrum_tables[level], n=int(self.L0_SIZE))
            small_table = np.fft.irfft(spectrum_tables[level], n=int(self.L0_SIZE / 2**level)) / 2**level

            # Normalize the table
            scale = (2**15 - 1) / np.max(np.abs(small_table))
            small_table *= scale

            mipmap_table.extend(small_table)

            # Plot tables
            axes[level, 0].plot(spectrum_x[:(self.L0_SIZE // 2**(level + 1) + 1)],
                np.abs(spectrum_tables[level][:(self.L0_SIZE // 2**(level + 1) + 1)] / self.L0_SIZE)**2)
            axes[level, 0].plot(spectrum_x[:(self.L0_SIZE // 2**(level + 1) + 1)],
                np.abs(spectrum_tables[level][:(self.L0_SIZE // 2**(level + 1) + 1)] / self.L0_SIZE)**2, 'ro', markersize=2)
            axes[level, 0].set_yscale("log");
            # axes[level, 0].plot(spectrum_x[:8], np.abs(spectrum_tables[level][:8] / self.L0_SIZE)**2)#, 'ro', markersize=2)
            axes[level, 0].set_title('L{} spectrum'.format(level))
            axes[level, 1].plot(full_table)
            axes[level, 1].set_title('L{} waveform'.format(level))
            axes[level, 2].plot(small_table)
            axes[level, 2].plot(small_table, 'ro', markersize=2)
            axes[level, 2].set_title('L{} table'.format(level))

        # Pad mipmap with zero's to power of two
        pad_length = 2**self.L0_SIZE_LOG2 * 2 - len(mipmap_table)
        mipmap_table.extend([0] * pad_length)

        return mipmap_table


    def _write_table(self):

        filename = f"{self.name}_mipmap.data"
        with open(filename, 'w') as f:
            for value in self.mipmap_table:
                f.write(f"{int(value) & 0xFFFF:04X}\n")


def main():

    saw = np.array([(2.0 * (i + 0.5) / Mipmap.L0_SIZE + 1.0) % 2 - 1.0 for i in range(Mipmap.L0_SIZE)])
    square = np.concatenate((np.ones(Mipmap.L0_SIZE // 2), -np.ones(Mipmap.L0_SIZE // 2)))
    acid = read("Acid.wav")[1][:2048] * 2

    Mipmap('saw', saw)
    Mipmap('square', square)
    Mipmap('acid', acid)

    # plt.tight_layout()
    plt.show()

if __name__ == '__main__':
    main()
