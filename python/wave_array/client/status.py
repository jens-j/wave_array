import numpy as np
import struct
from wave_array.client.uart import UartType 
from wave_array.client.modmap import ModMap

class Status:
    

    # Packet: entire packet as array of np.int16.
    def __init__(self, client, packet=None):

        self.PACKET_BYTES = (2 + 4 + (ModMap.MODS_LEN + ModMap.MODD_LEN) * client.n_voices) * 2

        self.client = client

        if packet == None:

            self.voice_enabled = [False] * self.client.n_voices
            self.voice_active = [False] * self.client.n_voices
            self.polyphony = 0
            self.active_oscillators = 0
            self.mod_sources = 0
            self.mod_destinations = 0

            self.packet = b'\x00' * self.PACKET_BYTES

        else:        

            # Check packet length.
            assert len(packet) == self.PACKET_BYTES, \
                f'Incorrect status packet length {len(packet)} instead of {self.PACKET_BYTES}'

            # Check if opcode and channel are correct.
            assert struct.unpack('<B', packet[0:1])[0] == UartType.AUTO_OFFLOAD and struct.unpack('<B', packet[1:2])[0] == 0, \
                f'Incorrect header for status packet {packet[0]:04X}'  

            self.packet = packet
            # self.print_packet()

        # Skip header.
        data = self.packet[4:]

        self.voice_enabled      = struct.unpack('<h', data[0:2])[0]
        self.voice_active       = struct.unpack('<h', data[2:4])[0]
        self.polyphony          = struct.unpack('<h', data[4:6])[0]
        self.active_oscillators = struct.unpack('<h', data[6:8])[0]

        self.mod_sources        = {}
        self.mod_destinations   = {}

        offset = 8

        for source in range(ModMap.MODS_LEN):

            self.mod_sources[source] = []

            for voice in range(self.client.n_voices):

                self.mod_sources[source].append(struct.unpack('<h', data[offset:offset + 2])[0])
                offset += 2
        
        for destination in range(ModMap.MODD_LEN):

            self.mod_destinations[destination] = []

            for voice in range(self.client.n_voices):

                self.mod_destinations[destination].append(struct.unpack('<h', data[offset:offset + 2])[0])
                offset += 2


    def print_packet(self):

        print(f'Packet ({len(self.packet)}):')
        print(self.packet)
        print(f'opcode          = {self.packet[0]}')
        print(f'channel         = {self.packet[1]}')
        print(f'length          = {struct.unpack(">h", self.packet[2:4])[0]}')
        print(f'voice enabled   = 0x{struct.unpack(">h", self.packet[4:6])[0]:04X}')
        print(f'voice active    = 0x{struct.unpack(">h", self.packet[6:8])[0]:04X}')

        offset = 8

        for source in range(self.ModMap.MODS_LEN):

            s = f'Mod Source {source}: ['

            for voice in range(self.client.n_voices):

                value = struct.unpack("<h", self.packet[offset:offset + 2])[0]
                if voice > 0:
                    s += ', '
                s += f'{value}'
                offset += 2

            print(s + ']')

        
        for destination in range(self.ModMap.MODD_LEN):

            s = f'Mod Destination {destination}: ['

            for voice in range(self.client.n_voices):

                value = struct.unpack("<h", self.packet[offset:offset + 2])[0]
                if voice > 0:
                    s += ', '
                s += f'{value}'
                offset += 2

            print(s + ']')



        
        