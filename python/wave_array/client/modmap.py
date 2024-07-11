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
    MODD_LEN                = 11
    MODS_LEN_LOG2           = int(np.ceil(np.log2(MODS_LEN)))
    MODD_LEN_LOG2           = int(np.ceil(np.log2(MODD_LEN)))

    # Modulation destination strings.
    MODD = {
        MODD_CUTOFF         : 'filter_cutoff',          
        MODD_RESONANCE      : 'filter_resonance',                
        MODD_VOLUME         : 'voice_mixer_volume',
        MODD_OSC_0_FRAME    : 'osc_0_frame',     
        MODD_OSC_1_FRAME    : 'osc_1_frame',     
        MODD_OSC_0_MIX      : 'osc_0_mix',     
        MODD_OSC_1_MIX      : 'osc_1_mix',
        MODD_NOISE_MIX      : 'noise_mix',
        MODD_OSC_0_FREQ     : 'osc_0_freq',     
        MODD_OSC_1_FREQ     : 'osc_1_freq',
        MODD_UNISON         : 'unison'
    }                  

    # Modulation source strings.
    MODS = {
        MODS_NONE           : 'none',                
        MODS_ENVELOPE_0     : 'envelope_0',                
        MODS_ENVELOPE_1     : 'envelope_1',  
        MODS_ENVELOPE_2     : 'envelope_2',                
        MODS_ENVELOPE_3     : 'envelope_3', 
        MODS_LFO_0          : 'lfo_0',
        MODS_LFO_1          : 'lfo_1',
        MODS_LFO_2          : 'lfo_2',
        MODS_LFO_3          : 'lfo_3',
        MODS_VELOCITY       : 'velocity',
        MODS_TABLE_0        : 'table_0',
        MODS_TABLE_1        : 'table_1'
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
            raise MapException(f'No free slots for destination {self.MODD[destination]}')
    
    def remove_mapping(self, destination, source):

        i = self._find_source(destination, source)

        if i != None:
            self.client.write_mod_source(destination, i, 0)
            # self.client.write_mod_amount(destination, i, 0) 
            self.map[destination][i].source = 0
        else:
            raise MapException(f'Source {self.MODS[source]} not found in map for destination {self.MODD[destination]}')

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
            raise MapException(f'Source {self.MODS[source]} not found in map for destination {self.MODD[destination]}')

    def write_amount(self, destination, source, amount):

        i = self._find_source(destination, source)

        if i != None:
            return self.client.write_mod_amount(destination, i, amount)
        else:
            raise MapException(f'Source {self.MODS[source]} not found in map for destination {self.MODD[destination]}')

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
        
        for d in self.MODD.keys():
            map[d] = [None] * self.MAX_SOURCES

            for i in range(self.MAX_SOURCES):
                source = self.client.read_mod_source(d, i)
                amount = self.client.read_mod_amount(d, i)
                map[d][i] = Map(d, source, amount) 

        return map


