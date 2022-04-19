import numpy as np
import matplotlib.pyplot as plt
import matplotlib.animation as animation
import argparse
import time


def hex_to_16bit2scomplement(hexval):

    val = int(hexval, 16)
    if val & 0x8000:
        val -= 0x10000
    return val


class TableTester():

    SAMPLE_RATE = 48000
    N_FRAMES = 500
    INTERPOLATE = False

    FFT_SIZE_LOG2 = 16
    FFT_SIZE = 2**FFT_SIZE_LOG2

    # MIPMAP_LIMITS = [0x20000, 0x10000, 0x8000, 0x4000, 0x2000, 0x1000, 0x800, 0x400, 0x200]
    MIPMAP_LIMITS = [0x15555, 0xAAAA, 0x5555, 0x2AAA, 0x1555, 0xAAA, 0x555, 0x2AA, 0x155]
    MIPMAP_OFFSETS = [0x000, 0x800, 0XC00, 0xE00, 0xF00, 0xF80, 0xFC0, 0xFE0, 0xFF0, 0xFF8]


    def __init__(self, filename):

        # self.table = np.loadtxt(filename, dtype=hex)
        self.table = np.loadtxt(filename, dtype='int32', converters={0: hex_to_16bit2scomplement})
        self.fig, (self.ax1, self.ax2) = plt.subplots(2,1, figsize=(20, 12))
        plt.yscale('log')
        self.ax1.set_xlim(0, self.FFT_SIZE)
        self.ax1.set_ylim(-2**15, 2**15)
        self.ax1.set_xlabel('sample number')
        self.ax1.set_ylabel('sample value')
        self.ax2.set_xlim(0, self.SAMPLE_RATE // 2)
        self.ax2.set_ylim(0, 1E8)
        self.ax2.set_xlabel('f (Hz)')
        self.ax2.set_ylabel('Power')
        self.lines = [self.ax1.plot([], [])[0], self.ax2.plot([], [])[0]]

        frequencies = list(2 * np.logspace(1, 4, self.N_FRAMES).astype(int))
        duplicates = set()
        for f in frequencies[:]:
            if f in duplicates:
                frequencies.remove(f)
            else:
                duplicates.add(f)

        print(frequencies)

        # anim = animation.FuncAnimation(
        #     self.fig, self._animate, init_func=self._init_data,
        #     frames=frequencies, blit=True, interval=100, repeat=False)
        #
        # anim.save('mipmap.gif', writer='imagemagick')

        self._animate(256.9 * 23.4375)
        plt.show()



    def _init_data(self):

        self.lines[0].set_data([], [])
        self.lines[1].set_data([], [])

        return self.lines


    def _animate(self, frequency):

        print(frequency)

        level = 0
        samples = []
        velocity = int(2**19 / self.SAMPLE_RATE * frequency)

        for limit in self.MIPMAP_LIMITS:
            if velocity > limit:
                level += 1

        phase = np.array(np.array(range(self.FFT_SIZE)) * velocity % (1 << 19))

        for x in phase:

            if self.INTERPOLATE:
                index_a = int(x >> (8 + level))
                index_b = (index_a + 1) % 2**(11 - level)
                index_a += self.MIPMAP_OFFSETS[level]
                index_b += self.MIPMAP_OFFSETS[level]

                if x % 256 == 0:
                    coeff_a = 1.0
                    coeff_b = 0.0
                else:
                    coeff_b = (x % 256) / 256
                    coeff_a = 1.0 - coeff_b

                samples.append(coeff_a * self.table[index_a] + coeff_b * self.table[index_b])
            else:
                index_a = int(x >> (8 + level)) + self.MIPMAP_OFFSETS[level]
                samples.append(self.table[index_a])

        spectrum = np.abs(np.fft.rfft(samples) / self.FFT_SIZE)**2

        cycle_resolution = int(np.ceil(self.SAMPLE_RATE / frequency))
        self.ax1.set_xlim(0, cycle_resolution)
        self.ax2.set_xlim(0, self.SAMPLE_RATE // 2)
        self.fig.suptitle('{} Hz, level {}, table sampling rate {}'.format(
            frequency, level, cycle_resolution / 2**(11 - level)))

        x_time = np.array(range(cycle_resolution))
        x_spectrum = np.array(range(self.FFT_SIZE // 2 + 1)) * self.SAMPLE_RATE / self.FFT_SIZE

        self.lines[0].set_data(x_time, samples[:cycle_resolution])
        self.lines[1].set_data(x_spectrum, spectrum)

        return self.lines



def main():

    parser = argparse.ArgumentParser()
    parser.add_argument('--filename', '-f', type=str, help='filename of mipmap table')
    args = parser.parse_args()

    tt = TableTester(args.filename)




if __name__ == '__main__':
    main()
