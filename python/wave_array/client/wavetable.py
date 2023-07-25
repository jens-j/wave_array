import numpy as np

class WaveTable:

    def __init__(self):
        
        self.n_frames = 0
        self.n_frames_log2 = 0
        self.frames = []


    def initialize(self, data):

        assert len(data) % 4096 == 0, f'Invalid wavetable length {len(data)}'

        self.frames = []
        self.n_frames = len(data) // 4096
        self.n_frames_log2 = int(np.log2(self.n_frames))

        for i in range(self.n_frames):
            self.frames.append(data[i * 4096:i * 4096 + 2048])

