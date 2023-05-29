#!/usr/bin/env python3

import os
import sys 

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
        self.ui.slider_filter_cutoff.sliderMoved.connect(self.filter_cutoff_changed)
        self.ui.slider_filter_resonance.sliderMoved.connect(self.filter_resonance_changed)
        self.ui.box_filter_select.currentIndexChanged.connect(self.filter_select_changed)

        # Status refresh timer.
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.load_status)
        self.timer.start(250)

    
    def load_status(self):

        faults = self.client.read(WaveArray.REG_ADDR_FAULT)
        self.ui.lbl_faults.setText(f"0x{faults:04X}")

        potentiometer = self.client.read(WaveArray.REG_POTENTIOMETER)
        self.ui.lbl_potentiometer.setText(f"0x{potentiometer:03X}")

    
    def load_config(self):

        cutoff = self.client.read_filter_cutoff(convert=True)
        self.ui.slider_filter_cutoff.setValue(int(cutoff * self.CONTROL_MAX))

        resonance = self.client.read_filter_resonance(convert=True)
        self.ui.slider_filter_resonance.setValue(int(resonance * self.CONTROL_MAX))

        select = self.client.read(WaveArray.REG_FILTER_SELECT)
        self.ui.box_filter_select.setValue(select)
        

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
        n_frames = np.uint16(np.log2(max(1, len(data) / 4096 - 1)))
        self.client.write(WaveArray.REG_TABLE_BASE_H, 0x0000)
        self.client.write(WaveArray.REG_TABLE_BASE_L, 0x0000)
        self.client.write(WaveArray.REG_TABLE_FRAMES, n_frames)
        self.client.write(WaveArray.REG_TABLE_NEW, 0x0001)


    def filter_cutoff_changed(self, control_value):

        self.client.write_filter_cutoff(control_value / self.CONTROL_MAX, convert=True)
        

    def filter_resonance_changed(self, control_value):

        self.client.write_filter_resonance(control_value / self.CONTROL_MAX, convert=True)


    def filter_select_changed(self, index):

        self.client.write(WaveArray.REG_FILTER_SELECT, np.uint16(index))

    # def envelope_attack_changed(self, control_value):
        
    # def envelope_delay_changed(self, control_value):
        
    # def envelope_sustain_changed(self, control_value):
        
    # def envelope_release_changed(self, control_value):
        
    
def main():
    application = QApplication(sys.argv)
    gui = WaveArrayGui()
    gui.show()
    application.exec_()


if __name__ == "__main__":
    main()
