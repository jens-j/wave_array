import logging 
import numpy                  as np


class MapException(Exception):
    pass


class Map:
    def __init__(self, destination, source, amount):
        self.destination = destination
        self.source = source
        self.amount = amount

    def __str__(self):
        return f'{ModMap.MODS[self.source]} -> {ModMap.MODD[self.destination]}, {self.amount:04X}'


class ModMap:

    # Maximum mod sources mapped to the same destination.
    MAX_SOURCES = 4

    # Frequency control constants.
    MOD_FREQ_OCTAVES        = 3
    MOD_FREQ_STEP_OCTAVE    = 2**15 / 3
    MOD_FREQ_STEP_SEMITONE  = MOD_FREQ_STEP_OCTAVE / 12 # Since the control value is already mapped to exponential, semitones are spaced linearly.
    MOD_FREQ_STEP_CENT      = MOD_FREQ_STEP_OCTAVE / 12 / 100 # These should actually be mapped logarithmicly here to counter the exponential mapping later.  

    # Modulation source and destination indices.
    MODD_CUTOFF             = 0 
    MODD_RESONANCE          = 1 
    MODD_VOLUME             = 2
    MODD_OSC_0_FRAME        = 3
    MODD_OSC_1_FRAME        = 4
    MODD_OSC_0_MIX          = 5
    MODD_OSC_1_MIX          = 6
    MODD_NOISE_MIX          = 7
    MODD_OSC_0_FREQ         = 8
    MODD_OSC_1_FREQ         = 9
    MODD_UNISON             = 10
    MODD_LFO_0_AMPLITUDE    = 11
    MODD_LFO_1_AMPLITUDE    = 12
    MODD_LFO_2_AMPLITUDE    = 13
    MODD_LFO_3_AMPLITUDE    = 14

    MODS_NONE               = 0
    MODS_ENVELOPE_0         = 1
    MODS_ENVELOPE_1         = 2
    MODS_ENVELOPE_2         = 3
    MODS_ENVELOPE_3         = 4
    MODS_LFO_0              = 5
    MODS_LFO_1              = 6
    MODS_LFO_2              = 7
    MODS_LFO_3              = 8
    MODS_VELOCITY           = 9
    MODS_TABLE_0            = 10
    MODS_TABLE_1            = 11

    MODS_LEN                = 12
    MODD_LEN                = 15
    MODS_LEN_LOG2           = int(np.ceil(np.log2(MODS_LEN)))
    MODD_LEN_LOG2           = int(np.ceil(np.log2(MODD_LEN)))

    # Modulation destination strings.
    MODD_STRING = {
        MODD_CUTOFF             : 'filter cutoff',          
        MODD_RESONANCE          : 'filter resonance',                
        MODD_VOLUME             : 'voice mixer volume',
        MODD_OSC_0_FRAME        : 'osc 0 frame',     
        MODD_OSC_1_FRAME        : 'osc 1 frame',     
        MODD_OSC_0_MIX          : 'osc 0 mix',     
        MODD_OSC_1_MIX          : 'osc 1 mix',
        MODD_NOISE_MIX          : 'noise mix',
        MODD_OSC_0_FREQ         : 'osc 0 frequency',     
        MODD_OSC_1_FREQ         : 'osc 1 frequency',
        MODD_UNISON             : 'unison',
        MODD_LFO_0_AMPLITUDE    : 'lfo 0 amplitude',
        MODD_LFO_1_AMPLITUDE    : 'lfo 1 amplitude',
        MODD_LFO_2_AMPLITUDE    : 'lfo 2 amplitude',
        MODD_LFO_3_AMPLITUDE    : 'lfo 3 amplitude'
    }      

    # Modulation destination short strings.
    MODD_STRING_SHORT = {
        MODD_CUTOFF             : 'cutoff',          
        MODD_RESONANCE          : 'resonance',                
        MODD_VOLUME             : 'volume',
        MODD_OSC_0_FRAME        : 'frame 0',     
        MODD_OSC_1_FRAME        : 'frame 1',     
        MODD_OSC_0_MIX          : 'mix 0',     
        MODD_OSC_1_MIX          : 'mix 1',
        MODD_NOISE_MIX          : 'mix noise',
        MODD_OSC_0_FREQ         : 'frequency 0',     
        MODD_OSC_1_FREQ         : 'frequency 1',
        MODD_UNISON             : 'unison',
        MODD_LFO_0_AMPLITUDE    : 'lfo 0 depth',
        MODD_LFO_1_AMPLITUDE    : 'lfo 1 depth',
        MODD_LFO_2_AMPLITUDE    : 'lfo 2 depth',
        MODD_LFO_3_AMPLITUDE    : 'lfo 3 depth'
    }               

    # Modulation source strings.
    MODS_STRING = {
        MODS_NONE           : 'none',                
        MODS_ENVELOPE_0     : 'envelope 0',                
        MODS_ENVELOPE_1     : 'envelope 1',  
        MODS_ENVELOPE_2     : 'envelope 2',                
        MODS_ENVELOPE_3     : 'envelope 3', 
        MODS_LFO_0          : 'lfo 0',
        MODS_LFO_1          : 'lfo 1',
        MODS_LFO_2          : 'lfo 2',
        MODS_LFO_3          : 'lfo 3',
        MODS_VELOCITY       : 'velocity',
        MODS_TABLE_0        : 'oscillator 0',
        MODS_TABLE_1        : 'oscillator 1'
    }

    # Modulation source short strings.
    MODS_STRING_SHORT = {
        MODS_NONE           : 'none',                
        MODS_ENVELOPE_0     : 'env 0',                
        MODS_ENVELOPE_1     : 'env 1',  
        MODS_ENVELOPE_2     : 'env 2',                
        MODS_ENVELOPE_3     : 'env 3', 
        MODS_LFO_0          : 'lfo 0',
        MODS_LFO_1          : 'lfo 1',
        MODS_LFO_2          : 'lfo 2',
        MODS_LFO_3          : 'lfo 3',
        MODS_VELOCITY       : 'vel',
        MODS_TABLE_0        : 'osc 0',
        MODS_TABLE_1        : 'osc 1'
    }

    logger = logging.getLogger()


    def __init__(self, client):

        self.client = client
        self.map = self._load()

    def print(self):
        
        for d in range(len(ModMap.MODD.keys())):

            string = f'{d}: {str(self.map[d][0])}'

            for s in range(1, ModMap.MAX_SOURCES):

                string += f', {str(self.map[d][s])}'

    def add_mapping(self, destination, source, amount):

        i = self._find_slot(destination)

        if i != None:
            self.client.write_mod_source(destination, i, source)
            self.client.write_mod_amount(destination, i, amount)
            self.map[destination][i] = Map(destination, source, amount)
        else:
            raise MapException(f'No free slots for destination {self.MODD_STRING[destination]}')
    
    def remove_mapping(self, destination, source):

        i = self._find_source(destination, source)

        if i != None:
            self.client.write_mod_source(destination, i, 0)
            # self.client.write_mod_amount(destination, i, 0) 
            self.map[destination][i].source = 0
        else:
            raise MapException(f'Source {self.MODS_STRING[source]} not found in map for destination {self.MODD_STRING[destination]}')

    # Return tuple (enabled, amount).
    def get_mapping(self, destination, source):

        i = self._find_source(destination, source)

        if i != None:
            amount = self.client.read_mod_amount(source, i)
            return (True, amount)
        else:
            return (False, 0)

    def read_amount(self, destination, source):

        i = self._find_source(destination, source)

        if i != None:
            return self.client.read_mod_amount(destination, i)
        else:
            raise MapException(f'Source {self.MODS_STRING[source]} not found in map for destination {self.MODD_STRING[destination]}')

    def write_amount(self, destination, source, amount):

        i = self._find_source(destination, source)

        if i != None:
            return self.client.write_mod_amount(destination, i, amount)
        else:
            raise MapException(f'Source {self.MODS_STRING[source]} not found in map for destination {self.MODD_STRING[destination]}')

    # Find mapping index of source. Returns None if not found.
    def _find_source(self, destination, source):

        for i in range(self.MAX_SOURCES):
            if self.map[destination][i].source == source:
                return i 

        return None

    # Find first empty map slot index. Returns None if not available.
    def _find_slot(self, destination):

        for i in range(self.MAX_SOURCES):
            if self.map[destination][i].source == 0:
                return i 

        return None

    # Initialize by reading device state.
    def _load(self):

        map = {}
        
        for d in self.MODD_STRING.keys():
            map[d] = [None] * self.MAX_SOURCES

            for i in range(self.MAX_SOURCES):
                source = self.client.read_mod_source(d, i)
                amount = self.client.read_mod_amount(d, i)
                map[d][i] = Map(d, source, amount) 

        return map


