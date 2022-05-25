#!/usr/bin/env python3

from math import sin, pi

# Generate a sine wave table
with open('sine.data', 'w') as f:
    for i in range(0, 2048):
        sample = int(sin(i * 2 * pi / 2048) * (2**15 - 1))
        print(f"{sample & 0xFFFF:04X}")
        f.write(f"{sample & 0xFFFF:04X}\n")
