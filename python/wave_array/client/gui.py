#!/usr/bin/env python3

import os
import sys 
import logging
from functools                import partial
from random                   import randint
from datetime                 import datetime

import pyqtgraph as pg
import numpy                  as np
from PyQt5                    import QtWidgets, uic
from PyQt5.QtCore             import QSize, QSettings, Qt, QTimer
from PyQt5.QtWidgets          import QLabel, QApplication, QFileDialog
from PyQt5.QtGui              import QIntValidator

from wave_array.client.client import WaveArray
from wave_array.client.modmap import ModMap, MapException
from wave_array.client.status import Status

class WaveArrayGui(QtWidgets.QMainWindow):

    PLOT_FREQUENCY = 50
    PLOT_PERIOD_MS = 1000 // PLOT_FREQUENCY

    PLOT_T       = 8 # Seconds.
    PLOT_SAMPLES = PLOT_T * PLOT_FREQUENCY

    logger = logging.getLogger()

    def __init__(self):

        QtWidgets.QMainWindow.__init__(self)
        self.setWindowTitle('Wave Array')

        self.auto_offload_enable = False

        # Create client object.
        self.client = WaveArray(self.auto_offload_handler)

        self.mod_source = None 
        self.mod_destination = None
        self.modmap = ModMap(self.client)
        self.frames = [None] * 16 
        self.modd_mixer = np.zeros(self.client.n_voices, dtype='int16')
        self.modd_frame = np.zeros(self.client.n_voices, dtype='int16')
        self.mixer_x = np.arange(0, self.PLOT_T, self.PLOT_T / self.PLOT_SAMPLES)[::-1] # Constant used for plotting.

        self.t_hk = datetime.now()
        self.t_plot = datetime.now()

        # PlotDataItems used to update the plots.
        self.waveforms = [None] * self.client.n_voices 
        self.mixer_control = [None] * self.client.n_voices

        # Initialize the GUI.
        module_path = os.path.dirname(os.path.abspath(__file__))
        ui_path     = os.path.join(module_path, '../../../qt')
        self.ui     = uic.loadUi(os.path.join(ui_path, 'wavearray.ui'))
        self.initialize_plots()

        table_path = os.path.join(module_path, '../../../data') 
        self.open_wavetable(filename=os.path.join(table_path, 'saw_square.table'))

        # Load initial values.
        self.load_status()
        self.load_config()

        # Connect signals.
        self.ui.btn_enable_hk.clicked.connect(self.btn_enable_hk_clicked)
        self.ui.box_hk_rate.valueChanged.connect(self.box_hk_rate_changed)
        self.ui.btn_reg_read.released.connect(self.btn_reg_read_clicked)
        self.ui.btn_reg_write.released.connect(self.btn_reg_write_clicked)
        self.ui.action_open_wavetable.triggered.connect(self.open_wavetable)
        self.ui.action_load_config.triggered.connect(self.load_config)
        self.ui.box_filter_select.currentIndexChanged.connect(self.filter_select_changed)
        self.ui.box_lfo_waveform.currentIndexChanged.connect(self.lfo_waveform_changed)
        self.ui.slider_frame_position.sliderMoved.connect(self.frame_position_changed)
        self.ui.slider_lfo_velocity.sliderMoved.connect(self.lfo_velocity_changed)
        self.ui.slider_filter_cutoff.sliderMoved.connect(self.filter_cutoff_changed)
        self.ui.slider_filter_resonance.sliderMoved.connect(self.filter_resonance_changed)
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
        # self.timer.timeout.connect(self.load_status)
        self.timer.timeout.connect(self.update_plots)
        self.timer.start(self.PLOT_PERIOD_MS)

        # Start auto offload handling.
        self.auto_offload_enable = True


    def auto_offload_handler(self, packet):

        if self.auto_offload_enable:

            status = Status(self.client, packet)

            self.ui.lbl_potentiometer.setText(f"0x{status.pot_value:03X}")

            self.modd_mixer = status.mod_destinations[WaveArray.MODD_MIXER]
            self.modd_frame = status.mod_destinations[WaveArray.MODD_OSC_FRAME]

    
    def load_status(self):

        t = datetime.now()

        faults = self.client.read(WaveArray.REG_FAULT, log=False)
        self.ui.lbl_faults.setText(f"0x{faults:04X}")

        print(f'T hk = {(datetime.now() - t).total_seconds()}')

        potentiometer = self.client.read(WaveArray.REG_POTENTIOMETER, log=False)
        self.ui.lbl_potentiometer.setText(f"0x{potentiometer:03X}")

        self.frames_log2 = self.client.read(WaveArray.REG_TABLE_FRAMES, log=False)
        self.ui.lbl_frames.setText(f"{2**self.frames_log2:d}") 

        for i in range(self.client.n_voices):

            self.modd_mixer[i] = np.int16(self.client.read(WaveArray.REG_MOD_DEST_BASE 
                + WaveArray.MODD_MIXER * 2**self.client.n_voices_log2 + i, log=False))

            self.modd_frame[i] = np.int16(self.client.read(WaveArray.REG_MOD_DEST_BASE 
                + WaveArray.MODD_OSC_FRAME * 2**self.client.n_voices_log2 + i, log=False))


    def update_plots(self):

        # t = datetime.now()
        
        for i in range(self.client.n_voices):

            # Set mixer plot data.
            data = self.mixer_control[i].getData()[1]
            data[-1] = self.modd_mixer[i]
            data = np.roll(data, 1)

            # data = np.concatenate((data[1:], [self.modd_mixer[i]]))

            self.mixer_control[i].setData(self.mixer_x, data)

            # Set waveform plot data.
            if self.frames_log2 == 0:
                self.waveforms[i].setData(self.frames[0])

            # Interpolate between frames 0 and 1.
            elif self.frames_log2 == 1: 
                self.waveforms[i].setData(self.frames[0] 
                    + np.int16(self.modd_frame[i] * np.int32(self.frames[1] - self.frames[0]) // 2**15))

            # interpolate between frames a and b.
            else:
                index_a = 2**self.frames_log2 * self.modd_frame[i] // 2**15 
                index_b = min(index_a + 1, 2**self.frames_log2 - 1)
                d = self.modd_frame[i] % 2**(15 - self.frames_log2)
                d_max = 2**(15 - self.frames_log2) - 1
                
                self.waveforms[i].setData(self.frames[index_a] 
                    + np.int16(d * np.int32(self.frames[index_b] - self.frames[index_a]) // d_max))

        # print(f'T plot = {(datetime.now() - t).total_seconds()}')
       


    # Read device settings and update GUI elements accordingly.
    def load_config(self):


        # Initialize configuration.
        enabled = self.client.read(WaveArray.REG_HK_ENABLE)
        self.ui.btn_enable_hk.setChecked(enabled)

        period = self.client.read(WaveArray.REG_HK_PERIOD)
        rate = 100E6 / (period * 1024)
        self.ui.box_hk_rate.setValue(int(rate))
    
        index = self.client.read(WaveArray.REG_FILTER_SELECT)
        self.ui.box_filter_select.setCurrentIndex(index)

        index = self.client.read(WaveArray.REG_LFO_WAVE)
        self.ui.box_lfo_waveform.setCurrentIndex(index)

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


    def initialize_plots(self):
        
        self.ui.plot_mixer.setBackground('w')
        self.ui.plot_mixer.setTitle('mixer control values')
        self.ui.plot_waveform.setBackground('w')
        self.ui.plot_waveform.setTitle('waveform')

        # Plot curves and store PlotDataItem.        
        for i in range(self.client.n_voices):
            pen = pg.mkPen(color=(randint(0, 255), randint(0, 255), randint(0, 255)))

            self.mixer_control[i] = self.ui.plot_mixer.plot(
                self.mixer_x, np.zeros(self.PLOT_SAMPLES), name=f'voice {i}', pen=pen)

            self.waveforms[i] = self.ui.plot_waveform.plot(
                np.zeros(1024), name=f'voice {i}', pen=pen)

        self.ui.plot_mixer.addLegend()
        self.ui.plot_waveform.addLegend()
        self.ui.plot_mixer.setYRange(0, 32767, padding=0)
        self.ui.plot_waveform.setYRange(-32768, 32767, padding=0)


    def show(self):
        """ Re-implemented from QMainWindow. """
        self.ui.show()

    
    def open_wavetable(self, filename=None):

        # This does not work well toghether.
        self.auto_offload_enable = False

        if filename == None:
            dlg = QFileDialog()
            dlg.setDirectory(default_path)
            dlg.setFileMode(QFileDialog.AnyFile)
            # dlg.selectNameFilter("Wavetable files (*.table)")
            
            if dlg.exec_():
                filename = dlg.selectedFiles()[0]

        with open(filename, 'r') as f:
            raw_data = f.read().split('\n')

        raw_data = list(filter(lambda x: x != '', raw_data))
        data = np.array([int(x, 16) for x in raw_data]).astype('int16')

        # Write table to sdram.
        self.client.write_sdram(0, data)

        # Update table registers.
        n_frames_log2 = np.uint16(np.log2(len(data) / 4096))
        self.client.write(WaveArray.REG_TABLE_BASE_H, 0x0000)
        self.client.write(WaveArray.REG_TABLE_BASE_L, 0x0000)
        self.client.write(WaveArray.REG_TABLE_FRAMES, n_frames_log2)
        self.client.write(WaveArray.REG_TABLE_NEW, 0x0001)

        # Store L0 table of each frame to display. Reduce samplerate by 8.
        for i in range(2**n_frames_log2):
            base = 4096 * i
            self.frames[i] = data[base:base + 2048:8]

        self.auto_offload_enable = True


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


    def btn_enable_hk_clicked(self, checked):
        self.client.write(WaveArray.REG_HK_ENABLE, int(checked))

    def box_hk_rate_changed(self, rate):
        period = 100E6 / (1024 * rate)
        self.client.write(WaveArray.REG_HK_PERIOD, np.uint16(period))

    def btn_reg_read_clicked(self):
        self.ui.box_reg_data.setValue(self.client.read(self.ui.box_reg_address.value()))

    def btn_reg_write_clicked(self):
        self.client.write(self.ui.box_reg_address.value(), self.ui.box_reg_data.value())

    def filter_select_changed(self, index):
        self.client.write(WaveArray.REG_FILTER_SELECT, index)

    def lfo_waveform_changed(self, index):
        self.client.write(WaveArray.REG_LFO_WAVE, index)

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

    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger()
    
    gui = None
    application = QApplication(sys.argv)
    
    try:
        gui = WaveArrayGui()
        gui.show()
        application.exec_()
    except Exception as e:
        logger.error(e)
        if gui:
            gui.client.stop()
        os._exit(1)
        raise e

    else:
        if gui:
            gui.client.stop()
        os._exit(1)


if __name__ == "__main__":
    main()
