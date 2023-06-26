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
from wave_array.client.modmap import ModMap, MapException


class WaveArrayGui(QtWidgets.QMainWindow):

    def __init__(self):

        QtWidgets.QMainWindow.__init__(self)
        self.setWindowTitle('Wave Array')

        # Create client object.
        self.client = WaveArray()

        self.mod_source = None 
        self.mod_destination = None
        self.modmap = ModMap(self.client)

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
        
        for d in ModMap.MODD.keys():
            for s in list(ModMap.MODS.keys())[1:]: # Skip MODS_NONE.
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
        position = self.client.read(WaveArray.REG_FRAME_CTRL)
        self.ui.slider_frame_position.setValue(position)
        self.ui.lbl_position.setText(f'0x{position:04X}')

        velocity = self.client.read(WaveArray.REG_LFO_VELOCITY)
        self.ui.slider_lfo_velocity.setValue(velocity)
        self.ui.lbl_position.setText(f'0x{velocity:04X}')

        cutoff = self.client.read(WaveArray.REG_FILTER_CUTOFF)
        self.ui.slider_filter_cutoff.setValue(cutoff)
        self.ui.lbl_cutoff.setText(f'0x{cutoff:04X}')

        resonance = self.client.read(WaveArray.REG_FILTER_RESONANCE)
        self.ui.slider_filter_resonance.setValue(resonance)
        self.ui.lbl_resonance.setText(f'0x{resonance:04X}')

        index = self.client.read(WaveArray.REG_FILTER_SELECT)
        self.ui.box_filter_select.setCurrentIndex(index)

        attack = self.client.read(WaveArray.REG_ENVELOPE_ATTACK)
        self.ui.slider_envelope_attack.setValue(attack)
        self.ui.lbl_attack.setText(f'0x{attack:04X}')

        decay = self.client.read(WaveArray.REG_ENVELOPE_DECAY)
        self.ui.slider_envelope_decay.setValue(decay)
        self.ui.lbl_decay.setText(f'0x{decay:04X}')

        sustain = self.client.read(WaveArray.REG_ENVELOPE_SUSTAIN)
        self.ui.slider_envelope_sustain.setValue(sustain)
        self.ui.lbl_sustain.setText(f'0x{sustain:04X}')

        release = self.client.read(WaveArray.REG_ENVELOPE_RELEASE)
        self.ui.slider_envelope_release.setValue(release)  
        self.ui.lbl_release.setText(f'0x{release:04X}')

        # initialize mod matrix. 
        for d in range(len(ModMap.MODD)):
            for s in range(1, len(ModMap.MODS)):

                enable, amount = self.modmap.get_mapping(d, s)
                btn = getattr(self.ui, f'btn_mod_{d}_{s}')

                btn.setChecked(enable)


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

        self.mod_source = source 
        self.mod_destination = destination

        # Update amount slider and text.
        try:
            amount = self.modmap.read_amount(destination, source)
        except MapException as e:
            amount = 0

        self.ui.slider_mod_amount.setValue(int(amount))  
        self.ui.lbl_mod_select.setText(
            f'{ModMap.MODS[source]}\n->\n{ModMap.MODD[destination]}')       

        # Add new mod mapping.
        if state:
            self.modmap.add_mapping(destination, source, 0)

        # remove mod mapping.
        else:
            self.modmap.remove_mapping(destination, source)

    def set_mod_amount(self, control_value):
        self.modmap.write_amount(self.mod_destination, self.mod_source, control_value)
        self.ui.lbl_amount.setText(f'0x{control_value:04X}')

    def lfo_velocity_changed(self, control_value):
        self.client.write(WaveArray.REG_LFO_VELOCITY, control_value)

    def frame_position_changed(self, control_value):
        self.client.write(WaveArray.REG_FRAME_CTRL, control_value)
        self.ui.lbl_position.setText(f'0x{control_value:04X}')

    def filter_cutoff_changed(self, control_value):
        self.client.write(WaveArray.REG_FILTER_CUTOFF, control_value)
        self.ui.lbl_cutoff.setText(f'0x{control_value:04X}')
        
    def filter_resonance_changed(self, control_value):
        self.client.write(WaveArray.REG_FILTER_RESONANCE, control_value)
        self.ui.lbl_resonance.setText(f'0x{control_value:04X}')

    def filter_select_changed(self, index):
        self.client.write(WaveArray.REG_FILTER_SELECT, index)

    def envelope_attack_changed(self, control_value):
        self.client.write(WaveArray.REG_ENVELOPE_ATTACK, control_value)
        self.ui.lbl_attack.setText(f'0x{control_value:04X}')
        
    def envelope_decay_changed(self, control_value):
        self.client.write(WaveArray.REG_ENVELOPE_DECAY, control_value)
        self.ui.lbl_decay.setText(f'0x{control_value:04X}')

    def envelope_sustain_changed(self, control_value):
        self.client.write(WaveArray.REG_ENVELOPE_SUSTAIN, control_value)
        self.ui.lbl_sustain.setText(f'0x{control_value:04X}')

    def envelope_release_changed(self, control_value):
        self.client.write(WaveArray.REG_ENVELOPE_RELEASE, control_value)
        self.ui.lbl_release.setText(f'0x{control_value:04X}')
        
    
def main():
    application = QApplication(sys.argv)
    gui = WaveArrayGui()
    gui.show()
    application.exec_()


if __name__ == "__main__":
    main()
