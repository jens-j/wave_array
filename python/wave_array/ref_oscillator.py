import time

import numpy as np
import matplotlib.pyplot as plt

from wave_array.mipmap.mipmap import Mipmap
from wave_array.mipmap import waveforms
from wave_array.oscillator.polyphase import PolyphaseFilter
from wave_array.oscillator.halfband import Halfband



def get_coeffs(pp_filter, m0, d):

    m1 = (m0 + 1) % POLY_M
    c0 = pp_filter.filterbank[m0]
    c1 = np.append(pp_filter.filterbank[m1][1:], 0) if m1 == 0 else pp_filter.filterbank[m1] # Edge case where m1 overflows
    c0 = (c0 * (1 << (POLY_COEFF_SIZE - 1))).astype(int) # Convert to scaled fixedpoint
    c1 = (c1 * (1 << (POLY_COEFF_SIZE - 1))).astype(int)
    c = (((1 << OSC_COEFF_FRAC) - d) * c0 + d * c1) >> OSC_COEFF_FRAC

    return c


MIPMAP_THRESHOLDS = [0x10000, 0x20000, 0x40000, 0x80000, 0x100000, 0x200000, 0x400000, 0x800000, 0x1000000]

SAMPLE_RATE             = 48000
FREQUENCY               = 156
OUTPUT_LENGTH           = 0.1 # s
SAMPLE_SIZE             = 16
TABLE_SIZE_L0_LOG2      = 11
TABLE_SIZE_L0           = 1 << TABLE_SIZE_L0_LOG2
POLY_COEFF_SIZE         = 16
POLY_M_LOG2             = 7
POLY_M                  = 1 << POLY_M_LOG2
POLY_N_LOG2             = 4
POLY_N                  = 1 << POLY_N_LOG2
OSC_SAMPLE_FRAC         = 8 # Bits useed for frame interpolation.
OSC_COEFF_FRAC          = 8 # Bits used for coefficient interpolation.
PHASE_SIZE              = TABLE_SIZE_L0_LOG2 + POLY_M_LOG2 + OSC_COEFF_FRAC

phase = 0
velocity = (1 << PHASE_SIZE) * FREQUENCY // (2 * SAMPLE_RATE)
level = 9

# Calculate mipmap level
for i in range(9):
    if velocity > MIPMAP_THRESHOLDS[i]:
        level = i + 1

waveform = waveforms.saw()
mm_table = Mipmap('saw', waveform, prefilter=True)
level_table = mm_table.subtables[level]
pp_filter = PolyphaseFilter(POLY_N, POLY_M, 0.3)
output_samples = np.zeros(int(OUTPUT_LENGTH * 2 * SAMPLE_RATE), dtype=int)
test_samples = np.zeros((TABLE_SIZE_L0 >> level) * POLY_M * (1 << OSC_COEFF_FRAC), dtype=int)

print(hex(velocity), hex(velocity >> (POLY_M_LOG2 + OSC_COEFF_FRAC)))
print(level)
print(level_table)

# # Generate every interpolation point for FREQUENCY.
# for i in range((TABLE_SIZE_L0 >> level) * POLY_M * (1 << OSC_COEFF_FRAC)):
#
#     # Create input sample array.
#     x = np.zeros(POLY_N, dtype=int)
#     base_address = i // (POLY_M * (1 << OSC_COEFF_FRAC))
#     for j in range(POLY_N):
#         x[j] = level_table[(base_address + j) % (TABLE_SIZE_L0 >> level)]
#
#     m0 = i // (1 << OSC_COEFF_FRAC) % POLY_M
#     d = i % (1 << OSC_COEFF_FRAC)
#     c = get_coeffs(pp_filter, m0, d)
#
#     test_samples[i] = int(sum(x * c[::-1]) >> (POLY_COEFF_SIZE - 1))


# Generate OUTPUT_LENGTH seconds of output data.
for i in range(int(OUTPUT_LENGTH * 2 * SAMPLE_RATE)):

    # Create input sample array.
    x = np.zeros(POLY_N, dtype=int)
    base_address = phase >> (POLY_M_LOG2 + OSC_COEFF_FRAC + level)
    for j in range(POLY_N):
        x[j] = level_table[(base_address + j) % (TABLE_SIZE_L0 >> level)]

    # Create coefficient array.
    m0 = (phase >> (OSC_COEFF_FRAC + level)) % POLY_M
    d = (phase >> level) % (1 << OSC_COEFF_FRAC)
    c = get_coeffs(pp_filter, m0, d)

    # Calculate output sample.
    output_samples[i] = int(sum(x * c[::-1]) >> (POLY_COEFF_SIZE - 1))

    # Increment and overflow phase.
    phase += velocity
    if phase >= (1 << PHASE_SIZE):
        phase -= (1 << PHASE_SIZE)

    # print(i, base_address, m0, d, output_samples[i])

phase_points = np.array([np.nan] * (TABLE_SIZE_L0 >> level) * POLY_M * (1 << OSC_COEFF_FRAC))
sample_points = np.array([np.nan] * (TABLE_SIZE_L0 >> level) * POLY_M * (1 << OSC_COEFF_FRAC))

phase_points[::(1 << OSC_COEFF_FRAC)] = test_samples[::(1 << OSC_COEFF_FRAC)]
sample_points[::POLY_M * (1 << OSC_COEFF_FRAC)] = test_samples[::POLY_M * (1 << OSC_COEFF_FRAC)]

fig, axes = plt.subplots(3)
axes[0].plot(level_table)
axes[1].plot(test_samples)
axes[1].plot(phase_points, 'y.')
axes[1].plot(sample_points, 'r.')
axes[2].plot(output_samples)
plt.show()
