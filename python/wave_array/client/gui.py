#!/usr/bin/env python3

import os
import sys 
import logging
import struct
from functools                import partial
from random                   import randint, random
from time                     import time, sleep

import pyqtgraph              as pg
import numpy                  as np
from PyQt5                    import QtWidgets, uic
from PyQt5.QtCore             import QObject, QSize, QSettings, Qt, QTimer, pyqtSignal
from PyQt5.QtWidgets          import QLabel, QApplication, QFileDialog, QVBoxLayout, QRadioButton, QSpacerItem, \
                                     QSizePolicy, QListWidgetItem, QCheckBox, QHBoxLayout, QFrame
from PyQt5.QtGui              import QIntValidator


from wave_array.client.client import WaveArray
from wave_array.client.wavetable import TableManager
from wave_array.client.modmap import ModMap, MapException
from wave_array.client.status import Status
from wave_array.client.wavetable import WaveTable
from wave_array.client.drag_widgets import DragListWidget, DropPlotWidget


class auto_offload_signal(QObject):

    received = pyqtSignal('QByteArray')



class WaveArrayGui(QtWidgets.QMainWindow):

    PLOT_FREQUENCY = 50
    PLOT_PERIOD_MS = 1000 // PLOT_FREQUENCY

    PLOT_T       = 4 # Seconds.
    PLOT_SAMPLES = PLOT_T * PLOT_FREQUENCY

    logger = logging.getLogger()

    def __init__(self, application):

        QtWidgets.QMainWindow.__init__(self)

        self.application = application

        self.setWindowTitle('Wave Array')

        self.auto_offload_enable = False

        # Create client object.
        self.hk_signal = auto_offload_signal()
        self.wave_signal = auto_offload_signal()
        self.client = WaveArray(self.hk_signal, self.wave_signal)

        # Create table manager 
        self.table_manager = TableManager(self.client)
        
        self.mod_source = None 
        self.mod_destination = None
        self.mod_button = None
        self.modmap = ModMap(self.client)
        self.wavetables = [None, None]
        self.status = Status(self.client)
        self.oscilloscope_samples = np.zeros(100, dtype=np.int16)
        self.voice_enabled_buttons = []
        self.voice_active_buttons = []
        self.voice_labels = []
        self.lfo_select_buttons = []
        self.mods_plot_buttons = []
        self.modd_plot_buttons = []
        self.lfo_index = 0
        self.envelope_select_buttons = [] 
        self.envelope_index = 0

        self.curve_oscilloscope = None
        self.curves_waveforms = [[None] * self.client.n_voices, [None] * self.client.n_voices]
        self.plots_mods = []
        self.plots_modd = []
        self.curves_mods = [[] for i in range(len(ModMap.MODS_STRING) - 1)]
        self.curves_modd = [[] for i in range(len(ModMap.MODD_STRING))]
        self.curve_x = np.arange(0, self.PLOT_T, self.PLOT_T / self.PLOT_SAMPLES)[::-1] # Constant used for plotting.

        module_path = os.path.dirname(os.path.abspath(__file__))
        self.table_dir = os.path.join(module_path, '../../../data/wavetables/')

        self.t_hk = time()
        self.t_plot = time()

        # Initialize the GUI.
        module_path = os.path.dirname(os.path.abspath(__file__))
        ui_path     = os.path.join(module_path, '../../../qt')
        self.ui     = uic.loadUi(os.path.join(ui_path, 'wavearray.ui'))

        self.mods_plots_layout = self.ui.group_mods.layout() 
        self.modd_plots_layout = self.ui.group_modd.layout()
        self.matrix_layout = self.ui.group_mod_matrix.layout().children()[1].children()[-1] 
        self.mods_labels_layout = self.ui.group_mod_matrix.layout().children()[1].children()[0] 
        self.modd_labels_layout = self.ui.group_mod_matrix.layout().children()[0].children()[0].children()[0]

        self.generate_voice_ui()
        self.generate_mod_matrix()
        self.generate_lfo_ui()
        self.generate_envelope_ui()
        self.generate_plot_select()
        self.initialize_plots()
        self.load_stylesheets()
        self.load_wavetables()

        # Load initial values.
        self.load_config()

        # Set range for unison spinbox.
        self.ui.box_unison.setRange(1, self.client.read(WaveArray.REG_UNISON_MAX))

        # Connect signals.
        self.hk_signal.received.connect(self.hk_offload_handler)
        self.wave_signal.received.connect(self.wave_offload_handler)

        self.ui.btn_enable_hk.clicked.connect(self.btn_enable_hk_clicked)
        self.ui.btn_enable_oscilloscope.clicked.connect(self.btn_enable_oscilloscope_clicked)
        self.ui.btn_enable_lfo_trigger.clicked.connect(self.btn_enable_lfo_trigger_clicked)
        self.ui.btn_enable_binaural.clicked.connect(self.btn_enable_binaural_clicked)
        self.ui.btn_mod_disable.clicked.connect(self.btn_mod_disable_clicked)
        self.ui.btn_mod_zero.clicked.connect(self.btn_mod_zero_clicked)

        for btn in self.lfo_select_buttons:
            btn.clicked.connect(self.btn_lfo_index_changed)

        for btn in self.envelope_select_buttons:
            btn.clicked.connect(self.btn_envelope_index_changed)
        
        self.ui.btn_reg_read.released.connect(self.btn_reg_read_clicked)
        self.ui.btn_reg_write.released.connect(self.btn_reg_write_clicked)
        self.ui.btn_reset_pitch_0.released.connect(partial(self.btn_reset_pitch_clicked, 0))
        self.ui.btn_reset_pitch_1.released.connect(partial(self.btn_reset_pitch_clicked, 1))
        self.ui.btn_lfo_reset.released.connect(self.btn_lfo_reset_clicked)

        self.ui.box_unison.valueChanged.connect(self.box_unison_n_changed)
        self.ui.box_hk_rate.valueChanged.connect(self.box_hk_rate_changed)
        self.ui.box_midi_channel.valueChanged.connect(self.box_midi_channel_changed)
        self.ui.box_oscilloscope_rate.valueChanged.connect(self.box_oscilloscope_rate_changed)
        self.ui.box_filter_select.currentIndexChanged.connect(self.filter_select_changed)
        self.ui.box_lfo_waveform.currentIndexChanged.connect(self.lfo_waveform_changed)
        self.ui.box_noise_select.currentIndexChanged.connect(self.noise_select_changed)

        self.ui.box_octaves_0.valueChanged.connect(partial(self.pitch_changed, 0))
        self.ui.box_octaves_1.valueChanged.connect(partial(self.pitch_changed, 1))
        self.ui.box_semitones_0.valueChanged.connect(partial(self.pitch_changed, 0))
        self.ui.box_semitones_1.valueChanged.connect(partial(self.pitch_changed, 1))

        self.ui.action_load_config.triggered.connect(self.load_config)
        self.ui.action_reset.triggered.connect(self.software_reset)

        self.ui.slider_mix_0_position.sliderMoved.connect(partial(self.mix_amount_changed, 0))
        self.ui.slider_mix_1_position.sliderMoved.connect(partial(self.mix_amount_changed, 1))
        self.ui.slider_mix_noise_position.sliderMoved.connect(partial(self.mix_amount_changed, 2))
        self.ui.slider_frame_0_position.sliderMoved.connect(partial(self.frame_position_changed, 0))
        self.ui.slider_frame_1_position.sliderMoved.connect(partial(self.frame_position_changed, 1))
        self.ui.slider_pitch_0.sliderMoved.connect(partial(self.pitch_changed, 0))
        self.ui.slider_pitch_1.sliderMoved.connect(partial(self.pitch_changed, 1))
        self.ui.slider_unison_spread.sliderMoved.connect(self.unison_spread_changed)
        self.ui.slider_lfo_velocity.sliderMoved.connect(self.lfo_velocity_changed)
        self.ui.slider_lfo_phase.sliderMoved.connect(self.lfo_phase_changed)
        self.ui.slider_lfo_amplitude.sliderMoved.connect(self.lfo_amplitude_changed)
        self.ui.slider_filter_cutoff.sliderMoved.connect(self.filter_cutoff_changed)
        self.ui.slider_filter_resonance.sliderMoved.connect(self.filter_resonance_changed)
        self.ui.slider_envelope_attack.sliderMoved.connect(self.envelope_attack_changed)
        self.ui.slider_envelope_decay.sliderMoved.connect(self.envelope_decay_changed)
        self.ui.slider_envelope_sustain.sliderMoved.connect(self.envelope_sustain_changed)
        self.ui.slider_envelope_release.sliderMoved.connect(self.envelope_release_changed)
        self.ui.slider_mod_amount.sliderMoved.connect(self.set_mod_amount)
        
        # Connect mod matrix signals.
        for destination in range(ModMap.MODD_LEN):
            for source in range(ModMap.MODS_LEN - 1): 
                button = self.matrix_layout.itemAtPosition(destination, source).widget()
                button.clicked.connect(partial(self.mod_button_clicked, button, destination, source + 1)) # Skip MODS_NONE.

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
            # self.logger.info(f'wave packet [{len(data)} / {length}]')
            self.oscilloscope_samples = data


    def show_hide_plot(self, btn_enable, plot):
        if btn_enable.isChecked():
            plot.show()
        else:
            plot.hide()

                    
    def update_plots(self):
        
        t = time()
        # self.logger.info(f'plot T = {(t - self.t_plot)}')
        self.t_plot = t

        self.ui.lbl_voice_enabled.setText(f'0x{self.status.voice_enabled:04X}')
        self.ui.lbl_voice_active.setText(f'0x{self.status.voice_active:04X}')
        self.ui.lbl_polyphony.setText(f'{self.status.polyphony:d}')
        self.ui.lbl_active_voices.setText(f'{self.status.active_voices:d}')
        self.ui.lbl_active_oscillators.setText(f'{self.status.active_oscillators:d}')

        # Set voice leds.
        for i in range(self.client.n_voices):
            self.voice_enabled_buttons[i].setChecked(bool(self.status.voice_enabled & (1 << i)))
            self.voice_active_buttons[i].setChecked(bool(self.status.voice_active & (1 << i)))

            # Grey out any unused voices in current configuration.
            if i < self.status.active_voices:
                self.voice_labels[i].show()
                self.voice_enabled_buttons[i].show()
                self.voice_active_buttons[i].show()
            else:
                self.voice_labels[i].hide()
                self.voice_enabled_buttons[i].hide()
                self.voice_active_buttons[i].hide()

        self.curve_oscilloscope.setData(self.oscilloscope_samples)

        for i in range(self.client.n_voices):

            # Update mod source plots.
            for j in range(len(ModMap.MODS_STRING) - 1):
                self.curves_mods[j][i].setData(self.curve_x, np.concatenate((
                    self.curves_mods[j][i].getData()[1][1:], [self.status.mod_sources[j + 1][i]]))) # Skip MODS_NONE
                
            # Update mod destination plots.
            for j in range(len(ModMap.MODD_STRING)):
                self.curves_modd[j][i].setData(self.curve_x, np.concatenate((
                    self.curves_modd[j][i].getData()[1][1:], [self.status.mod_destinations[j][i]])))
            
            # Don't show curves for unused polyphonic voices.
            for curves in self.curves_modd + self.curves_mods:
                
                if i < self.status.polyphony * (2 if self.ui.btn_enable_binaural.isChecked() else 1):
                    curves[i].show()
                else:
                    curves[i].hide()
                            
            # Update both wavetable plots.
            for j in range(2):

                wavetable = self.wavetables[j]
                n_frames_log2 = wavetable.descriptor.n_frames_log2

                dest = ModMap.MODD_OSC_0_FRAME if j == 0 else ModMap.MODD_OSC_1_FRAME
            
                # Set waveform plot data.
                if n_frames_log2 == 0:
                    self.curves_waveforms[j][i].setData(wavetable.frames[0])

                # Interpolate between frames 0 and 1.
                elif n_frames_log2 == 1: 
                    self.curves_waveforms[j][i].setData(wavetable.frames[0] 
                        + np.int16(np.int32(self.status.mod_destinations[dest][i]) 
                            * (np.int32(wavetable.frames[1]) - np.int32(wavetable.frames[0])) // 2**15))

                # interpolate between frames a and b.
                else:
                    index_a = 2**n_frames_log2 * max(0, self.status.mod_destinations[dest][i]) // 2**15 
                    index_b = min(index_a + 1, 2**n_frames_log2 - 1)
                    d = max(0, self.status.mod_destinations[dest][i]) % 2**(15 - n_frames_log2)
                    d_max = 2**(15 - n_frames_log2)
                    
                    self.curves_waveforms[j][i].setData(wavetable.frames[index_a] 
                        + np.int16(np.int32(d) * (np.int32(wavetable.frames[index_b]) 
                                                  - np.int32(wavetable.frames[index_a])) // d_max))
                    
                if i < self.status.polyphony * (2 if self.ui.btn_enable_binaural.isChecked() else 1):
                    self.curves_waveforms[j][i].show()
                else:
                    self.curves_waveforms[j][i].hide()

        # Hide un-enabled mod destination plots.
        for i in range(len(ModMap.MODS_STRING) - 1):
            self.show_hide_plot(self.mods_plot_buttons[i], self.plots_mods[i])

        for i in range(len(ModMap.MODD_STRING)):
            self.show_hide_plot(self.modd_plot_buttons[i], self.plots_modd[i])


    # Perform a software reset on the fpga and reload the gui.
    def software_reset(self):

        try:
            self.client.write(WaveArray.REG_RESET, 1) # This will timeout.
        except:
            pass 

        self.load_config()


    # Read device settings and update GUI elements accordingly.
    def load_config(self):

        # Initialize configuration.
        enabled = self.client.read(WaveArray.REG_HK_ENABLE)
        self.ui.btn_enable_hk.setChecked(enabled)

        period = self.client.read(WaveArray.REG_HK_PERIOD)
        rate = 100E6 / (period * 1024)
        self.ui.box_hk_rate.setValue(int(rate))

        channel = self.client.read(WaveArray.REG_MIDI_CHANNEL)
        self.ui.box_midi_channel.setValue(channel + 1)

        enabled = self.client.read(WaveArray.REG_WAVE_ENABLE)
        self.ui.btn_enable_oscilloscope.setChecked(enabled)

        enabled = self.client.read(WaveArray.REG_LFO_CTRL_BASE + 2)
        self.ui.btn_enable_lfo_trigger.setChecked(enabled)

        period = self.client.read(WaveArray.REG_WAVE_PERIOD)
        rate = 100E6 / (period * 1024)
        self.ui.box_oscilloscope_rate.setValue(int(rate))
    
        index = self.client.read(WaveArray.REG_FILTER_SELECT)
        self.ui.box_filter_select.setCurrentIndex(index)

        index = self.client.read(WaveArray.REG_LFO_CTRL_BASE + 1)
        self.ui.box_lfo_waveform.setCurrentIndex(index)

        index = self.client.read(WaveArray.REG_NOISE_SELECT)
        self.ui.box_noise_select.setCurrentIndex(index) 

        enabled = self.client.read(WaveArray.REG_BINAURAL)
        self.ui.btn_enable_binaural.setChecked(enabled)

        unison_n = self.client.read(WaveArray.REG_UNISON_N)
        self.ui.box_unison.setValue(unison_n)

        # Initialize sliders.
        amount = self.client.read(WaveArray.REG_MIX_CTRL_BASE)
        self.ui.slider_mix_0_position.setValue(amount)
        self.mix_amount_changed(0, amount)

        amount = self.client.read(WaveArray.REG_MIX_CTRL_BASE + 1)
        self.ui.slider_mix_1_position.setValue(amount)
        self.mix_amount_changed(1, amount)

        amount = self.client.read(WaveArray.REG_MIX_CTRL_BASE + 2) # Noise mix slider
        self.ui.slider_mix_noise_position.setValue(amount)
        self.mix_amount_changed(2, amount)

        position = self.client.read(WaveArray.REG_FRAME_CTRL_BASE)
        self.ui.slider_frame_0_position.setValue(position)
        self.frame_position_changed(0, position)

        position = self.client.read(WaveArray.REG_FRAME_CTRL_BASE + 1)
        self.ui.slider_frame_1_position.setValue(position)
        self.frame_position_changed(1, position)

        frequency = self.client.read(WaveArray.REG_FREQ_CTRL_BASE, signed=True)
        self.ui.slider_pitch_0.setValue(frequency)
        self.frame_position_changed(0, frequency)

        frequency = self.client.read(WaveArray.REG_FREQ_CTRL_BASE + 1, signed=True)
        self.ui.slider_pitch_1.setValue(frequency)
        self.frame_position_changed(1, frequency)

        spread = self.client.read(WaveArray.REG_UNISON_SPREAD)
        self.ui.slider_unison_spread.setValue(spread)
        self.unison_spread_changed(spread)

        velocity = self.client.read(WaveArray.REG_LFO_CTRL_BASE)
        self.ui.slider_lfo_velocity.setValue(velocity)
        self.lfo_velocity_changed(velocity)

        phase = self.client.read(WaveArray.REG_LFO_CTRL_BASE + 3)
        self.ui.slider_lfo_phase.setValue(phase)
        self.lfo_phase_changed(phase)

        amplitude = self.client.read(WaveArray.REG_LFO_CTRL_BASE + 6)
        self.ui.slider_lfo_amplitude.setValue(amplitude)
        self.lfo_amplitude_changed(amplitude)

        cutoff = self.client.read(WaveArray.REG_FILTER_CUTOFF)
        self.ui.slider_filter_cutoff.setValue(cutoff)
        self.filter_cutoff_changed(cutoff)

        resonance = self.client.read(WaveArray.REG_FILTER_RESONANCE)
        self.ui.slider_filter_resonance.setValue(resonance)
        self.filter_resonance_changed(resonance)

        attack = self.client.read(WaveArray.REG_ENVELOPE_CTRL_BASE)
        self.ui.slider_envelope_attack.setValue(attack)
        self.envelope_attack_changed(attack)

        decay = self.client.read(WaveArray.REG_ENVELOPE_CTRL_BASE + 1)
        self.ui.slider_envelope_decay.setValue(decay)
        self.envelope_decay_changed(decay)

        sustain = self.client.read(WaveArray.REG_ENVELOPE_CTRL_BASE + 2)
        self.ui.slider_envelope_sustain.setValue(sustain)
        self.envelope_sustain_changed(sustain)

        release = self.client.read(WaveArray.REG_ENVELOPE_CTRL_BASE + 3)
        self.ui.slider_envelope_release.setValue(release)  
        self.envelope_release_changed(release)

        # Initialize pitch control.
        for index in range(2):

            pitch_control = self.client.read(WaveArray.REG_FREQ_CTRL_BASE + index, signed=True)

            oct = int(np.round(pitch_control / ModMap.MOD_FREQ_STEP_OCTAVE))
            semi = int(np.fmod(pitch_control, ModMap.MOD_FREQ_STEP_OCTAVE) / ModMap.MOD_FREQ_STEP_SEMITONE)
            cent = int(np.fmod(pitch_control, ModMap.MOD_FREQ_STEP_SEMITONE) / ModMap.MOD_FREQ_STEP_CENT)

            print(oct, semi, cent)
            
            getattr(self.ui, f'box_octaves_{index}').setValue(oct)
            getattr(self.ui, f'box_semitones_{index}').setValue(semi)
            getattr(self.ui, f'slider_pitch_{index}').setValue(cent)
            getattr(self.ui, f'lbl_pitch_{index}').setText(f'{cent} ct')

        # Initialize mod matrix.
        for destination in range(ModMap.MODD_LEN):
            for source in range(1, ModMap.MODS_LEN):
                box = self.matrix_layout.itemAtPosition(destination, source - 1).widget()
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

            self.voice_labels.append(label)

            count = self.ui.group_voices.layout().count()
            self.ui.group_voices.layout().insertLayout(count - 1, layout, 0) # Insert at the end but before spacer.


    def generate_mod_matrix(self):
        
        # Generate mod source labels.
        for name in list(ModMap.MODS_STRING_SHORT.values())[1:]:
            self.mods_labels_layout.addWidget(QLabel(name))

            # if name == list(ModMap.MODS_STRING_SHORT.values())[-1]:
            #     line = QFrame()
            #     line.setFrameShape(QFrame.VLine)
            #     self.mods_labels_layout.addWidget(line)

        # Generate mod destination labels 
        for name in ModMap.MODD_STRING_SHORT.values():
            label = QLabel(name)
            label.setMinimumHeight(15)
            self.modd_labels_layout.addWidget(label)

        # Generate checkboxes.
        for destination in range(ModMap.MODD_LEN):
            for source in range(ModMap.MODS_LEN - 1):
                box = QCheckBox('')
                box.setMinimumSize(35, 15)
                box.setMaximumSize(35, 15)
                self.matrix_layout.addWidget(box, destination, source)


    def generate_plot_select(self): 

        for name in list(ModMap.MODS_STRING.values())[1:]:
            layout = QHBoxLayout()
            layout.addWidget(QLabel(name))
            layout.addItem(QSpacerItem(40, 20, hPolicy=QSizePolicy.Expanding))
            button = QCheckBox()
            layout.addWidget(button)
            self.mods_plot_buttons.append(button)
            self.mods_plots_layout.addLayout(layout)

        self.mods_plots_layout.addItem(QSpacerItem(40, 20, vPolicy=QSizePolicy.Expanding))

        for name in ModMap.MODD_STRING.values():
            layout = QHBoxLayout()
            layout.addWidget(QLabel(name))
            layout.addItem(QSpacerItem(40, 20, hPolicy=QSizePolicy.Expanding))
            button = QCheckBox()
            layout.addWidget(button)
            self.modd_plot_buttons.append(button)
            self.modd_plots_layout.addLayout(layout)

        self.modd_plots_layout.addItem(QSpacerItem(40, 20, vPolicy=QSizePolicy.Expanding))
        

    # Create layout with radiobutton for each lfo. 
    # This is then placed in a layout which is the first element of the lfo_group groupbox.
    def generate_envelope_ui(self):

        layout = self.ui.group_envelope.layout().itemAt(0)

        for i in range(self.client.read(WaveArray.REG_ENVELOPE_N)):

            btn = QRadioButton(f'envelope {i}')
            btn.setChecked(i == 0)
            self.envelope_select_buttons.append(btn)
            
            item = QHBoxLayout()
            item.addWidget(btn)
            item.addStretch()
            
            layout.insertLayout(i, item)

    
    # Create layout with radiobutton for each lfo. 
    # This is then placed in a layout which is the first element of the lfo_group groupbox.
    def generate_lfo_ui(self):

        layout = self.ui.group_lfo.layout().itemAt(0)

        for i in range(self.client.read(WaveArray.REG_LFO_N)):

            btn = QRadioButton(f'LFO {i}')
            btn.setChecked(i == 0)
            self.lfo_select_buttons.append(btn)
            
            item = QHBoxLayout()
            item.addWidget(btn)
            item.addStretch()
            
            layout.insertLayout(i, item)


    def initialize_plots(self):

        bg_color = (0x3a, 0x3a, 0x3a)

        # Add callback to wavetable write when a table is dropped on the oscillator plots.
        self.ui.plot_waveform_0.addDropCallback(self.change_wavetable)
        self.ui.plot_waveform_1.addDropCallback(self.change_wavetable)

        self.ui.plot_waveform_0.setBackground(bg_color)
        self.ui.plot_waveform_0.setTitle('wavetable A')
        self.ui.plot_waveform_0.setYRange(-2**15, 2**15, padding=0)
        self.ui.plot_waveform_0.hideAxis('left')
        self.ui.plot_waveform_0.hideAxis('bottom')

        self.ui.plot_waveform_1.setBackground(bg_color)
        self.ui.plot_waveform_1.setTitle('wavetable B')
        self.ui.plot_waveform_1.setYRange(-2**15, 2**15, padding=0)
        self.ui.plot_waveform_1.hideAxis('left')
        self.ui.plot_waveform_1.hideAxis('bottom')

        self.ui.plot_oscilloscope.setBackground(bg_color)
        self.ui.plot_oscilloscope.setTitle('oscilloscope')
        self.ui.plot_oscilloscope.hideAxis('left')
        self.ui.plot_oscilloscope.hideAxis('bottom')

        # Generate mod destination plots.
        for name in ModMap.MODD_STRING.values():
            plot = DropPlotWidget(parent=self.ui.group_modd)
            plot.setBackground(bg_color)
            plot.setTitle(name)
            plot.setYRange(-2**15 - 1, 2**15, padding=0)
            plot.hideAxis('left')
            plot.hideAxis('bottom')
            self.ui.group_modd.layout().addWidget(plot, stretch=1)
            self.plots_modd.append(plot)
        
        # Generate mod source plots (skip MODS_NONE).
        for name in list(ModMap.MODS_STRING.values())[1:]:
            plot = DropPlotWidget(parent=self.ui.group_mods)
            plot.setBackground(bg_color)
            plot.setTitle(name)
            plot.setYRange(-2**15 - 1, 2**15, padding=0)
            plot.hideAxis('left')
            plot.hideAxis('bottom')
            self.ui.group_mods.layout().addWidget(plot, stretch=1)
            self.plots_mods.append(plot)

        self.plot_widgets = self.plots_modd + self.plots_mods

        color_map = pg.colormap.get('CET-C6')
        lut = color_map.getLookupTable(nPts=self.client.n_voices)
        # hue = random()

        # Generate curves and store PlotDataItem.     
        for i in range(self.client.n_voices):

            pen = pg.mkPen(color=lut[i])
            # pen = pg.mkPen(color=pg.hsvColor((hue + i / self.client.n_voices) % 1.0))

            if i == self.client.n_voices - 1:
                self.curve_oscilloscope = self.ui.plot_oscilloscope.plot(np.zeros(100), pen=pen)

            self.curves_waveforms[0][i] = self.ui.plot_waveform_0.plot(np.zeros(2048), name=f'voice {i}', pen=pen)
            self.curves_waveforms[1][i] = self.ui.plot_waveform_1.plot(np.zeros(2048), name=f'voice {i}', pen=pen)

            for j in range(len(ModMap.MODD_STRING)):
                self.curves_modd[j].append(self.plots_modd[j].plot(
                    self.curve_x, np.zeros(self.PLOT_SAMPLES), name=f'voice {i}', pen=pen))
                
            for j in range(len(ModMap.MODS_STRING) - 1):
                self.curves_mods[j].append(self.plots_mods[j].plot(
                    self.curve_x, np.zeros(self.PLOT_SAMPLES), name=f'voice {i}', pen=pen))
    

    def show(self):
        """ Re-implemented from QMainWindow. """
        self.ui.show()

    
    def load_wavetables(self):

        self.table_manager.load_from_flash()
        self.table_manager.read_table_descriptors()

        for descriptor in self.table_manager.descriptors.values():
            label = QListWidgetItem(descriptor.name)
            self.ui.list_tables.addItem(label)

        # Load first wavetable from list.
        self.change_wavetable(list(self.table_manager.descriptors.keys())[0], 0)
        self.change_wavetable(list(self.table_manager.descriptors.keys())[0], 1)

    
    # Load available stylesheet names from directory and add a menu item for each.
    def load_stylesheets(self):

        module_path = os.path.dirname(os.path.abspath(__file__))
        sheet_path  = os.path.join(module_path, '../../../qt')

        for filename in os.listdir(sheet_path):

            parts = filename.split('.')
            if len(parts) != 2:
                continue
            if parts[1] != 'qss':
                continue

            self.ui.menuAppearance.addAction(parts[0], self.appearanceActionClicked)

    
    def change_wavetable(self, table_name, index):

        descriptor = self.table_manager.descriptors[table_name]

        # Load wavetable from SDRAM if not already loaded
        if self.table_manager.tables[descriptor.name] == None:
            table = WaveTable.from_sdram(descriptor, self.client)
            self.table_manager.add_table(table)

        self.wavetables[index] = self.table_manager.tables[descriptor.name]

        # Update plot title.
        plot = self.ui.plot_waveform_0 if index == 0 else self.ui.plot_waveform_1
        osc_id = 'A' if index == 0 else 'B'
        plot.setTitle(f'{osc_id}: {descriptor.name} [{descriptor.n_frames_log2}]')

        # Update table registers.
        self.client.write(WaveArray.REG_TABLE_BASE + index * 0x10    , descriptor.base_address & 0xFFFF)
        self.client.write(WaveArray.REG_TABLE_BASE + index * 0x10 + 1, (descriptor.base_address >> 16) & 0xFFFF)
        self.client.write(WaveArray.REG_TABLE_BASE + index * 0x10 + 2, descriptor.n_frames_log2)
        self.client.write(WaveArray.REG_TABLE_BASE + index * 0x10 + 3, 0x0001)


    def mod_button_clicked(self, button, destination, source, state):

        self.logger.info(f'mod_button_clicked {state}')
        self.mod_source = source  
        self.mod_destination = destination
        self.mod_button = button

        # Update amount slider and text.
        try:
            amount = self.modmap.read_amount(destination, source)
        except MapException as e:
            amount = 0

        self.ui.slider_mod_amount.setValue(int(amount))  
        self.ui.lbl_mod_select.setText(
            f'{ModMap.MODS_STRING[source]}\n⇓\n{ModMap.MODD_STRING[destination]}')       

        # Add new mod mapping.
        if state:
            self.modmap.add_mapping(destination, source, 0)

        # dont allow de-checking the box. User must use button.
        else:
            button.setChecked(True)
            
    
    def btn_mod_disable_clicked(self):

        self.logger.info(f'btn_mod_disable_clicked {self.mod_button}')
        self.modmap.remove_mapping(self.mod_destination, self.mod_source)
        self.ui.slider_mod_amount.setValue(0)  
        self.mod_button.setChecked(False)


    def btn_mod_zero_clicked(self):
        
        self.logger.info(f'btn_mod_zero_clicked {self.mod_button}')
        self.ui.slider_mod_amount.setValue(0)  


    def pitch_changed(self, index):

        box_oct = getattr(self.ui, f'box_octaves_{index}')
        box_semi = getattr(self.ui, f'box_semitones_{index}')
        slider_cent = getattr(self.ui, f'slider_pitch_{index}')

        pitch_control = box_oct.value() * ModMap.MOD_FREQ_STEP_OCTAVE \
                                 + box_semi.value() * ModMap.MOD_FREQ_STEP_SEMITONE \
                                 + slider_cent.value() * ModMap.MOD_FREQ_STEP_CENT
        
        pitch_control = max(-2**15, min(2**15 - 1, pitch_control))
        
        self.client.write(WaveArray.REG_FREQ_CTRL_BASE + index, np.int16(pitch_control))

        getattr(self.ui, f'lbl_pitch_{index}').setText(f'{slider_cent.value()} ct')
        

    def btn_enable_hk_clicked(self, checked):
        self.client.write(WaveArray.REG_HK_ENABLE, int(checked))


    def btn_envelope_index_changed(self):

        # Find active envelope
        for i, btn in enumerate(self.envelope_select_buttons):
            if btn.isChecked():
                self.envelope_index = i 
                break 

        attack  = self.client.read(WaveArray.REG_ENVELOPE_CTRL_BASE + self.envelope_index * 0x10)
        decay   = self.client.read(WaveArray.REG_ENVELOPE_CTRL_BASE + self.envelope_index * 0x10 + 1)
        sustain = self.client.read(WaveArray.REG_ENVELOPE_CTRL_BASE + self.envelope_index * 0x10 + 2)
        release = self.client.read(WaveArray.REG_ENVELOPE_CTRL_BASE + self.envelope_index * 0x10 + 3)

        self.ui.slider_envelope_attack.setValue(attack) 
        self.ui.slider_envelope_decay.setValue(decay) 
        self.ui.slider_envelope_sustain.setValue(sustain)
        self.ui.slider_envelope_release.setValue(release) 
        
        # Call slots to update labels as well.
        self.envelope_attack_changed(attack)   
        self.envelope_decay_changed(decay)   
        self.envelope_sustain_changed(sustain)
        self.envelope_release_changed(release)   
        

    def btn_lfo_index_changed(self):

        # Find active LFO
        for i, btn in enumerate(self.lfo_select_buttons):
            if btn.isChecked():
                self.lfo_index = i 
                break 

        # Load settings.
        self.ui.btn_enable_lfo_trigger.setChecked(
            bool(self.client.read(WaveArray.REG_LFO_CTRL_BASE + self.lfo_index * 0x10 + 2)))
            
        self.ui.box_lfo_waveform.setCurrentIndex(
            self.client.read(WaveArray.REG_LFO_CTRL_BASE + self.lfo_index * 0x10 + 1))

        velocity = self.client.read(WaveArray.REG_LFO_CTRL_BASE + self.lfo_index * 0x10)
        phase = self.client.read(WaveArray.REG_LFO_CTRL_BASE + self.lfo_index * 0x10 + 3)
        amplitude = self.client.read(WaveArray.REG_LFO_CTRL_BASE + self.lfo_index * 0x10 + 6) 

        self.ui.slider_lfo_velocity.setValue(velocity)
        self.ui.slider_lfo_phase.setValue(phase)  
        self.ui.slider_lfo_amplitude.setValue(amplitude)       

        # Call slots to update labels as well.
        self.lfo_velocity_changed(velocity)   
        self.lfo_phase_changed(phase)    
        self.lfo_amplitude_changed(amplitude)    


    def noise_select_changed(self, index):
        self.client.write(WaveArray.REG_NOISE_SELECT, np.uint16(index));                               

    def btn_lfo_reset_clicked(self):
        self.client.write(WaveArray.REG_LFO_CTRL_BASE + self.lfo_index * 0x10 + 5, 1)

    def box_hk_rate_changed(self, rate):
        period = 100E6 / (1024 * rate)
        self.client.write(WaveArray.REG_HK_PERIOD, np.uint16(period))

    def box_midi_channel_changed(self, channel):
        self.client.write(WaveArray.REG_MIDI_CHANNEL, np.uint16(channel - 1))

    def box_unison_n_changed(self, n):
        assert n in range(1, 17)
        self.client.write(WaveArray.REG_UNISON_N, n - 1)

    def btn_enable_oscilloscope_clicked(self, checked):
        self.client.write(WaveArray.REG_WAVE_ENABLE, int(checked))

    def btn_enable_lfo_trigger_clicked(self, checked):
        self.client.write(WaveArray.REG_LFO_CTRL_BASE + self.lfo_index * 0x10 + 2, int(checked))   

        # Reset phases when trigger is deselected
        if not checked:
            self.client.write(WaveArray.REG_LFO_CTRL_BASE + self.lfo_index * 0x10 + 5, 1)

    def btn_reset_pitch_clicked(self, index):
        self.client.write(WaveArray.REG_FREQ_CTRL_BASE + index, 0)
        getattr(self.ui, f'box_octaves_{index}').setValue(0)
        getattr(self.ui, f'box_semitones_{index}').setValue(0)
        getattr(self.ui, f'slider_pitch_{index}').setValue(0)
        getattr(self.ui, f'lbl_pitch_{index}').setText('0 ct')

    def btn_enable_binaural_clicked(self, checked):
        self.client.write(WaveArray.REG_BINAURAL, int(checked))

    def box_oscilloscope_rate_changed(self, rate):
        period = 100E6 / (1024 * rate)
        self.client.write(WaveArray.REG_WAVE_PERIOD, np.uint16(period))

    def btn_reg_read_clicked(self):
        self.ui.box_reg_data.setValue(self.client.read(self.ui.box_reg_address.value()))

    def btn_reg_write_clicked(self):
        self.client.write(self.ui.box_reg_address.value(), self.ui.box_reg_data.value())

    def filter_select_changed(self, index):
        self.client.write(WaveArray.REG_FILTER_SELECT, index)

    def lfo_waveform_changed(self, waveform_index):
        self.client.write(WaveArray.REG_LFO_CTRL_BASE + self.lfo_index * 0x10 + 1, waveform_index)

    def set_mod_amount(self, control_value):

        # Reduce mod amount to frequency modulation to make it more usable. 
        # Except when the source is an oscillator.
        if (self.mod_destination in [ModMap.MODD_OSC_0_FREQ, ModMap.MODD_OSC_1_FREQ]
                and self.mod_source not in [ModMap.MODS_TABLE_0, ModMap.MODS_TABLE_1]):

            control_value = control_value >> 6

        self.modmap.write_amount(self.mod_destination, self.mod_source, control_value)

        if control_value <= 0:
            self.ui.lbl_amount.setText(f'{int(100 * control_value / (2**15 - 1)):3d}%')
        else:
            self.ui.lbl_amount.setText(f'{int(100 * control_value / 2**15):3d}%')

    def lfo_velocity_changed(self, control_value):
        self.client.write(WaveArray.REG_LFO_CTRL_BASE + self.lfo_index * 0x10, control_value)
        self.ui.lbl_velocity.setText(f'{int(100 * control_value / (2**15 - 1)):3d}%')

    def lfo_phase_changed(self, control_value):
        self.client.write(WaveArray.REG_LFO_CTRL_BASE + self.lfo_index * 0x10 + 3, control_value)
        self.ui.lbl_phase.setText(f'{int(100 * control_value / (2**15 - 1)):3d}%')

    def lfo_amplitude_changed(self, control_value):
        self.client.write(WaveArray.REG_LFO_CTRL_BASE + self.lfo_index * 0x10 + 6, control_value)
        self.ui.lbl_amplitude.setText(f'{int(100 * control_value / (2**15 - 1)):3d}%')

    def mix_amount_changed(self, index, control_value):
        self.client.write(WaveArray.REG_MIX_CTRL_BASE + index, control_value)
        lbl = getattr(self.ui, f'lbl_mix_{index}')
        lbl.setText(f'{int(100 * control_value / (2**15 - 1)):3d}%')

    def frame_position_changed(self, index, control_value):
        self.client.write(WaveArray.REG_FRAME_CTRL_BASE + index, control_value)
        lbl = getattr(self.ui, f'lbl_position_{index}')
        lbl.setText(f'{int(100 * control_value / (2**15 - 1)):3d}%')

    def unison_spread_changed(self, control_value):
        self.client.write(WaveArray.REG_UNISON_SPREAD, control_value)
        self.ui.lbl_spread.setText(f'{int(100 * control_value / (2**15 - 1)):3d}%')

    def filter_cutoff_changed(self, control_value):
        self.client.write(WaveArray.REG_FILTER_CUTOFF, control_value)
        self.ui.lbl_cutoff.setText(f'{int(100 * control_value / (2**15 - 1)):3d}%')
        
    def filter_resonance_changed(self, control_value):
        self.client.write(WaveArray.REG_FILTER_RESONANCE, control_value)
        self.ui.lbl_resonance.setText(f'{int(100 * control_value / (2**15 - 1)):3d}%')

    def envelope_attack_changed(self, control_value):
        self.client.write(WaveArray.REG_ENVELOPE_CTRL_BASE + 0x10 * self.envelope_index, control_value)
        self.ui.lbl_attack.setText(f'{int(100 * control_value / (2**15 - 1)):3d}%')
        
    def envelope_decay_changed(self, control_value):
        self.client.write(WaveArray.REG_ENVELOPE_CTRL_BASE + 0x10 * self.envelope_index + 1, control_value)
        self.ui.lbl_decay.setText(f'{int(100 * control_value / (2**15 - 1)):3d}%')

    def envelope_sustain_changed(self, control_value):
        self.client.write(WaveArray.REG_ENVELOPE_CTRL_BASE + 0x10 * self.envelope_index + 2, control_value)
        self.ui.lbl_sustain.setText(f'{int(100 * control_value / (2**15 - 1)):3d}%')

    def envelope_release_changed(self, control_value):
        self.client.write(WaveArray.REG_ENVELOPE_CTRL_BASE + 0x10 * self.envelope_index + 3, control_value)
        self.ui.lbl_release.setText(f'{int(100 * control_value / (2**15 - 1)):3d}%')

    def appearanceActionClicked(self):

        name = self.sender().text() + '.qss'
        module_path = os.path.dirname(os.path.abspath(__file__))
        style_path = os.path.join(module_path, '../../../qt/', name)

        with open(style_path) as f:

            self.application.setStyleSheet(f.read())
            # Set plot backgrounds to stylesheet background color.

        section = False
        color = (20, 20, 20)
        color_string = None

        # Extract background color from stylesheet and use it as plot background.
        with open(style_path) as f:
            for line in f:

                if not section and line == 'QWidget\n':
                    section = True
                
                if section:

                    if line == '}\n':
                        break 

                    if 'background-color' in line:
                        color_string = line.split(':')[1].strip().strip(';')
                        
                        if color_string[0] != '#':
                            break 

                        raw_color = int(color_string[1:7], 16)
                        print(hex(raw_color))
                        color = ((raw_color >> 16) % 0x100, (raw_color >> 8) % 0x100, raw_color % 0x100)
                        break
            
        if color:
            for plot in self.plot_widgets:
                plot.setBackground(color)

        
def main():

    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger()
    
    gui = None
    application = QApplication(sys.argv)

    # Set stylesheet 
    module_path = os.path.dirname(os.path.abspath(__file__))
    style_dir = os.path.join(module_path, '../../../qt/')

    with open(style_dir + 'Combinear.qss') as f:
        application.setStyleSheet(f.read())

    gui = WaveArrayGui(application)
    gui.show()
    application.exec_()

    # try:
    #     gui = WaveArrayGui(application)
    #     gui.show()
    #     application.exec_()

    # except Exception as e:
    #     logger.error(e)
    #     if gui:
    #         gui.client.stop()
    #     os._exit(1)
    #     raise e

    # else:
    #     if gui:
    #         gui.client.stop()
    #     os._exit(1)


if __name__ == "__main__":
    main()
