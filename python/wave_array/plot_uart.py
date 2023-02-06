import numpy as np
import matplotlib.pyplot as plt


values = []

with open('putty.log', 'rb') as f:
    data = f.read()

data = [int(x) for x in data[2:]]


while len(data) > 2:
    msb = data.pop(0)
    lsb = data.pop(0)
    values.append((msb << 16) + lsb)
    if data.pop(0) != 0:
        break

fig, axis = plt.subplots(1)
axis.plot(values)
plt.show()
