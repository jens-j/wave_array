#!/usr/bin/env python3

# Frequencies of octave 4
NOTES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
FREQUENCIES = [261.63, 277.18, 293.66, 311.13, 329.63, 349.23,
               369.99, 392.00 , 415.30, 440.00, 466.16, 493.88]

# Generate the base step sizes used in oscillator.vhd
for n, f in zip(NOTES, FREQUENCIES):
    # 16.11 fixed point wave table step size for octave 9
    # step = int(2**11 * f * 2**5)
    # print(f"27x\"{step:07X}\", -- {n}");

    print(f"{f * 2**5:.2f}, -- {n}")
