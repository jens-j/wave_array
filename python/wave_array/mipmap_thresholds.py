
SAMPLE_RATE = 48000
TABLE_LEVELS = 10
L0_THRESHOLD = SAMPLE_RATE / 4 / 2**(TABLE_LEVELS - 1)

for level in range(10):
    threshold_f = L0_THRESHOLD * 2**level
    threshold_v = threshold_f / SAMPLE_RATE
    threshold_v_fixed = int(threshold_v * 0x80000)
    # print(threshold_f, threshold_v, f"{threshold_v_fixed:05X}")
    print(f"19x\"{threshold_v_fixed:05X}\"")
