#!/usr/bin/env python3

import os
import sys 
from functools                import partial

import numpy                  as np

from PyQt5                    import QtWidgets, uic
from PyQt5.QtCore             import QSize, QSettings, Qt, QTimer
from PyQt5.QtWidgets          import QLabel, QApplication, QFileDialog
from PyQt5.QtGui              import QIntValidator

from wave_array.client.client import WaveArray


class WaveArrayGui(QtWidgets.QMainWindow):

    # Resolution of the control slider and spinboxes.
    CONTROL_MAX = 10000;

    def __init__(self):

        QtWidgets.QMainWindow.__init__(self)
        self.setWindowTitle('Wave Array')

        # Create client object.
        self.client = WaveArray()

        self.mod_source = None 
        self.mod_destination = None
        self.mod_index = None
        self.mod_mapping = {}

        for dest in self.client.MODD:
            self.mod_mapping[dest] = []

        # Initialize the GUI.
        module_path = os.path.dirname(os.path.abspath(__file__))
        ui_path     = os.path.join(module_path, '../../../qt')
        self.ui     = uic.loadUi(os.path.join(ui_path, 'wavearray.ui'))

        # Load initial values.
        self.load_status()
        self.load_config()

        # Connect signals.
        self.ui.action_open_wavetable.triggered.connect(self.open_wavetable)
        self.ui.action_load_config.triggered.connect(self.load_config)
        self.ui.slider_frame_position.sliderMoved.connect(self.frame_position_changed)
        self.ui.slider_lfo_velocity.sliderMoved.connect(self.lfo_velocity_changed)
        self.ui.slider_filter_cutoff.sliderMoved.connect(self.filter_cutoff_changed)
        self.ui.slider_filter_resonance.sliderMoved.connect(self.filter_resonance_changed)
        self.ui.box_filter_select.currentIndexChanged.connect(self.filter_select_changed)
        self.ui.slider_envelope_attack.sliderMoved.connect(self.envelope_attack_changed)
        self.ui.slider_envelope_decay.sliderMoved.connect(self.envelope_decay_changed)
        self.ui.slider_envelope_sustain.sliderMoved.connect(self.envelope_sustain_changed)
        self.ui.slider_envelope_release.sliderMoved.connect(self.envelope_release_changed)
        self.ui.slider_mod_amount.sliderMoved.connect(self.set_mod_amount)
        
        for d in self.client.MODD.keys():
            for s in list(self.client.MODS.keys())[1:]: # Skip MODS_NONE.
                button = getattr(self.ui, f'btn_mod_{d}_{s}')
                button.stateChanged.connect(partial(self.mod_button_clicked, d, s))
        

        # Status refresh timer.
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.load_status)
        self.timer.start(250)

    
    def load_status(self):

        faults = self.client.read(WaveArray.REG_ADDR_FAULT, log=False)
        self.ui.lbl_faults.setText(f"0x{faults:04X}")

        potentiometer = self.client.read(WaveArray.REG_POTENTIOMETER, log=False)
        self.ui.lbl_potentiometer.setText(f"0x{potentiometer:03X}")


    # Read device settings and update GUI elements accordingly.
    def load_config(self):

        # Initialize sliders.
        position = self.client.read(WaveArray.REG_FRAME_CTRL, convert=True)
        self.ui.slider_frame_position.setValue(int(position * self.CONTROL_MAX))

        velocity = self.client.read(WaveArray.REG_FRAME_CTRL, convert=True)
        self.ui.slider_lfo_velocity.setValue(int(velocity * self.CONTROL_MAX))

        cutoff = self.client.read(WaveArray.REG_FILTER_CUTOFF, convert=True)
        self.ui.slider_filter_cutoff.setValue(int(cutoff * self.CONTROL_MAX))

        resonance = self.client.read(WaveArray.REG_FILTER_RESONANCE, convert=True)
        self.ui.slider_filter_resonance.setValue(int(resonance * self.CONTROL_MAX))

        index = self.client.read(WaveArray.REG_FILTER_SELECT)
        self.ui.box_filter_select.setCurrentIndex(index)

        attack = self.client.read(WaveArray.REG_ENVELOPE_ATTACK, convert=True)
        self.ui.slider_envelope_attack.setValue(int(attack * self.CONTROL_MAX))

        decay = self.client.read(WaveArray.REG_ENVELOPE_DECAY, convert=True)
        self.ui.slider_envelope_decay.setValue(int(decay * self.CONTROL_MAX))

        sustain = self.client.read(WaveArray.REG_ENVELOPE_SUSTAIN, convert=True)
        self.ui.slider_envelope_sustain.setValue(int(sustain * self.CONTROL_MAX))

        release = self.client.read(WaveArray.REG_ENVELOPE_RELEASE, convert=True)
        self.ui.slider_envelope_release.setValue(int(release * self.CONTROL_MAX))  

        # Initialize mod matrix. 
        for d in self.client.MODD.keys():
            for i in range(4):

                source = self.client.read_mod_enable(d, i)

                if source > 0:
                    button = getattr(self.ui, f'btn_mod_{d}_{source}')
                    button.setChecked(True)

                    self.mod_mapping[d].append(source)


    def show(self):
        """ Re-implemented from QMainWindow. """
        self.ui.show()

    
    def open_wavetable(self):

        default_path = os.path.dirname(os.path.abspath(__file__))
        default_path = os.path.join(default_path, '../../../data')

        dlg = QFileDialog()
        dlg.setDirectory(default_path)
        dlg.setFileMode(QFileDialog.AnyFile)
        # dlg.selectNameFilter("Wavetable files (*.table)")
		
        if dlg.exec_():
            filenames = dlg.selectedFiles()
            print(filenames)

        with open(filenames[0], 'r') as f:
            raw_data = f.read().split('\n')

        raw_data = list(filter(lambda x: x != '', raw_data))
        data = np.array([int(x, 16) for x in raw_data]).astype('int16')

        # Write table to sdram.
        self.client.write_sdram(0, data)

        # Update table registers.
        n_frames = np.uint16(np.log2(len(data) / 4096))
        self.client.write(WaveArray.REG_TABLE_BASE_H, 0x0000)
        self.client.write(WaveArray.REG_TABLE_BASE_L, 0x0000)
        self.client.write(WaveArray.REG_TABLE_FRAMES, n_frames)
        self.client.write(WaveArray.REG_TABLE_NEW, 0x0001)

        print(len(data))
        print(np.log2(len(data)) / 4096)


    def mod_button_clicked(self, destination, source, state):

        # Add new mod mapping.
        if state:
            assert source not in self.mod_mapping[destination]

            index = len(self.mod_mapping[destination])
            
            if index < 4:
                self.client.mod_enable(destination, index, source)
                self.mod_mapping[destination].append(source)

        # remove mod mapping.
        else:
            assert source in self.mod_mapping[destination]

            index = self.mod_mapping[destination].index(source)

            self.client.mod_disable(destination, index)
            self.mod_mapping[destination].pop(index)

        # Update amount slider and text.
        amount = self.client.read_mod_amount(destination, index)
        self.ui.slider_mod_amount.setValue(int(amount * self.CONTROL_MAX))  
        self.ui.lbl_mod_select.setText(
            f'{self.client.MODS[source]}\n->\n{self.client.MODD[destination]}')        

        self.mod_source = source 
        self.mod_destination = destination
        self.mod_index = index


    def set_mod_amount(self, control_value):

        index = self.mod_mapping[self.mod_destination].index(self.mod_source)

        self.client.write_mod_amount(self.mod_destination, index, control_value / self.CONTROL_MAX)


    def lfo_velocity_changed(self, control_value):
        self.client.write(WaveArray.REG_LFO_VELOCITY, control_value / self.CONTROL_MAX, convert=True)

    def frame_position_changed(self, control_value):
        self.client.write(WaveArray.REG_FRAME_CTRL, control_value / self.CONTROL_MAX, convert=True)

    def filter_cutoff_changed(self, control_value):
        self.client.write(WaveArray.REG_FILTER_CUTOFF, control_value / self.CONTROL_MAX, convert=True)
        
    def filter_resonance_changed(self, control_value):
        self.client.write(WaveArray.REG_FILTER_RESONANCE, control_value / self.CONTROL_MAX, convert=True)

    def filter_select_changed(self, index):
        self.client.write(WaveArray.REG_FILTER_SELECT, index)

    def envelope_attack_changed(self, control_value):
        self.client.write(WaveArray.REG_ENVELOPE_ATTACK, control_value / self.CONTROL_MAX, convert=True)
        
    def envelope_decay_changed(self, control_value):
        self.client.write(WaveArray.REG_ENVELOPE_DECAY, control_value / self.CONTROL_MAX, convert=True)

    def envelope_sustain_changed(self, control_value):
        self.client.write(WaveArray.REG_ENVELOPE_SUSTAIN, control_value / self.CONTROL_MAX, convert=True)

    def envelope_release_changed(self, control_value):
        self.client.write(WaveArray.REG_ENVELOPE_RELEASE, control_value / self.CONTROL_MAX, convert=True)
        
    
def main():
    application = QApplication(sys.argv)
    gui = WaveArrayGui()
    gui.show()
    application.exec_()


if __name__ == "__main__":
    main()
