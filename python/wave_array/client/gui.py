#!/usr/bin/env python3

import os
import sys 

import numpy                  as np

from PyQt5                    import QtWidgets, uic
from PyQt5.QtCore             import QSize, QSettings, Qt
from PyQt5.QtWidgets          import QLabel, QApplication
from PyQt5.QtGui              import QIntValidator

from wave_array.client.client import WaveArray


class WaveArrayGui(QtWidgets.QMainWindow):

    # Resolution of the control slider and spinboxes.
    CONTROL_MAX = 1000;

    def __init__(self):

        QtWidgets.QMainWindow.__init__(self)

        # Create client object.
        self.client = WaveArray()

        # Initialize the GUI.
        module_path = os.path.dirname(os.path.abspath(__file__))
        ui_path     = os.path.join(module_path, '../../../qt')
        self.ui     = uic.loadUi(os.path.join(ui_path, 'wavearray.ui'))

        # Connect signals.
        self.ui.slider_filter_cutoff.sliderMoved.connect(self.filter_cutoff_changed)
        self.ui.box_filter_cutoff.valueChanged.connect(self.filter_cutoff_changed)
        self.ui.slider_filter_resonance.sliderMoved.connect(self.filter_resonance_changed)
        self.ui.box_filter_resonance.valueChanged.connect(self.filter_resonance_changed)

        # Load initial values.
        cutoff = self.client.read_filter_cutoff(convert=True)
        self.filter_cutoff_changed(int(cutoff * self.CONTROL_MAX))
        resonance = self.client.read_filter_resonance(convert=True)
        self.filter_resonance_changed(int(resonance * self.CONTROL_MAX))
        

    def show(self):
        """ Re-implemented from QMainWindow. """
        self.ui.show()


    def filter_cutoff_changed(self, control_value):
        self.ui.slider_filter_cutoff.setValue(control_value)
        self.ui.box_filter_cutoff.valueChanged.disconnect()
        self.ui.box_filter_cutoff.setValue(control_value)
        self.ui.box_filter_cutoff.valueChanged.connect(self.filter_cutoff_changed)

        self.client.write_filter_cutoff(control_value / self.CONTROL_MAX, convert=True)
        

    def filter_resonance_changed(self, control_value):
        self.ui.slider_filter_resonance.setValue(control_value)
        self.ui.box_filter_resonance.valueChanged.disconnect()
        self.ui.box_filter_resonance.setValue(control_value)
        self.ui.box_filter_resonance.valueChanged.connect(self.filter_resonance_changed)

        self.client.write_filter_resonance(control_value / self.CONTROL_MAX, convert=True)

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
