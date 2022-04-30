import numpy as np
from scipy import signal
from scipy.io import wavfile
import matplotlib.pyplot as plt

from wavearray.mipmap.mipmap import Mipmap
from wavearray.oscillator.polyphase import PolyphaseFilter

class Oscillator:

    FFT_LENGTH = int(2**16)

    def __init__(self, mipmap, frequency, sample_rate):

        self.mipmap = mipmap
        self.F = frequency
        self.Fs = sample_rate

        self.Fb = 2 * self.Fs / Mipmap.L0_SIZE # Base frquency of L0 table (with 2x oversampling).
        self.r = self.F / self.Fb # Global intepolator resample factor w.r.t. L0 table.\

        if  self.r < 1:
            self.l = 0
        self.l = max(0, int(np.ceil(np.log2(self.r)))) # Mipmap level.
        self.rho = self.r / 2**self.l # [0.5, 1.0], Local resample factor w.r.t. active mipmap table.


        print('F   = ', self.F)
        print('Fb  = ', self.Fb)
        print('r   = ', self.r)
        print('rho = ', self.rho)
        print('l   = ', self.l)


        self.pfb = PolyphaseFilter(15, 64, 0.45) # Interpolation filter.
        # self.pfb.plot()
        self.waveform = self.generate_waveform(1)


    def generate_waveform(self, cycles):
        """ Generate a waveform of lenght cycles. """

        phase = 0.0 # [0.0, table_size] Table phase.
        velocity = self.rho # [0.5, 1.0] Oscillator normalized angular velocity (table steps / cycle).
        table_length = Mipmap.L0_SIZE >> self.l # Length of selected mipmap table.
        waveform = np.array([]) # Waveform to be generated.
        samples = np.array([]) # Interpolation filter input data.

        # Loop until x cycles of the output wave are generated.
        while phase < cycles * table_length:

            phase += velocity # Increment table address.

            table_index_int = int(phase) # Integer part of index.
            table_index_frac = phase - table_index_int # Fractional part of index.

            # Table index shifted for convolution.
            table_index_start = (table_index_int - self.pfb.N // 2) % table_length

            # Collect input samples.
            samples = self.mipmap.subtables[self.l][
                table_index_start:(table_index_start+self.pfb.N)]

            samples = np.append(samples, self.mipmap.subtables[self.l][
                :max(0, table_index_start+self.pfb.N-table_length)])

            # Halve the input to avoid overflow because of interpolation
            samples = samples / 2

            # Interpolate new sample and append to waveform.
            waveform = np.append(waveform, self.pfb.interpolate(samples, table_index_frac))

        return waveform


    def plot(self):

        # print(self.waveform / Mipmap.SAMPLE_MAX)

        psd_x = np.linspace(0, 0.5, self.FFT_LENGTH // 2 + 1)
        # window = signal.chebwin(len(self.waveform), 80)
        power_spectrum = np.abs(np.fft.rfft(self.waveform / Mipmap.SAMPLE_MAX, self.FFT_LENGTH) / self.FFT_LENGTH)**2

        # print(self.waveform / Mipmap.SAMPLE_MAX)
        # print(psd)
        # print(len(psd))

        print('len(waveform)       =', len(self.waveform))
        print('sum(samples)        =', np.sum(np.abs(self.waveform / Mipmap.SAMPLE_MAX)**2))
        print('sum(power_spectrum) =', np.sum(power_spectrum))

        fig, axes = plt.subplots(3)
        axes[0].plot(self.waveform)
        axes[1].plot(psd_x, 10 * np.log10(2 * power_spectrum / (2 * self.Fs)))
        # axes[1].set_ylim([-300, 25])
        axes[2].psd(self.waveform / Mipmap.SAMPLE_MAX, NFFT=2048, Fs=96000)
        plt.show()


def main():

    acid = wavfile.read("Acid.wav")[1][:2048] * 2
    # print(max(np.abs(acid)))
    acid *= Mipmap.SAMPLE_MAX / max(np.abs(acid))

    square = np.concatenate(
        (np.ones(Mipmap.L0_SIZE // 2), -np.ones(Mipmap.L0_SIZE // 2))) * Mipmap.SAMPLE_MAX



    # mm = Mipmap('acid', acid)
    mm = Mipmap('square', square)

    osc = Oscillator(mm, 200, 48000)
    waveform = osc.generate_waveform(1)
    # print(waveform)
    osc.plot()


if __name__ == '__main__':
    main()
