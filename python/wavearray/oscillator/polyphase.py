import numpy as np
from scipy import signal
from scipy.io import wavfile
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


    def interpolate(self, data, phase):
        """ Interpolate a sample based on an array of input data and a phase offset
            which is the table index fraction in [0.0, 1.0].
            Linear interpolation is used to refine the filter coefficients.
        """

        assert len(data) == self.N

        m0 = int(phase * self.M) # Coeffient index 0
        m1 = (m0 + 1) % self.M # Coeffient index 1
        d = phase * self.M - m0 # [0.0, 1.0) Fractional part of phase (interpolation weight).

        sample = 0.0

        # print('')
        # print('m0 =', m0)
        # print('m1 =', m1)
        # print('d  =', d)

        # Interpolate coefficients.
        if m1 == 0:
            c = (1.0 - d) * self.filterbank[m0] + d * np.append(self.filterbank[m1][1:], 0)
        else:
            c = (1.0 - d) * self.filterbank[m0] + d * self.filterbank[m1]

        # print('c =', c)

        # Filter input.
        # for n in range(self.N):
        #     sample += c[n] * data[self.N - 1 - n]

        sample = np.sum(c * data[::-1])

        return sample


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

    l = 2048    # Number of samples in waveform.
    fc = 0.3    # normalized cutoff frequency.
    N = 15      # Number of filter taps.
    M = 16      # Number of phases.
    d = 16      # Number of interpolation points between phases.

    pfb = PolyphaseFilter(N, M, fc)
    # pfb.plot()

    # Generate some waveforms.
    acid = wavfile.read("Acid.wav")[1][:2048] * 2
    saw = np.array([(2.0 * (i + 0.5) / l + 1.0) % 2 - 1.0
        for i in range(l)])

    output_samples = []

    for i in range(l * M * d):

        index_int = int(i // (M * d))
        index_frac = i / (M * d) - index_int
        start_index = (index_int - N // 2) % l

        input_samples = saw[index_int:index_int + N]
        input_samples = np.append(input_samples, saw[:max(0, index_int + N - l)])

        # print('')
        # print('i           =', i)
        # print('index_int   =', index_int)
        # print('index_frac  =', index_frac)
        # print('start_index =', start_index)
        #
        # if i == 16:
        #     exit()

        output_samples.append(pfb.interpolate(input_samples, index_frac))


    fig, axis = plt.subplots(1)

    # axis.plot(saw, '.')

    # axis.plot(output_samples, '.k')
    axis.plot(output_samples, 'k')

    phase_points = np.array([np.nan] * l * M * d)
    phase_points[::d] = output_samples[::d]
    axis.plot(phase_points, '.c')

    sample_points = np.array([np.nan] * l * M * d)
    sample_points[::d * M] = output_samples[::d * M]
    axis.plot(sample_points, '.r')

    plt.show()



if __name__ == '__main__':
    main()
