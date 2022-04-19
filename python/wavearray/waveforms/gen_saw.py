#!/usr/bin/env python3

# Generate a saw wave table
with open('saw.data', 'w') as f:
    for i in range(0, 2048):
        sample = int(i / 2047.0 * (2**16 - 1))
        f.write(f"{sample:04X}\n")
