

class MapException(Exception):
    pass


class Map:
    def __init__(self, destination, source, amount):
        self.destination = destination
        self.source = source
        self.amount = amount

    def __str__(self):
        return f'{self.source} -> {self.destination}, {self.amount:.6f}'


class ModMap:

    MAX_SOURCES = 4

    # Modulation destinations.
    MODD = {
        0: 'FILTER_CUTOFF',          
        1: 'FILTER_RESONANCE',       
        2: 'OSC_FRAME',              
        3: 'VOLUME'
    }                  

    # Modulation sources.
    MODS = {
        0: 'NONE',                   
        1: 'POT',                    
        2: 'ENVELOPE',                
        3: 'LFO'                    
    }


    def __init__(self, client):

        self.client = client
        self.map = self._load()

    def print(self):

        print(len(ModMap.MODD.keys()))
        
        for d in range(len(ModMap.MODD.keys())):

            string = f'{d}: {str(self.map[d][0])}'

            # print(string)

            for s in range(1, ModMap.MAX_SOURCES):

                string += f', {str(self.map[d][s])}'

            print(string)

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

        self.print()
        print(destination)


        for i in range(self.MAX_SOURCES):

            print(self.map[destination][i].source)

            if self.map[destination][i].source == 0:
                return i 

        return None

    # Initialize by reading device state.
    def _load(self):

        map = {}
        
        for d in self.MODS.keys():

            map[d] = [None] * self.MAX_SOURCES

            for i in range(self.MAX_SOURCES):

                source = self.client.read_mod_source(d, i)
                amount = self.client.read_mod_amount(d, i)
                map[d][i] = Map(d, source, amount) 

        return map


