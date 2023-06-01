import numpy as np
import matplotlib.pyplot as plt

# Calculate velocity control value exponential mapping to [0, MAX_TIME] seconds. 

SAMPLE_RATE = 48_000
MAX_TIME = 2**2
BASE = 20 # Base for exponential function.
BRAM_SIZE_LOG2 = 10

ctrl_exp = np.zeros(2**16)
velocity = np.zeros(2**16)
length = np.zeros(2**16)

for i in range(0, 2**16):

    # Map control value range to range in [0, 1]
    ctrl_exp[i] = (BASE**((i + 1) / 2**16) - 1) / (BASE - 1)

    # Calculate corresponding velocity values.
    velocity[i] = 2**32 / (MAX_TIME * SAMPLE_RATE * ctrl_exp[i])

    # Check by calculating resulting envelope times for control range. 
    length[i] = 2**32 / (velocity[i] * SAMPLE_RATE)

velocity = np.minimum(velocity, 2**32 - 1)

# print(ctrl_exp)
# print([int(x) for x in velocity][:5])
# print(length)

with open('log.hex', 'w') as f:
    for v in velocity[::2**(16 - BRAM_SIZE_LOG2)]:
        f.write(f"{np.uint32(v):08X}\n")

fig = plt.figure()
axes = fig.subplots(3)
axes[0].plot(ctrl_exp)
axes[1].semilogy(velocity)
axes[2].plot(length - MAX_TIME * ctrl_exp)

plt.show()