import numpy as np
import matplotlib.pyplot as plt

exp = np.zeros(1024)
values = np.zeros(1024, dtype=np.int16)

with open('exp.hex', 'w') as f:

    for i in range(1024):

        exp[i] = (i - 512) / 512 # [-1, 1)
        values[i] = int(2**14 * 2**exp[i])

        f.write(f'{values[i]:04X}\n')


fig = plt.figure()
axis = fig.subplots(1)
axis.plot(values)
plt.show()