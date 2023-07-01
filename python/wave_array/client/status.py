import numpy as np


class Status:

    # Packet: data part only as array of np.int16.
    def __init__(self, client, packet):

        self.client = client

        self.voice_enabled = [bool(packet[0] & (0x0001 << i)) for i in range(0, self.client.n_voices)]
        self.voice_active = [bool(packet[1] & (0x0001 << i)) for i in range(0, self.client.n_voices)]
        self.pot_value = np.uint16(packet[2])
        self.mod_sources = {}
        self.mod_destinations = {}


        for source in range(self.client.MODS_LEN):

            self.mod_sources[source] = []

            offset = (3 + source * self.client.n_voices) * 2

            for voice in range(self.client.n_voices):

                self.mod_sources[source].append(int.from_bytes(packet[offset + voice * 2:offset + voice * 2 + 2], "big"))

        
        for destination in range(self.client.MODD_LEN):

            self.mod_destinations[destination] = []

            offset = (3 + self.client.MODS_LEN * self.client.n_voices + destination * self.client.n_voices * 2)

            for voice in range(self.client.n_voices):

                self.mod_destinations[destination].append(
                    int.from_bytes(packet[offset + voice * 2:offset + voice * 2 + 2], "big"))


        # print(self.mod_sources)
        # print(self.mod_destinations)
        