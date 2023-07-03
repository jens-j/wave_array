#!/usr/bin/env python3

import os
import sys 
import logging
import struct
from functools                import partial
from random                   import randint, random
from datetime                 import datetime

import pyqtgraph              as pg
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

    PLOT_T       = 5 # Seconds.
    PLOT_SAMPLES = PLOT_T * PLOT_FREQUENCY

    logger = logging.getLogger()

    def __init__(self):

        QtWidgets.QMainWindow.__init__(self)
        self.setWindowTitle('Wave Array')

        self.auto_offload_enable = False

        # Create client object.
        self.client = WaveArray(self.hk_offload_handler, self.wave_offload_handler)
        
        self.mod_source = None 
        self.mod_destination = None
        self.modmap = ModMap(self.client)
        self.frames = [None] * 16 
        self.frames_log2 = 0
        self.status = Status(self.client)
        self.oscilloscope_samples = np.zeros(100, dtype=np.int16)

        self.curve_oscilloscope = None
        self.curves_waveform = [None] * self.client.n_voices 
        self.curves_pot = [None] * self.client.n_voices
        self.curves_lfo = [None] * self.client.n_voices
        self.curves_envelope = [None] * self.client.n_voices
        self.curves_cutoff = [None] * self.client.n_voices
        self.curves_resonance = [None] * self.client.n_voices
        self.curves_frame = [None] * self.client.n_voices
        self.curves_mixer = [None] * self.client.n_voices
        self.curve_x = np.arange(0, self.PLOT_T, self.PLOT_T / self.PLOT_SAMPLES)[::-1] # Constant used for plotting.

        self.t_hk = datetime.now()
        self.t_plot = datetime.now()

        # Initialize the GUI.
        module_path = os.path.dirname(os.path.abspath(__file__))
        ui_path     = os.path.join(module_path, '../../../qt')
        self.ui     = uic.loadUi(os.path.join(ui_path, 'wavearray.ui'))
        self.initialize_plots()

        table_path = os.path.join(module_path, '../../../data') 
        # self.open_wavetable(filename=os.path.join(table_path, 'saw_square.table'))
        self.open_wavetable(filename=os.path.join(table_path, 'basic.table'))

        # Load initial values.
        self.load_config()

        # Connect signals.
        self.ui.btn_enable_hk.clicked.connect(self.btn_enable_hk_clicked)
        self.ui.box_hk_rate.valueChanged.connect(self.box_hk_rate_changed)
        self.ui.btn_enable_oscilloscope.clicked.connect(self.btn_enable_oscilloscope_clicked)
        self.ui.box_oscilloscope_rate.valueChanged.connect(self.box_oscilloscope_rate_changed)
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
        self.timer.timeout.connect(self.update_plots)
        self.timer.start(self.PLOT_PERIOD_MS)

        # Start auto offload handling.
        self.auto_offload_enable = True


    def hk_offload_handler(self, packet):

        if self.auto_offload_enable:
            self.status = Status(self.client, packet=packet)   

    def wave_offload_handler(self, packet):

        if self.auto_offload_enable:

            length = struct.unpack('<h', packet[2:4])[0]
            data = np.array(struct.unpack(f'<{length}h', packet[4:]))
            self.oscilloscope_samples = data

                    
    def update_plots(self):

        
        # t = datetime.now()

        self.ui.lbl_voice_enabled.setText(f'{self.status.voice_enabled:04X}')
        self.ui.lbl_voice_active.setText(f'{self.status.voice_active:04X}')

        # print(f'state sample = {self.client.read(WaveArray.REG_DBG_STATE_WAVE_SAMPLE)}')
        # print(f'state offload = {self.client.read(WaveArray.REG_DBG_STATE_WAVE_OFFLOAD)}')

        self.curve_oscilloscope.setData(self.oscilloscope_samples)
        
        for i in range(self.client.n_voices):

            self.curves_pot[i].setData(self.curve_x, np.concatenate(
                (self.curves_pot[i].getData()[1][1:], [self.status.mod_sources[WaveArray.MODS_POT][i]])))
            self.curves_envelope[i].setData(self.curve_x, np.concatenate(
                (self.curves_envelope[i].getData()[1][1:], [self.status.mod_sources[WaveArray.MODS_ENVELOPE][i]])))
            self.curves_lfo[i].setData(self.curve_x, np.concatenate(
                (self.curves_lfo[i].getData()[1][1:], [self.status.mod_sources[WaveArray.MODS_LFO][i]])))
            
            self.curves_cutoff[i].setData(self.curve_x, np.concatenate(
                (self.curves_cutoff[i].getData()[1][1:], [self.status.mod_destinations[WaveArray.MODD_CUTOFF][i]])))
            self.curves_resonance[i].setData(self.curve_x, np.concatenate(
                (self.curves_resonance[i].getData()[1][1:], [self.status.mod_destinations[WaveArray.MODD_RESONANCE][i]])))
            self.curves_frame[i].setData(self.curve_x, np.concatenate(
                (self.curves_frame[i].getData()[1][1:], [self.status.mod_destinations[WaveArray.MODD_FRAME][i]])))
            self.curves_mixer[i].setData(self.curve_x, np.concatenate(
                (self.curves_mixer[i].getData()[1][1:], [self.status.mod_destinations[WaveArray.MODD_MIXER][i]])))

            
            # Set waveform plot data.
            if self.frames_log2 == 0:
                self.curves_waveform[i].setData(self.frames[0])

            # Interpolate between frames 0 and 1.
            elif self.frames_log2 == 1: 
                self.curves_waveform[i].setData(self.frames[0]  + np.int16(
                    self.status.mod_destinations[WaveArray.MODD_FRAME][i] 
                    * np.int32(self.frames[1] - self.frames[0]) // 2**15))

            # interpolate between frames a and b.
            else:
                index_a = 2**self.frames_log2 * max(0, self.status.mod_destinations[WaveArray.MODD_FRAME][i]) // 2**15 
                index_b = min(index_a + 1, 2**self.frames_log2 - 1)
                d = max(0, self.status.mod_destinations[WaveArray.MODD_FRAME][i]) % 2**(15 - self.frames_log2)
                d_max = 2**(15 - self.frames_log2) - 1
                
                self.curves_waveform[i].setData(self.frames[index_a] 
                    + np.int16(d * np.int32(self.frames[index_b] - self.frames[index_a]) // d_max))      


    # Read device settings and update GUI elements accordingly.
    def load_config(self):

        # Initialize configuration.
        enabled = self.client.read(WaveArray.REG_HK_ENABLE)
        self.ui.btn_enable_hk.setChecked(enabled)

        period = self.client.read(WaveArray.REG_HK_PERIOD)
        rate = 100E6 / (period * 1024)
        self.ui.box_hk_rate.setValue(int(rate))

        enabled = self.client.read(WaveArray.REG_WAVE_ENABLE)
        self.ui.btn_enable_oscilloscope.setChecked(enabled)

        period = self.client.read(WaveArray.REG_WAVE_PERIOD)
        rate = 100E6 / (period * 1024)
        self.ui.box_oscilloscope_rate.setValue(int(rate))
    
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
        
        self.ui.plot_cutoff.setBackground('w')
        self.ui.plot_cutoff.setTitle('filter cutoff')
        self.ui.plot_cutoff.setYRange(0, 2**15, padding=0)

        self.ui.plot_resonance.setBackground('w')
        self.ui.plot_resonance.setTitle('filter resonance')
        self.ui.plot_resonance.setYRange(0, 2**15, padding=0)

        self.ui.plot_frame.setBackground('w')
        self.ui.plot_frame.setTitle('wavetable frame')
        self.ui.plot_frame.setYRange(0, 2**15, padding=0)

        self.ui.plot_mixer.setBackground('w')
        self.ui.plot_mixer.setTitle('mixer')
        self.ui.plot_mixer.setYRange(0, 2**15, padding=0)
        
        self.ui.plot_pot.setBackground('w')
        self.ui.plot_pot.setTitle('potentiometer')
        self.ui.plot_pot.setYRange(0, 2**15, padding=0)

        self.ui.plot_envelope.setBackground('w')
        self.ui.plot_envelope.setTitle('envelope')
        self.ui.plot_envelope.setYRange(0, 2**15, padding=0)

        self.ui.plot_lfo.setBackground('w')
        self.ui.plot_lfo.setTitle('LFO')
        self.ui.plot_lfo.setYRange(-2**15, 2**15, padding=0)

        self.ui.plot_waveform.setBackground('w')
        self.ui.plot_waveform.setTitle('waveform')
        self.ui.plot_waveform.setYRange(-2**15, 2**15, padding=0)

        self.ui.plot_oscilloscope.setBackground('w')
        self.ui.plot_oscilloscope.setTitle('oscilloscope')
        # self.ui.plot_oscilloscope.setYRange(-2**15, 2**15, padding=0)

        hue = random() / self.client.n_voices

        # Plot curves and store PlotDataItem.     
        for i in range(self.client.n_voices):

            pen = pg.mkPen(color=pg.hsvColor((hue + i / self.client.n_voices) % 1.0))

            self.curves_pot[i] = self.ui.plot_pot.plot(
                self.curve_x, np.zeros(self.PLOT_SAMPLES), name=f'voice {i}', pen=pen)

            self.curves_envelope[i] = self.ui.plot_envelope.plot(
                self.curve_x, np.zeros(self.PLOT_SAMPLES), name=f'voice {i}', pen=pen)

            self.curves_lfo[i] = self.ui.plot_lfo.plot(
                self.curve_x, np.zeros(self.PLOT_SAMPLES), name=f'voice {i}', pen=pen)

            self.curves_cutoff[i] = self.ui.plot_cutoff.plot(
                self.curve_x, np.zeros(self.PLOT_SAMPLES), name=f'voice {i}', pen=pen)

            self.curves_resonance[i] = self.ui.plot_resonance.plot(
                self.curve_x, np.zeros(self.PLOT_SAMPLES), name=f'voice {i}', pen=pen)

            self.curves_frame[i] = self.ui.plot_frame.plot(
                self.curve_x, np.zeros(self.PLOT_SAMPLES), name=f'voice {i}', pen=pen)

            self.curves_mixer[i] = self.ui.plot_mixer.plot(
                self.curve_x, np.zeros(self.PLOT_SAMPLES), name=f'voice {i}', pen=pen)

            self.curves_waveform[i] = self.ui.plot_waveform.plot(np.zeros(2048), name=f'voice {i}', pen=pen)

            if i == self.client.n_voices - 1:
                self.curve_oscilloscope = self.ui.plot_oscilloscope.plot(np.zeros(100), pen=pen)


    def show(self):
        """ Re-implemented from QMainWindow. """
        self.ui.show()

    
    def open_wavetable(self, filename=None):

        # This does not work well toghether.
        # self.auto_offload_enable = False

        if filename == None:
            dlg = QFileDialog()
            dlg.setDirectory(default_path)
            dlg.setFileMode(QFileDialog.AnyFile)
            # dlg.selectNameFilter("Wavetable files (*.table)")

            print('ok')
            
            if dlg.exec_():
                filename = dlg.selectedFiles()[0]

        with open(filename, 'r') as f:
            raw_data = f.read().split('\n')

        raw_data = list(filter(lambda x: x != '', raw_data))
        data = np.array([int(x, 16) for x in raw_data]).astype('int16')

        # Write table to sdram.
        self.client.write_sdram(0, data)

        # Update table registers.
        self.frames_log2 = np.uint16(np.log2(len(data) / 4096))
        self.client.write(WaveArray.REG_TABLE_BASE_H, 0x0000)
        self.client.write(WaveArray.REG_TABLE_BASE_L, 0x0000)
        self.client.write(WaveArray.REG_TABLE_FRAMES, self.frames_log2)
        self.client.write(WaveArray.REG_TABLE_NEW, 0x0001)

        # Update n_frames in gui.
        self.ui.lbl_frames.setText(f'{2**self.frames_log2}')

        # Store L0 table of each frame to display. Reduce samplerate by 8.
        for i in range(2**self.frames_log2):
            base = 4096 * i
            self.frames[i] = data[base:base + 2048]

        # self.auto_offload_enable = True


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

    def btn_enable_oscilloscope_clicked(self, checked):
        self.client.write(WaveArray.REG_WAVE_ENABLE, int(checked))

    def box_oscilloscope_rate_changed(self, rate):
        period = 100E6 / (1024 * rate)
        self.client.write(WaveArray.REG_WAVE_PERIOD, np.uint16(period))

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
