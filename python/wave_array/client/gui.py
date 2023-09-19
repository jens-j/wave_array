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
                                     QSizePolicy, QListWidgetItem, QCheckBox
from PyQt5.QtGui              import QIntValidator


from wave_array.client.client import WaveArray
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
        
        self.mod_source = None 
        self.mod_destination = None
        self.modmap = ModMap(self.client)
        self.wavetables = [WaveTable(), WaveTable()]
        self.status = Status(self.client)
        self.oscilloscope_samples = np.zeros(100, dtype=np.int16)
        self.voice_enabled_buttons = []
        self.voice_active_buttons = []
        self.mod_layout = None

        self.curve_oscilloscope = None
        self.curves_waveforms = [[None] * self.client.n_voices, [None] * self.client.n_voices]
        self.curve_pot = [None]
        self.curves_lfo = [None] * self.client.n_voices
        self.curves_envelope = [None] * self.client.n_voices
        self.curves_cutoff = [None] * self.client.n_voices
        self.curves_resonance = [None] * self.client.n_voices
        self.curves_frame_0 = [None] * self.client.n_voices
        self.curves_frame_1 = [None] * self.client.n_voices
        self.curves_mix_0 = [None] * self.client.n_voices
        self.curves_mix_1 = [None] * self.client.n_voices
        self.curves_volume = [None] * self.client.n_voices
        self.curve_x = np.arange(0, self.PLOT_T, self.PLOT_T / self.PLOT_SAMPLES)[::-1] # Constant used for plotting.

        module_path = os.path.dirname(os.path.abspath(__file__))
        self.table_dir = os.path.join(module_path, '../../../data/wavetables/')

        self.t_hk = time()
        self.t_plot = time()

        # Initialize the GUI.
        module_path = os.path.dirname(os.path.abspath(__file__))
        ui_path     = os.path.join(module_path, '../../../qt')
        self.ui     = uic.loadUi(os.path.join(ui_path, 'wavearray.ui'))

        self.generate_voice_ui()
        self.generate_mod_matrix()
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
        
        self.ui.btn_reg_read.released.connect(self.btn_reg_read_clicked)
        self.ui.btn_reg_write.released.connect(self.btn_reg_write_clicked)
        self.ui.btn_reset_pitch_0.released.connect(partial(self.btn_reset_pitch_clicked, 0))
        self.ui.btn_reset_pitch_1.released.connect(partial(self.btn_reset_pitch_clicked, 1))

        self.ui.box_unison.valueChanged.connect(self.box_unison_n_changed)
        self.ui.box_hk_rate.valueChanged.connect(self.box_hk_rate_changed)
        self.ui.box_oscilloscope_rate.valueChanged.connect(self.box_oscilloscope_rate_changed)
        self.ui.box_filter_select.currentIndexChanged.connect(self.filter_select_changed)
        self.ui.box_lfo_waveform.currentIndexChanged.connect(self.lfo_waveform_changed)
        self.ui.box_octaves_0.valueChanged.connect(partial(self.pitch_changed, 0))
        self.ui.box_octaves_1.valueChanged.connect(partial(self.pitch_changed, 1))
        self.ui.box_semitones_0.valueChanged.connect(partial(self.pitch_changed, 0))
        self.ui.box_semitones_1.valueChanged.connect(partial(self.pitch_changed, 1))

        self.ui.action_load_config.triggered.connect(self.load_config)
        self.ui.action_reset.triggered.connect(self.software_reset)

        self.ui.slider_mix_0_position.sliderMoved.connect(partial(self.mix_amount_changed, 0))
        self.ui.slider_mix_1_position.sliderMoved.connect(partial(self.mix_amount_changed, 1))
        self.ui.slider_frame_0_position.sliderMoved.connect(partial(self.frame_position_changed, 0))
        self.ui.slider_frame_1_position.sliderMoved.connect(partial(self.frame_position_changed, 1))
        self.ui.slider_pitch_0.sliderMoved.connect(partial(self.pitch_changed, 0))
        self.ui.slider_pitch_1.sliderMoved.connect(partial(self.pitch_changed, 1))
        self.ui.slider_unison_spread.sliderMoved.connect(self.unison_spread_changed)
        self.ui.slider_lfo_velocity.sliderMoved.connect(self.lfo_velocity_changed)
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
            self.logger.info(f'wave packet [{len(data)} / {length}]')
            self.oscilloscope_samples = data

                    
    def update_plots(self):
        
        t = time()
        # self.logger.info(f'plot T = {(t - self.t_plot)}')
        self.t_plot = t

        self.ui.lbl_voice_enabled.setText(f'0x{self.status.voice_enabled:04X}')
        self.ui.lbl_voice_active.setText(f'0x{self.status.voice_active:04X}')
        self.ui.lbl_polyphony.setText(f'{self.status.polyphony:04X}')
        self.ui.lbl_active_oscillators.setText(f'{self.status.active_oscillators:04X}')

        # Set voice leds.
        for i in range(self.client.n_voices):
            self.voice_enabled_buttons[i].setChecked(bool(self.status.voice_enabled & (1 << i)))
            self.voice_active_buttons[i].setChecked(bool(self.status.voice_active & (1 << i)))

            # Grey out any unused voices in current configuration.
            if i < self.status.polyphony:
                self.voice_enabled_buttons[i].show()
                self.voice_active_buttons[i].show()
            else:
                self.voice_enabled_buttons[i].hide()
                self.voice_active_buttons[i].hide()

        self.curve_oscilloscope.setData(self.oscilloscope_samples)

        self.curve_pot.setData(self.curve_x, np.concatenate(
            (self.curve_pot.getData()[1][1:], [self.status.mod_sources[ModMap.MODS_POT][i]])))
        
        for i in range(self.client.n_voices):

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

            self.curves_mix_0[i].setData(self.curve_x, np.concatenate(
                (self.curves_mix_0[i].getData()[1][1:], [self.status.mod_destinations[ModMap.MODD_OSC_0_MIX][i]])))

            self.curves_mix_1[i].setData(self.curve_x, np.concatenate(
                (self.curves_mix_1[i].getData()[1][1:], [self.status.mod_destinations[ModMap.MODD_OSC_1_MIX][i]])))

            self.curves_volume[i].setData(self.curve_x, np.concatenate(
                (self.curves_volume[i].getData()[1][1:], [self.status.mod_destinations[ModMap.MODD_VOLUME][i]])))
            
            # Don't show curves for unused polyphonic voices.
            for curves in self.modd_curves:
                
                if i < self.status.polyphony:
                    curves[i].show()
                else:
                    curves[i].hide()
                
            # Update both wavetable plots.
            for j in range(2):

                wavetable = self.wavetables[j]
                dest = ModMap.MODD_OSC_0_FRAME if j == 0 else ModMap.MODD_OSC_1_FRAME

                # Skip uninitialized wavetables.
                if wavetable.n_frames == 0:
                    continue
            
                # Set waveform plot data.
                if wavetable.n_frames_log2 == 0:
                    self.curves_waveforms[j][i].setData(wavetable.frames[0])

                # Interpolate between frames 0 and 1.
                elif wavetable.n_frames_log2 == 1: 
                    self.curves_waveforms[j][i].setData(wavetable.frames[0] + np.int16(
                        self.status.mod_destinations[dest][i] 
                        * np.int32(wavetable.frames[1] - wavetable.frames[0]) // 2**15))

                # interpolate between frames a and b.
                else:
                    index_a = 2**wavetable.n_frames_log2 * max(0, self.status.mod_destinations[dest][i]) // 2**15 
                    index_b = min(index_a + 1, 2**wavetable.n_frames_log2 - 1)
                    d = max(0, self.status.mod_destinations[dest][i]) % 2**(15 - wavetable.n_frames_log2)
                    d_max = 2**(15 - wavetable.n_frames_log2) - 1
                    
                    self.curves_waveforms[j][i].setData(wavetable.frames[index_a] 
                        + np.int16(d * np.int32(wavetable.frames[index_b] - wavetable.frames[index_a]) // d_max))     


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

        enabled = self.client.read(WaveArray.REG_WAVE_ENABLE)
        self.ui.btn_enable_oscilloscope.setChecked(enabled)

        enabled = self.client.read(WaveArray.REG_LFO_TRIGGER)
        self.ui.btn_enable_lfo_trigger.setChecked(enabled)

        period = self.client.read(WaveArray.REG_WAVE_PERIOD)
        rate = 100E6 / (period * 1024)
        self.ui.box_oscilloscope_rate.setValue(int(rate))
    
        index = self.client.read(WaveArray.REG_FILTER_SELECT)
        self.ui.box_filter_select.setCurrentIndex(index)

        index = self.client.read(WaveArray.REG_LFO_WAVE)
        self.ui.box_lfo_waveform.setCurrentIndex(index)

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

        position = self.client.read(WaveArray.REG_FRAME_CTRL_BASE)
        self.ui.slider_frame_0_position.setValue(position)
        self.frame_position_changed(0, position)

        position = self.client.read(WaveArray.REG_FRAME_CTRL_BASE + 1)
        self.ui.slider_frame_1_position.setValue(position)
        self.frame_position_changed(1, position)

        frequency = self.client.read(WaveArray.REG_FREQ_CTRL_BASE)
        self.ui.slider_pitch_0.setValue(frequency)
        self.frame_position_changed(0, frequency)

        frequency = self.client.read(WaveArray.REG_FREQ_CTRL_BASE + 1)
        self.ui.slider_pitch_1.setValue(frequency)
        self.frame_position_changed(1, frequency)

        spread = self.client.read(WaveArray.REG_UNISON_SPREAD)
        self.ui.slider_unison_spread.setValue(spread)
        self.unison_spread_changed(spread)

        velocity = self.client.read(WaveArray.REG_LFO_VELOCITY)
        self.ui.slider_lfo_velocity.setValue(velocity)
        self.lfo_velocity_changed(velocity)

        cutoff = self.client.read(WaveArray.REG_FILTER_CUTOFF)
        self.ui.slider_filter_cutoff.setValue(cutoff)
        self.filter_cutoff_changed(cutoff)

        resonance = self.client.read(WaveArray.REG_FILTER_RESONANCE)
        self.ui.slider_filter_resonance.setValue(resonance)
        self.filter_resonance_changed(resonance)

        attack = self.client.read(WaveArray.REG_ENVELOPE_ATTACK)
        self.ui.slider_envelope_attack.setValue(attack)
        self.envelope_attack_changed(attack)

        decay = self.client.read(WaveArray.REG_ENVELOPE_DECAY)
        self.ui.slider_envelope_decay.setValue(decay)
        self.envelope_decay_changed(decay)

        sustain = self.client.read(WaveArray.REG_ENVELOPE_SUSTAIN)
        self.ui.slider_envelope_sustain.setValue(sustain)
        self.envelope_sustain_changed(sustain)

        release = self.client.read(WaveArray.REG_ENVELOPE_RELEASE)
        self.ui.slider_envelope_release.setValue(release)  
        self.envelope_release_changed(release)

        # Initialize pitch control.
        for index in range(2):

            pitch_control = self.client.read(WaveArray.REG_FREQ_CTRL_BASE + index)

            oct = int(np.round(pitch_control / ModMap.MOD_FREQ_STEP_OCTAVE))
            semi = int(np.fmod(pitch_control, ModMap.MOD_FREQ_STEP_OCTAVE) / ModMap.MOD_FREQ_STEP_SEMITONE)
            cent = int(np.fmod(pitch_control, ModMap.MOD_FREQ_STEP_SEMITONE) / ModMap.MOD_FREQ_STEP_CENT)
            
            getattr(self.ui, f'box_octaves_{index}').setValue(oct)
            getattr(self.ui, f'box_semitones_{index}').setValue(semi)
            getattr(self.ui, f'slider_pitch_{index}').setValue(cent)

        # Initialize mod matrix.
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

            count = self.ui.group_voices.layout().count()
            self.ui.group_voices.layout().insertLayout(count - 1, layout, 0) # Insert at the end but before spacer.

        # self.ui.group_voices.layout().addItem(QSpacerItem(20, 40, QSizePolicy.Minimum, QSizePolicy.Expanding))

    def generate_mod_matrix(self):

        self.mod_layout = self.ui.group_mod_matrix.layout().children()[1].children()[-1] # .layout_matrix_col.layout_mod_matrix

        for destination in range(ModMap.MODD_LEN):
            for source in range(ModMap.MODS_LEN - 1):
                box = QCheckBox('')
                self.mod_layout.addWidget(box, destination, source)


    def initialize_plots(self):

        bg_color = (0x3a, 0x3a, 0x3a)

        # Add callback to wavetable write when a table is dropped on the oscillator plots.
        self.ui.plot_waveform_0.addDropCallback(self.write_wavetable)
        self.ui.plot_waveform_1.addDropCallback(self.write_wavetable)
        
        self.ui.plot_cutoff.setBackground(bg_color)
        self.ui.plot_cutoff.setTitle('filter cutoff')
        self.ui.plot_cutoff.setYRange(-1, 2**15, padding=0)
        self.ui.plot_cutoff.hideAxis('left')
        self.ui.plot_cutoff.hideAxis('bottom')

        self.ui.plot_resonance.setBackground(bg_color)
        self.ui.plot_resonance.setTitle('filter resonance')
        self.ui.plot_resonance.setYRange(-1, 2**15, padding=0)
        self.ui.plot_resonance.hideAxis('left')
        self.ui.plot_resonance.hideAxis('bottom')

        self.ui.plot_frame_0.setBackground(bg_color)
        self.ui.plot_frame_0.setTitle('wavetable A frame')
        self.ui.plot_frame_0.setYRange(-1, 2**15, padding=0)
        self.ui.plot_frame_0.hideAxis('left')
        self.ui.plot_frame_0.hideAxis('bottom')

        self.ui.plot_frame_1.setBackground(bg_color)
        self.ui.plot_frame_1.setTitle('wavetable B frame')
        self.ui.plot_frame_1.setYRange(-1, 2**15, padding=0)
        self.ui.plot_frame_1.hideAxis('left')
        self.ui.plot_frame_1.hideAxis('bottom')

        self.ui.plot_mix_0.setBackground(bg_color)
        self.ui.plot_mix_0.setTitle('wavetable A mix')
        self.ui.plot_mix_0.setYRange(-1, 2**15, padding=0)
        self.ui.plot_mix_0.hideAxis('left')
        self.ui.plot_mix_0.hideAxis('bottom')

        self.ui.plot_mix_1.setBackground(bg_color)
        self.ui.plot_mix_1.setTitle('wavetable B mix')
        self.ui.plot_mix_1.setYRange(-1, 2**15, padding=0)
        self.ui.plot_mix_1.hideAxis('left')
        self.ui.plot_mix_1.hideAxis('bottom')

        self.ui.plot_volume.setBackground(bg_color)
        self.ui.plot_volume.setTitle('volume')
        self.ui.plot_volume.setYRange(-1, 2**15, padding=0)
        self.ui.plot_volume.hideAxis('left')
        self.ui.plot_volume.hideAxis('bottom')
        
        self.ui.plot_pot.setBackground(bg_color)
        self.ui.plot_pot.setTitle('potentiometer')
        self.ui.plot_pot.setYRange(-1, 2**15, padding=0)
        self.ui.plot_pot.hideAxis('left')
        self.ui.plot_pot.hideAxis('bottom')

        self.ui.plot_envelope.setBackground(bg_color)
        self.ui.plot_envelope.setTitle('envelope')
        self.ui.plot_envelope.setYRange(-1, 2**15, padding=0)
        self.ui.plot_envelope.hideAxis('left')
        self.ui.plot_envelope.hideAxis('bottom')

        self.ui.plot_lfo.setBackground(bg_color)
        self.ui.plot_lfo.setTitle('LFO')
        self.ui.plot_lfo.setYRange(-2**15, 2**15, padding=0)
        self.ui.plot_lfo.hideAxis('left')
        self.ui.plot_lfo.hideAxis('bottom')

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
        # self.ui.plot_oscilloscope.setYRange(-2**15, 2**15, padding=0)

        self.plot_widgets = [self.ui.plot_waveform_0, self.ui.plot_cutoff, self.ui.plot_resonance, self.ui.plot_frame_0, 
                             self.ui.plot_frame_1, self.ui.plot_mix_0, self.ui.plot_mix_1, self.ui.plot_volume, 
                             self.ui.plot_pot, self.ui.plot_envelope, self.ui.plot_lfo, self.ui.plot_waveform_0, 
                             self.ui.plot_waveform_1, self.ui.plot_oscilloscope]

        hue = random()

        # Plot curves and store PlotDataItem.     
        for i in range(self.client.n_voices):

            pen = pg.mkPen(color=pg.hsvColor((hue + i / self.client.n_voices) % 1.0))

            if i == 0:
                self.curve_pot = self.ui.plot_pot.plot(
                    self.curve_x, np.zeros(self.PLOT_SAMPLES), name=f'voice {i}', pen=pen)

            if i == self.client.n_voices - 1:
                self.curve_oscilloscope = self.ui.plot_oscilloscope.plot(np.zeros(100), pen=pen)

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

            self.curves_mix_0[i] = self.ui.plot_mix_0.plot(
                self.curve_x, np.zeros(self.PLOT_SAMPLES), name=f'voice {i}', pen=pen)

            self.curves_mix_1[i] = self.ui.plot_mix_1.plot(
                self.curve_x, np.zeros(self.PLOT_SAMPLES), name=f'voice {i}', pen=pen)

            self.curves_volume[i] = self.ui.plot_volume.plot(
                self.curve_x, np.zeros(self.PLOT_SAMPLES), name=f'voice {i}', pen=pen)

            self.curves_waveforms[0][i] = self.ui.plot_waveform_0.plot(np.zeros(2048), name=f'voice {i}', pen=pen)
            self.curves_waveforms[1][i] = self.ui.plot_waveform_1.plot(np.zeros(2048), name=f'voice {i}', pen=pen)

        self.modd_curves = [self.curves_envelope, self.curves_lfo, self.curves_cutoff, self.curves_resonance, 
                            self.curves_frame_0, self.curves_frame_1, self.curves_mix_0, self.curves_mix_1, 
                            self.curves_volume]


    def show(self):
        """ Re-implemented from QMainWindow. """
        self.ui.show()

    
    def load_wavetables(self):

        module_path = os.path.dirname(os.path.abspath(__file__))
        table_path  = os.path.join(module_path, '../../../data/wavetables')

        for filename in os.listdir(self.table_dir):

            parts = filename.split('.')

            if len(parts) > 2:
                self.logger.warning(f'Illegal wavetable file name {filename}')

            elif parts[1] != 'table':
                self.logger.warning(f'Wavetable file name has wrong extension {filename}')

            else:
                label = QListWidgetItem(parts[0])
                self.ui.list_tables.addItem(label)

    
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


    # Write a wavetable to the SDRAM. Currently only one wavetable is stored in SDRAM per oscillator.
    def write_wavetable(self, table_name, index):

        self.logger.info(f'Write table [{index}] <= \"{table_name}\"')

        filepath = self.table_dir + table_name + '.table'

        with open(filepath, 'r') as f:
            raw_data = f.read().split('\n')

        raw_data = list(filter(lambda x: x != '', raw_data))
        data = np.array([int(x, 16) for x in raw_data]).astype('int16')
        frames = len(data) // 4096
        frames_log2 = np.uint16(np.log2(frames))
        address = 0x0000_0000 if index == 0 else 0x0001_0000
        offset = 0 if index == 0 else 4

        # Write table to sdram.
        self.client.write_sdram(0, data)

        # Update table registers.
        self.client.write(WaveArray.REG_TABLE_BASE + offset    , (address >> 16) & 0xFFFF)
        self.client.write(WaveArray.REG_TABLE_BASE + offset + 1, address & 0xFFFF)
        self.client.write(WaveArray.REG_TABLE_BASE + offset + 2, frames_log2)
        self.client.write(WaveArray.REG_TABLE_BASE + offset + 3, 0x0001)

        # Update Wavetable object
        self.wavetables[index].initialize(data)

        # Update plot title.
        plot = self.ui.plot_waveform_0 if index == 0 else self.ui.plot_waveform_1
        name = 'A' if index == 0 else 'B'
        plot.setTitle(f'{name}: {table_name} [{frames}]')


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
            f'{ModMap.MODS[source]}\n⇓\n{ModMap.MODD[destination]}')       

        # Add new mod mapping.
        if state:
            self.modmap.add_mapping(destination, source, 0)

        # remove mod mapping.
        else:
            self.modmap.remove_mapping(destination, source)

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

    def box_hk_rate_changed(self, rate):
        period = 100E6 / (1024 * rate)
        self.client.write(WaveArray.REG_HK_PERIOD, np.uint16(period))

    def box_unison_n_changed(self, n):
        assert n in range(1, 17)
        self.client.write(WaveArray.REG_UNISON_N, n - 1)

    def btn_enable_oscilloscope_clicked(self, checked):
        self.client.write(WaveArray.REG_WAVE_ENABLE, int(checked))

    def btn_enable_lfo_trigger_clicked(self, checked):
        self.client.write(WaveArray.REG_LFO_TRIGGER, int(checked))   

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

    def lfo_waveform_changed(self, index):
        self.client.write(WaveArray.REG_LFO_WAVE, index)

    def set_mod_amount(self, control_value):
        self.modmap.write_amount(self.mod_destination, self.mod_source, control_value)

        if control_value <= 0:
            self.ui.lbl_amount.setText(f'{int(100 * control_value / (2**15 - 1)):3d}%')
        else:
            self.ui.lbl_amount.setText(f'{int(100 * control_value / 2**15):3d}%')

    def lfo_velocity_changed(self, control_value):
        self.client.write(WaveArray.REG_LFO_VELOCITY, control_value)
        self.ui.lbl_velocity.setText(f'{int(100 * control_value / (2**15 - 1)):3d}%')

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
        self.client.write(WaveArray.REG_ENVELOPE_ATTACK, control_value)
        self.ui.lbl_attack.setText(f'{int(100 * control_value / (2**15 - 1)):3d}%')
        
    def envelope_decay_changed(self, control_value):
        self.client.write(WaveArray.REG_ENVELOPE_DECAY, control_value)
        self.ui.lbl_decay.setText(f'{int(100 * control_value / (2**15 - 1)):3d}%')

    def envelope_sustain_changed(self, control_value):
        self.client.write(WaveArray.REG_ENVELOPE_SUSTAIN, control_value)
        self.ui.lbl_sustain.setText(f'{int(100 * control_value / (2**15 - 1)):3d}%')

    def envelope_release_changed(self, control_value):
        self.client.write(WaveArray.REG_ENVELOPE_RELEASE, control_value)
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

    try:
        gui = WaveArrayGui(application)
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
