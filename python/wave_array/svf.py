import numpy as np 
import matplotlib.pyplot as plt 


class StateVariableFilter:


    def __init__(self, cutoff, resonance):

        # Use 32 bit intermediate representation.
        self.cutoff = np.int32(cutoff * 2**16)
        self.resonance = np.int32(resonance * 2**16)
        self.lp_r = np.int32(0)
        self.bp_r = np.int32(0)


    # Process one filter step.
    def step(self, input_sample):

        lp = (self.cutoff * self.bp_r + self.lp_r * 2**16) >> 16
        hp = ((np.int32(input_sample * 2**16) - self.resonance * self.bp_r) >> 16) - lp
        bp = (self.cutoff * hp + self.bp_r * 2**16) >> 16
        notch = hp + lp 

        self.lp_r = lp
        self.bp_r = bp 

        return lp, hp, bp, notch

    # Generate all outputs for an array of input samples.
    def filter(self, input):

        self.lp_r = np.int32(0)
        self.bp_r = np.int32(0)

        # Cast output to 16 bit.
        lp_array = np.zeros(len(input), dtype=np.int16)
        hp_array = np.zeros(len(input), dtype=np.int16)
        bp_array = np.zeros(len(input), dtype=np.int16)
        notch_array = np.zeros(len(input), dtype=np.int16)

        for i, input_sample in enumerate(input):
            lp, hp, bp, notch = self.step(input_sample)
            lp_array[i] = lp
            hp_array[i] = hp            
            bp_array[i] = bp    
            notch_array[i] = notch   

        return lp_array, hp_array, bp_array, notch_array


def main():

    input_array = np.zeros(2048, dtype=np.int16)
    for i in range(0, 2048):
        input_array[i] = np.int16(i / 2047.0 * (2**16 - 1)) >> 2

    svf = StateVariableFilter(0.5, 2.0)

    lp_array, hp_array, bp_array, notch_array = svf.filter(input_array)

    fig = plt.figure()
    plt.plot(input_array, label='input')
    plt.plot(lp_array, label='lp')
    plt.plot(hp_array, label='hp')
    plt.plot(bp_array, label='bp')
    plt.plot(notch_array, label='notch')
    plt.legend(loc="upper right")
    plt.show()

if __name__ == '__main__':
    main()