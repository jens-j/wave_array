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
from PyQt5.QtWidgets          import QLabel, QApplication, QFileDialog, QVBoxLayout, QRadioButton, QSpacerItem, \
                                     QSizePolicy, QListWidgetItem, QCheckBox
from PyQt5.QtGui              import QIntValidator


from wave_array.client.client import WaveArray
from wave_array.client.modmap import ModMap, MapException
from wave_array.client.status import Status
from wave_array.client.drag_widgets import DragListWidget, DropPlotWidget



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
        self.voice_enabled_buttons = []
        self.voice_active_buttons = []
        self.mod_layout = None

        self.curve_oscilloscope = None
        self.curves_waveform = [None] * self.client.n_voices 
        self.curves_pot = [None] * self.client.n_voices
        self.curves_lfo = [None] * self.client.n_voices
        self.curves_envelope = [None] * self.client.n_voices
        self.curves_cutoff = [None] * self.client.n_voices
        self.curves_resonance = [None] * self.client.n_voices
        self.curves_frame_0 = [None] * self.client.n_voices
        self.curves_frame_1 = [None] * self.client.n_voices
        self.curves_mixer = [None] * self.client.n_voices
        self.curve_x = np.arange(0, self.PLOT_T, self.PLOT_T / self.PLOT_SAMPLES)[::-1] # Constant used for plotting.

        module_path = os.path.dirname(os.path.abspath(__file__))
        self.table_dir = os.path.join(module_path, '../../../data/wavetables/')

        self.t_hk = datetime.now()
        self.t_plot = datetime.now()

        # Initialize the GUI.
        module_path = os.path.dirname(os.path.abspath(__file__))
        ui_path     = os.path.join(module_path, '../../../qt')
        self.ui     = uic.loadUi(os.path.join(ui_path, 'wavearray.ui'))
        self.generate_voice_ui()
        self.generate_mod_matrix()
        self.initialize_plots()

        # table_path = os.path.join(module_path, '../../../data') 
        # self.open_wavetable(filename=os.path.join(table_path, 'saw_square.table'))
        # self.open_wavetable(filename=os.path.join(table_path, 'basic.table'))

        self.load_wavetables()

        # Load initial values.
        self.load_config()

        # Connect signals.
        self.ui.btn_enable_hk.clicked.connect(self.btn_enable_hk_clicked)
        self.ui.box_hk_rate.valueChanged.connect(self.box_hk_rate_changed)
        self.ui.btn_enable_oscilloscope.clicked.connect(self.btn_enable_oscilloscope_clicked)
        self.ui.box_oscilloscope_rate.valueChanged.connect(self.box_oscilloscope_rate_changed)
        self.ui.btn_reg_read.released.connect(self.btn_reg_read_clicked)
        self.ui.btn_reg_write.released.connect(self.btn_reg_write_clicked)
        self.ui.action_load_config.triggered.connect(self.load_config)
        self.ui.box_filter_select.currentIndexChanged.connect(self.filter_select_changed)
        self.ui.box_lfo_waveform.currentIndexChanged.connect(self.lfo_waveform_changed)
        self.ui.slider_mix_0_position.sliderMoved.connect(partial(self.mix_amount_changed, 0))
        self.ui.slider_mix_1_position.sliderMoved.connect(partial(self.mix_amount_changed, 1))
        self.ui.slider_frame_0_position.sliderMoved.connect(partial(self.frame_position_changed, 0))
        self.ui.slider_frame_1_position.sliderMoved.connect(partial(self.frame_position_changed, 1))
        self.ui.slider_lfo_velocity.sliderMoved.connect(self.lfo_velocity_changed)
        self.ui.slider_filter_cutoff.sliderMoved.connect(self.filter_cutoff_changed)
        self.ui.slider_filter_resonance.sliderMoved.connect(self.filter_resonance_changed)
        self.ui.slider_envelope_attack.sliderMoved.connect(self.envelope_attack_changed)
        self.ui.slider_envelope_decay.sliderMoved.connect(self.envelope_decay_changed)
        self.ui.slider_envelope_sustain.sliderMoved.connect(self.envelope_sustain_changed)
        self.ui.slider_envelope_release.sliderMoved.connect(self.envelope_release_changed)
        self.ui.slider_mod_amount.sliderMoved.connect(self.set_mod_amount)
        
        for destination in range(ModMap.MODD_LEN):
            for source in range(ModMap.MODS_LEN - 1): 
                button = self.mod_layout.itemAtPosition(destination, source).widget()
                button.stateChanged.connect(partial(self.mod_button_clicked, destination, source + 1)) # Skip MODS_NONE.

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

        # Set voice leds.
        for i in range(self.client.n_voices):
            self.voice_enabled_buttons[i].setChecked(bool(self.status.voice_enabled & (1 << i)))
            self.voice_active_buttons[i].setChecked(bool(self.status.voice_active & (1 << i)))


        self.curve_oscilloscope.setData(self.oscilloscope_samples)
        
        for i in range(self.client.n_voices):

            self.curves_pot[i].setData(self.curve_x, np.concatenate(
                (self.curves_pot[i].getData()[1][1:], [self.status.mod_sources[ModMap.MODS_POT][i]])))
            self.curves_envelope[i].setData(self.curve_x, np.concatenate(
                (self.curves_envelope[i].getData()[1][1:], [self.status.mod_sources[ModMap.MODS_ENVELOPE][i]])))
            self.curves_lfo[i].setData(self.curve_x, np.concatenate(
                (self.curves_lfo[i].getData()[1][1:], [self.status.mod_sources[ModMap.MODS_LFO][i]])))
            
            self.curves_cutoff[i].setData(self.curve_x, np.concatenate(
                (self.curves_cutoff[i].getData()[1][1:], [self.status.mod_destinations[ModMap.MODD_CUTOFF][i]])))
            self.curves_resonance[i].setData(self.curve_x, np.concatenate(
                (self.curves_resonance[i].getData()[1][1:], [self.status.mod_destinations[ModMap.MODD_RESONANCE][i]])))
            self.curves_frame_0[i].setData(self.curve_x, np.concatenate(
                (self.curves_frame_0[i].getData()[1][1:], [self.status.mod_destinations[ModMap.MODD_OSC_0_FRAME][i]])))
            self.curves_frame_1[i].setData(self.curve_x, np.concatenate(
                (self.curves_frame_1[i].getData()[1][1:], [self.status.mod_destinations[ModMap.MODD_OSC_1_FRAME][i]])))
            self.curves_mixer[i].setData(self.curve_x, np.concatenate(
                (self.curves_mixer[i].getData()[1][1:], [self.status.mod_destinations[ModMap.MODD_VOLUME][i]])))

            
            # # Set waveform plot data.
            # if self.frames_log2 == 0:
            #     self.curves_waveform[i].setData(self.frames[0])

            # # Interpolate between frames 0 and 1.
            # elif self.frames_log2 == 1: 
            #     self.curves_waveform[i].setData(self.frames[0]  + np.int16(
            #         self.status.mod_destinations[ModMap.MODD_FRAME][i] 
            #         * np.int32(self.frames[1] - self.frames[0]) // 2**15))

            # # interpolate between frames a and b.
            # else:
            #     index_a = 2**self.frames_log2 * max(0, self.status.mod_destinations[ModMap.MODD_FRAME][i]) // 2**15 
            #     index_b = min(index_a + 1, 2**self.frames_log2 - 1)
            #     d = max(0, self.status.mod_destinations[ModMap.MODD_FRAME][i]) % 2**(15 - self.frames_log2)
            #     d_max = 2**(15 - self.frames_log2) - 1
                
            #     self.curves_waveform[i].setData(self.frames[index_a] 
            #         + np.int16(d * np.int32(self.frames[index_b] - self.frames[index_a]) // d_max))      


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
        amount = self.client.read(WaveArray.REG_MIX_CTRL_BASE)
        self.ui.slider_mix_0_position.setValue(amount)
        self.ui.lbl_mix_0.setText(f'0x{amount:04X}')

        amount = self.client.read(WaveArray.REG_MIX_CTRL_BASE + 1)
        self.ui.slider_mix_1_position.setValue(amount)
        self.ui.lbl_mix_1.setText(f'0x{amount:04X}')

        position = self.client.read(WaveArray.REG_FRAME_CTRL_BASE)
        self.ui.slider_frame_0_position.setValue(position)
        self.ui.lbl_position_0.setText(f'0x{position:04X}')

        position = self.client.read(WaveArray.REG_FRAME_CTRL_BASE + 1)
        self.ui.slider_frame_1_position.setValue(position)
        self.ui.lbl_position_1.setText(f'0x{position:04X}')

        velocity = self.client.read(WaveArray.REG_LFO_VELOCITY)
        self.ui.slider_lfo_velocity.setValue(velocity)
        self.ui.lbl_velocity.setText(f'0x{velocity:04X}')

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

        for destination in range(ModMap.MODD_LEN):
            for source in range(1, ModMap.MODS_LEN):
                box = self.mod_layout.itemAtPosition(destination, source - 1).widget()
                enable, amount = self.modmap.get_mapping(destination, source)
                box.setChecked(enable)

       
    def generate_voice_ui(self):

        for i in range(self.client.n_voices):

            layout = QVBoxLayout()
            label = QLabel(f'{i}') 
            label.setStyleSheet("font-weight: normal");
            label.setAlignment(Qt.AlignCenter)
            layout.addWidget(label)

            for j in range(2):
                btn = QRadioButton('')
                # btn.setCheckable(False)
                btn.setAutoExclusive(False)
                btn.setMinimumSize(20, 20)
                btn.setMaximumSize(20, 20)
                layout.addWidget(btn)

                if j == 0:
                    self.voice_enabled_buttons.append(btn)
                else:
                    self.voice_active_buttons.append(btn)

            self.ui.group_voices.layout().insertLayout(2, layout, 0) # Skip labels and separator.

        # self.ui.group_voices.layout().addItem(QSpacerItem(20, 40, QSizePolicy.Minimum, QSizePolicy.Expanding))

    def generate_mod_matrix(self):

        self.mod_layout = self.ui.group_mod_matrix.layout().children()[1].children()[-1] # .layout_matrix_col.layout_mod_matrix

        for destination in range(ModMap.MODD_LEN):
            for source in range(ModMap.MODS_LEN - 1):
                box = QCheckBox('')
                self.mod_layout.addWidget(box, destination, source)


    def initialize_plots(self):

        # Add callback to wavetable write when a table is dropped on the oscillator plots.
        self.ui.plot_waveform_0.addDropCallback(self.write_wavetable)
        self.ui.plot_waveform_1.addDropCallback(self.write_wavetable)
        
        self.ui.plot_cutoff.setBackground('w')
        self.ui.plot_cutoff.setTitle('filter cutoff')
        self.ui.plot_cutoff.setYRange(0, 2**15, padding=0)

        self.ui.plot_resonance.setBackground('w')
        self.ui.plot_resonance.setTitle('filter resonance')
        self.ui.plot_resonance.setYRange(0, 2**15, padding=0)

        self.ui.plot_frame_0.setBackground('w')
        self.ui.plot_frame_0.setTitle('wavetable frame')
        self.ui.plot_frame_0.setYRange(0, 2**15, padding=0)

        self.ui.plot_frame_1.setBackground('w')
        self.ui.plot_frame_1.setTitle('wavetable frame')
        self.ui.plot_frame_1.setYRange(0, 2**15, padding=0)

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

        self.ui.plot_waveform_0.setBackground('w')
        self.ui.plot_waveform_0.setTitle('wavetable 0')
        self.ui.plot_waveform_0.setYRange(-2**15, 2**15, padding=0)

        self.ui.plot_waveform_1.setBackground('w')
        self.ui.plot_waveform_1.setTitle('wavetable 1')
        self.ui.plot_waveform_1.setYRange(-2**15, 2**15, padding=0)

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

            self.curves_frame_0[i] = self.ui.plot_frame_0.plot(
                self.curve_x, np.zeros(self.PLOT_SAMPLES), name=f'voice {i}', pen=pen)

            self.curves_frame_1[i] = self.ui.plot_frame_1.plot(
                self.curve_x, np.zeros(self.PLOT_SAMPLES), name=f'voice {i}', pen=pen)

            self.curves_mixer[i] = self.ui.plot_mixer.plot(
                self.curve_x, np.zeros(self.PLOT_SAMPLES), name=f'voice {i}', pen=pen)

            self.curves_waveform[i] = self.ui.plot_waveform_0.plot(np.zeros(2048), name=f'voice {i}', pen=pen)

            if i == self.client.n_voices - 1:
                self.curve_oscilloscope = self.ui.plot_oscilloscope.plot(np.zeros(100), pen=pen)


    def show(self):
        """ Re-implemented from QMainWindow. """
        self.ui.show()

    
    def load_wavetables(self):

        module_path = os.path.dirname(os.path.abspath(__file__))
        table_path     = os.path.join(module_path, '../../../data/wavetables')

        for filename in os.listdir(self.table_dir):

            parts = filename.split('.')

            if len(parts) > 2:
                log.warning(f'Illegal wavetable file name {filename}')

            elif parts[1] != 'table':
                log.warning(f'Wavetable file name has wrong extension {filename}')

            else:
                label = QListWidgetItem(parts[0])
                self.ui.list_tables.addItem(label)


    # Write a wavetable to the SDRAM. Currently only one wavetable is stored per oscillator.
    def write_wavetable(self, table_name, index):

        filepath = self.table_dir + table_name + '.table'

        with open(filepath, 'r') as f:
            raw_data = f.read().split('\n')

        raw_data = list(filter(lambda x: x != '', raw_data))
        data = np.array([int(x, 16) for x in raw_data]).astype('int16')
        frames_log2 = np.uint16(np.log2(len(data) / 4096))
        address = 0x0000_0000 if index == 0 else 0x0000_4000
        offset = 0 if index == 0 else 4

        # Write table to sdram.
        self.client.write_sdram(0, data)

        # Update table registers.
        self.client.write(WaveArray.REG_TABLE_BASE + offset    , (address >> 16) & 0xFFFF)
        self.client.write(WaveArray.REG_TABLE_BASE + offset + 1, address & 0xFFFF)
        self.client.write(WaveArray.REG_TABLE_BASE + offset + 2, frames_log2)
        self.client.write(WaveArray.REG_TABLE_BASE + offset + 3, 0x0001)


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

    def mix_amount_changed(self, index, control_value):
        self.client.write(WaveArray.REG_MIX_CTRL_BASE + index, control_value)
        lbl = getattr(self.ui, f'lbl_mix_{index}')
        lbl.setText(f'0x{control_value:04X}')

    def frame_position_changed(self, index, control_value):
        self.client.write(WaveArray.REG_FRAME_CTRL_BASE + index, control_value)
        lbl = getattr(self.ui, f'lbl_position_{index}')
        lbl.setText(f'0x{control_value:04X}')

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
