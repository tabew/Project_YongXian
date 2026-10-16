"""程序化占位音效生成器。

用法：python tools/generate_sfx.py
产物：assets/audio/sfx/*.wav（44.1kHz 单声道 16bit）与 assets/audio/music/*.wav（22.05kHz）。
全部音效由噪声、振荡器和包络合成，不依赖任何外部素材或音源库，
方便在拿到正式音频前先把播放链路跑通。文件名即 AudioManager 里使用的音效 id。

换成正式素材时直接覆盖同名文件即可，不需要改任何脚本。
"""

import math
import os
import sys
import wave

import numpy as np

SFX_RATE = 44100
MUSIC_RATE = 22050
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SFX_DIR = os.path.join(PROJECT_ROOT, "assets", "audio", "sfx")
MUSIC_DIR = os.path.join(PROJECT_ROOT, "assets", "audio", "music")


# --- 基础工具 ---------------------------------------------------------------


def rng(seed):
    return np.random.default_rng(seed)


def noise(n, seed):
    return rng(seed).normal(0.0, 1.0, n)


def lowpass(signal, cutoff, rate):
    """一阶低通；cutoff 可以是标量，也可以是逐样本曲线。"""
    a = 1.0 - np.exp(-2.0 * math.pi * np.maximum(cutoff, 20.0) / rate)
    if np.isscalar(cutoff):
        a = float(a)
    out = np.empty(signal.size, dtype=np.float64)
    y = 0.0
    for i in range(signal.size):
        y += (a if np.isscalar(a) else a[i]) * (signal[i] - y)
        out[i] = y
    return out


def highpass(signal, cutoff, rate):
    return signal - lowpass(signal, cutoff, rate)


def dc_block(signal, rate, cutoff=25.0):
    """二阶高通：去掉直流偏移与次声隆隆。

    衰减正弦的第一个正半周占主导，会让整段素材带上明显的直流分量——
    既浪费动态余量，又会在起止处产生"噗"声。25Hz 以下人耳听不到，直接切掉。
    """
    return highpass(highpass(signal, cutoff, rate), cutoff, rate)


def bell(t, center, width):
    return np.exp(-0.5 * ((t - center) / max(width, 1e-4)) ** 2)


def exp_decay(n, rate, attack, tau):
    t = np.arange(n) / rate
    env = np.exp(-np.maximum(t - attack, 0.0) / max(tau, 1e-4))
    a = max(int(attack * rate), 1)
    if a > 1:
        env[:a] *= np.linspace(0.0, 1.0, a)
    return env


def phase(freq, rate, n):
    """返回长度为 n 的相位序列。

    频率是标量时必须展开成 n 个采样：np.cumsum 对标量只返回 1 个元素，
    那样波形会退化成常量（直流 + 包络），听起来是隆隆声而不是乐音。
    """
    freq = np.asarray(freq, dtype=np.float64)
    if freq.ndim == 0:
        freq = np.full(n, float(freq))
    elif freq.size != n:
        raise ValueError("频率序列长度 %d 与目标长度 %d 不一致" % (freq.size, n))
    return np.cumsum(2.0 * math.pi * freq / rate)


def sine(freq, rate, n):
    return np.sin(phase(freq, rate, n))


def saw(freq, rate, n):
    p = phase(freq, rate, n) / (2.0 * math.pi)
    return 2.0 * (p - np.floor(p + 0.5))


def square(freq, rate, n, duty=0.5):
    p = (phase(freq, rate, n) / (2.0 * math.pi)) % 1.0
    return np.where(p < duty, 1.0, -1.0)


def ramp(n, start, end):
    return np.linspace(start, end, n)


def t_of(n, rate):
    return np.arange(n) / rate


def mix(*layers):
    size = max(layer.size for layer in layers)
    total = np.zeros(size, dtype=np.float64)
    for layer in layers:
        total[: layer.size] += layer
    return total


def pad_to(signal, n):
    out = np.zeros(n, dtype=np.float64)
    out[: min(signal.size, n)] = signal[: min(signal.size, n)]
    return out


def normalize(signal, peak_db=-3.0):
    peak = float(np.max(np.abs(signal))) if signal.size else 0.0
    if peak <= 1e-9:
        return signal
    return signal / peak * (10.0 ** (peak_db / 20.0))


def write_wav(path, signal, rate, peak_db=-3.0, fade=0.005):
    data = normalize(dc_block(np.asarray(signal, dtype=np.float64), rate), peak_db)
    edge = min(int(fade * rate), max(data.size // 2, 0))
    if edge > 0:
        data[:edge] *= np.linspace(0.0, 1.0, edge)
        data[-edge:] *= np.linspace(1.0, 0.0, edge)
    pcm = (np.clip(data, -1.0, 1.0) * 32767.0).astype("<i2")
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(rate)
        handle.writeframes(pcm.tobytes())
    print("  %-22s %6.0f ms  %6.1f KB" % (
        os.path.basename(path),
        data.size / rate * 1000.0,
        os.path.getsize(path) / 1024.0,
    ))


def make_seamless(signal, rate, fade_seconds):
    """把尾巴交叉淡入到开头，使循环播放时听不出接缝。"""
    fade = int(fade_seconds * rate)
    if fade * 2 >= signal.size:
        return signal
    length = signal.size - fade
    out = signal[:length].copy()
    blend = np.linspace(0.0, 1.0, fade)
    out[:fade] = signal[:fade] * blend + signal[length : length + fade] * (1.0 - blend)
    return out


# --- 音效 -------------------------------------------------------------------


def whoosh(duration, low, high, center, seed, body=0.0):
    """气声挥砍：噪声 + 随时间推移的带通，振幅成钟形。"""
    n = int(duration * SFX_RATE)
    t = t_of(n, SFX_RATE)
    src = noise(n, seed)
    curve = low + (high - low) * bell(t, center, duration * 0.30)
    shaped = lowpass(highpass(src, low * 0.6, SFX_RATE), curve, SFX_RATE)
    amp = bell(t, center, duration * 0.34)
    out = shaped * amp
    if body > 0.0:
        tone = sine(low * 0.5 + (high * 0.2 - low * 0.5) * bell(t, center, duration * 0.30), SFX_RATE, n)
        out = out + tone * amp * body
    return out


def thud(duration, start_freq, end_freq, tau, seed, crack=0.0):
    """闷击：低频下滑正弦 + 短噪声。"""
    n = int(duration * SFX_RATE)
    t = t_of(n, SFX_RATE)
    freq = start_freq + (end_freq - start_freq) * (t / max(duration, 1e-4))
    body = sine(freq, SFX_RATE, n) * exp_decay(n, SFX_RATE, 0.002, tau)
    out = body
    if crack > 0.0:
        burst = lowpass(noise(n, seed), 3500.0, SFX_RATE) * exp_decay(n, SFX_RATE, 0.0, tau * 0.35)
        out = out + burst * crack
    return out


def impact(seed, ring_freqs=(), ring_tau=0.05, ring_gain=0.0, **thud_args):
    out = thud(seed=seed, **thud_args)
    for index, freq in enumerate(ring_freqs):
        n = out.size
        ring = sine(freq, SFX_RATE, n) * exp_decay(n, SFX_RATE, 0.001, ring_tau)
        out = out + ring * ring_gain * (1.0 - 0.25 * index)
    return out


def build_swing_longsword():
    return whoosh(0.34, 320.0, 2600.0, 0.13, 11, body=0.10)


def build_swing_spear():
    return whoosh(0.14, 1000.0, 3800.0, 0.05, 12, body=0.04)


def build_swing_yoyo():
    n = int(0.26 * SFX_RATE)
    t = t_of(n, SFX_RATE)
    whip = sine(900.0 + 2200.0 * bell(t, 0.03, 0.02), SFX_RATE, n) * exp_decay(n, SFX_RATE, 0.001, 0.035)
    return mix(whoosh(0.26, 900.0, 2800.0, 0.09, 13, body=0.05), whip * 0.35)


def build_swing_generic():
    return whoosh(0.28, 450.0, 2400.0, 0.10, 15, body=0.08)


def build_hit_flesh():
    return impact(21, start_freq=170.0, end_freq=62.0, tau=0.055, crack=0.55,
                  ring_freqs=(196.0,), ring_tau=0.03, ring_gain=0.12, duration=0.20)


def build_hit_critical():
    return impact(22, start_freq=210.0, end_freq=70.0, tau=0.07, crack=0.70,
                  ring_freqs=(1760.0, 2640.0, 3520.0), ring_tau=0.13, ring_gain=0.22,
                  duration=0.30)


def build_hit_wood():
    return impact(23, start_freq=330.0, end_freq=150.0, tau=0.045, crack=0.45,
                  ring_freqs=(392.0, 587.0), ring_tau=0.045, ring_gain=0.30,
                  duration=0.18)


def build_hit_stone():
    n = int(0.20 * SFX_RATE)
    clack = lowpass(noise(n, 24), 2600.0, SFX_RATE) * exp_decay(n, SFX_RATE, 0.0, 0.022)
    return impact(25, start_freq=240.0, end_freq=110.0, tau=0.035, crack=0.0,
                  ring_freqs=(1150.0,), ring_tau=0.05, ring_gain=0.35, duration=0.20) + clack * 0.5


def build_monster_hurt():
    n = int(0.22 * SFX_RATE)
    t = t_of(n, SFX_RATE)
    freq = 430.0 - 250.0 * (t / 0.22)
    voice = lowpass(saw(freq, SFX_RATE, n), 2200.0, SFX_RATE) * exp_decay(n, SFX_RATE, 0.004, 0.055)
    grit = lowpass(noise(n, 31), 1800.0, SFX_RATE) * exp_decay(n, SFX_RATE, 0.0, 0.030)
    return voice * 0.75 + grit * 0.30


def build_monster_die():
    n = int(0.60 * SFX_RATE)
    t = t_of(n, SFX_RATE)
    freq = 390.0 - 300.0 * (t / 0.60) + 18.0 * np.sin(2.0 * math.pi * 17.0 * t)
    voice = lowpass(saw(freq, SFX_RATE, n), 1600.0, SFX_RATE) * exp_decay(n, SFX_RATE, 0.006, 0.16)
    landing = thud(duration=0.30, start_freq=120.0, end_freq=48.0, tau=0.06, seed=33, crack=0.35)
    return voice * 0.85 + pad_to(landing, n) * 0.55


def build_player_hurt():
    n = int(0.32 * SFX_RATE)
    t = t_of(n, SFX_RATE)
    freq = 300.0 - 170.0 * (t / 0.32)
    voice = sine(freq, SFX_RATE, n) * exp_decay(n, SFX_RATE, 0.003, 0.09)
    return mix(
        thud(duration=0.26, start_freq=150.0, end_freq=58.0, tau=0.06, seed=41, crack=0.50),
        voice * 0.45,
    )


def build_player_defeat():
    n = int(1.30 * SFX_RATE)
    notes = (392.00, 329.63, 261.63, 196.00)
    out = np.zeros(n, dtype=np.float64)
    for index, freq in enumerate(notes):
        start = int(index * 0.22 * SFX_RATE)
        length = n - start
        tone = (sine(freq, SFX_RATE, length) * 0.6 + sine(freq * 2.0, SFX_RATE, length) * 0.2)
        tone = tone * exp_decay(length, SFX_RATE, 0.01, 0.30)
        out[start:] += tone
    return out


def build_pickup_material():
    n = int(0.18 * SFX_RATE)
    first = sine(659.25, SFX_RATE, n) * exp_decay(n, SFX_RATE, 0.002, 0.045)
    second = pad_to(sine(987.77, SFX_RATE, n) * exp_decay(n, SFX_RATE, 0.0, 0.055), n)
    shift = int(0.055 * SFX_RATE)
    out = first.copy()
    out[shift:] += second[: n - shift] * 0.8
    return out


def build_absorb_material():
    n = int(0.16 * SFX_RATE)
    t = t_of(n, SFX_RATE)
    freq = 520.0 + 900.0 * (t / 0.16)
    return sine(freq, SFX_RATE, n) * exp_decay(n, SFX_RATE, 0.004, 0.045)


def build_brew_open():
    n = int(0.34 * SFX_RATE)
    swell = lowpass(noise(n, 51), ramp(n, 300.0, 2600.0), SFX_RATE) * bell(t_of(n, SFX_RATE), 0.16, 0.10)
    fifth = sine(392.0, SFX_RATE, n) * 0.35 + sine(587.33, SFX_RATE, n) * 0.25
    return mix(swell * 0.7, pad_to(fifth * exp_decay(n, SFX_RATE, 0.02, 0.14), n))


def build_brew_activate():
    n = int(0.60 * SFX_RATE)
    out = np.zeros(n, dtype=np.float64)
    for index, freq in enumerate((523.25, 659.25, 783.99, 1046.50)):
        start = int(index * 0.045 * SFX_RATE)
        tone = (sine(freq, SFX_RATE, n - start) * 0.55 + sine(freq * 2.0, SFX_RATE, n - start) * 0.15
                + sine(freq * 1.004, SFX_RATE, n - start) * 0.25)
        out[start:] += tone * exp_decay(n - start, SFX_RATE, 0.008, 0.28)
    shimmer = lowpass(noise(n, 52), 6000.0, SFX_RATE) * exp_decay(n, SFX_RATE, 0.01, 0.10)
    return out + shimmer * 0.10


def build_brew_stack():
    n = int(0.42 * SFX_RATE)
    out = np.zeros(n, dtype=np.float64)
    for index, freq in enumerate((659.25, 987.77)):
        start = int(index * 0.075 * SFX_RATE)
        tone = sine(freq, SFX_RATE, n - start) * 0.6 + sine(freq * 2.0, SFX_RATE, n - start) * 0.2
        out[start:] += tone * exp_decay(n - start, SFX_RATE, 0.006, 0.16)
    return out


def build_brew_burst():
    n = int(0.50 * SFX_RATE)
    t = t_of(n, SFX_RATE)
    freq = 700.0 - 480.0 * (t / 0.50)
    sweep = square(freq, SFX_RATE, n, duty=0.35) * exp_decay(n, SFX_RATE, 0.004, 0.10)
    burst = lowpass(noise(n, 53), ramp(n, 5200.0, 700.0), SFX_RATE) * exp_decay(n, SFX_RATE, 0.0, 0.09)
    return mix(lowpass(sweep, 2600.0, SFX_RATE) * 0.55, burst * 0.65)


def build_brew_expire():
    n = int(0.44 * SFX_RATE)
    t = t_of(n, SFX_RATE)
    freq = 523.25 - 260.0 * (t / 0.44)
    return sine(freq, SFX_RATE, n) * exp_decay(n, SFX_RATE, 0.006, 0.18) * 0.9


def build_brew_reject():
    n = int(0.26 * SFX_RATE)
    out = np.zeros(n, dtype=np.float64)
    for index, freq in enumerate((196.0, 155.56)):
        start = int(index * 0.085 * SFX_RATE)
        tone = square(freq, SFX_RATE, n - start, duty=0.5) * exp_decay(n - start, SFX_RATE, 0.002, 0.05)
        out[start:] += lowpass(tone, 1400.0, SFX_RATE) * 0.6
    return out


def build_brew_overload():
    n = int(1.00 * SFX_RATE)
    t = t_of(n, SFX_RATE)
    alarm = square(233.08 + 12.0 * np.sin(2.0 * math.pi * 11.0 * t), SFX_RATE, n, duty=0.45)
    alarm = lowpass(alarm, 2400.0, SFX_RATE) * exp_decay(n, SFX_RATE, 0.004, 0.30)
    blast = lowpass(noise(n, 61), ramp(n, 4000.0, 220.0), SFX_RATE) * exp_decay(n, SFX_RATE, 0.0, 0.16)
    boom = sine(ramp(n, 110.0, 38.0), SFX_RATE, n) * exp_decay(n, SFX_RATE, 0.006, 0.26)
    return mix(alarm * 0.45, blast * 0.55, boom * 0.70)


def build_heat_warning():
    n = int(0.13 * SFX_RATE)
    return square(1174.66, SFX_RATE, n, duty=0.5) * exp_decay(n, SFX_RATE, 0.001, 0.025) * 0.5


def build_wheel_open():
    n = int(0.28 * SFX_RATE)
    sweep = lowpass(noise(n, 71), ramp(n, 600.0, 4200.0), SFX_RATE) * bell(t_of(n, SFX_RATE), 0.13, 0.09)
    return sweep * 0.9


def build_wheel_close():
    n = int(0.22 * SFX_RATE)
    sweep = lowpass(noise(n, 72), ramp(n, 3800.0, 500.0), SFX_RATE) * bell(t_of(n, SFX_RATE), 0.09, 0.07)
    return sweep * 0.9


def build_ui_click():
    n = int(0.08 * SFX_RATE)
    return (sine(880.0, SFX_RATE, n) * 0.7 + sine(1760.0, SFX_RATE, n) * 0.2) * exp_decay(n, SFX_RATE, 0.001, 0.020)


def build_ui_hover():
    n = int(0.06 * SFX_RATE)
    return sine(1318.51, SFX_RATE, n) * exp_decay(n, SFX_RATE, 0.001, 0.014) * 0.55


def build_ui_back():
    n = int(0.16 * SFX_RATE)
    out = np.zeros(n, dtype=np.float64)
    for index, freq in enumerate((783.99, 523.25)):
        start = int(index * 0.055 * SFX_RATE)
        out[start:] += sine(freq, SFX_RATE, n - start) * exp_decay(n - start, SFX_RATE, 0.002, 0.045)
    return out


def build_ui_toggle():
    n = int(0.10 * SFX_RATE)
    return square(1046.50, SFX_RATE, n, duty=0.4) * exp_decay(n, SFX_RATE, 0.001, 0.025) * 0.5


def build_world_ready():
    n = int(1.80 * SFX_RATE)
    air = lowpass(noise(n, 81), ramp(n, 400.0, 2200.0), SFX_RATE) * bell(t_of(n, SFX_RATE), 0.8, 0.55)
    chord = np.zeros(n, dtype=np.float64)
    for freq in (261.63, 329.63, 392.00, 523.25):
        chord += sine(freq, SFX_RATE, n) * exp_decay(n, SFX_RATE, 0.35, 0.55)
    return mix(air * 0.45, chord * 0.22)


def build_gate_transition():
    n = int(0.80 * SFX_RATE)
    sweep = lowpass(noise(n, 82), ramp(n, 700.0, 300.0), SFX_RATE)
    sweep = sweep * bell(t_of(n, SFX_RATE), 0.35, 0.26)
    tone = sine(ramp(n, 220.0, 110.0), SFX_RATE, n) * exp_decay(n, SFX_RATE, 0.05, 0.28)
    return mix(sweep * 0.8, tone * 0.45)


# --- 灵感系统 ---------------------------------------------------------------


def build_inspiration_ding():
    """小怪灵感的轻"叮"：单个高频衰减音，尾巴极短，连掉多个也不会糊成一片。"""
    n = int(0.14 * SFX_RATE)
    out = (sine(1567.98, SFX_RATE, n) * 0.8 + sine(3135.96, SFX_RATE, n) * 0.15) * exp_decay(n, SFX_RATE, 0.001, 0.032)
    # 140ms 太短，write_wav 里 25Hz 的二级高通来不及收敛；这里先用更高的截止频率压掉直流。
    return dc_block(out, SFX_RATE, 140.0)


def build_inspiration_bell():
    """精英灵感的"铃"：基频 + 非谐分音，比轻叮更厚、更亮。"""
    n = int(0.55 * SFX_RATE)
    out = np.zeros(n, dtype=np.float64)
    for freq, gain, tau in ((783.99, 1.0, 0.20), (1174.66, 0.55, 0.15), (1876.0, 0.28, 0.10), (2615.0, 0.14, 0.07)):
        out += sine(freq, SFX_RATE, n) * gain * exp_decay(n, SFX_RATE, 0.002, tau)
    return out


def build_inspiration_chime():
    """Boss 灵感的钟鸣：低沉基频 + 长尾泛音，分量更足。"""
    n = int(1.20 * SFX_RATE)
    out = np.zeros(n, dtype=np.float64)
    for freq, gain, tau in ((392.00, 1.0, 0.55), (587.33, 0.6, 0.40), (932.33, 0.35, 0.28), (1385.0, 0.18, 0.18), (1864.66, 0.09, 0.12)):
        out += sine(freq, SFX_RATE, n) * gain * exp_decay(n, SFX_RATE, 0.004, tau)
    shimmer = lowpass(noise(n, 91), 6000.0, SFX_RATE) * exp_decay(n, SFX_RATE, 0.01, 0.30)
    return mix(out, shimmer * 0.05)


def build_inspiration_bell_soft():
    """事件 / 图鉴 / 无伤清房的柔和铃：低通掉高频，听感温润。"""
    n = int(0.45 * SFX_RATE)
    out = np.zeros(n, dtype=np.float64)
    for freq, gain, tau in ((659.25, 1.0, 0.18), (987.77, 0.45, 0.12), (1318.51, 0.2, 0.08)):
        out += sine(freq, SFX_RATE, n) * gain * exp_decay(n, SFX_RATE, 0.004, tau)
    return lowpass(out, 3200.0, SFX_RATE)


def build_inspiration_merge():
    """光点超过阈值合并成光团：上滑的短扫频，提示"合并"这一动作。"""
    n = int(0.22 * SFX_RATE)
    t = t_of(n, SFX_RATE)
    freq = 520.0 + 900.0 * (t / 0.22)
    tone = sine(freq, SFX_RATE, n) * exp_decay(n, SFX_RATE, 0.003, 0.06)
    return mix(tone * 0.7, lowpass(noise(n, 92), 4000.0, SFX_RATE) * exp_decay(n, SFX_RATE, 0.002, 0.03) * 0.25)


def build_inspiration_death():
    """死亡灵感飞散：下行的碎裂声，听感"肉疼"。"""
    n = int(1.10 * SFX_RATE)
    t = t_of(n, SFX_RATE)
    fall = sine(ramp(n, 880.0, 180.0), SFX_RATE, n) * exp_decay(n, SFX_RATE, 0.02, 0.45)
    scatter = lowpass(noise(n, 93), ramp(n, 5000.0, 700.0), SFX_RATE) * exp_decay(n, SFX_RATE, 0.01, 0.35)
    return mix(fall * 0.6, scatter * 0.4)


def build_sage_stone():
    """贤者之石结算：上行和弦 + 长尾，正反馈拉满。"""
    n = int(2.20 * SFX_RATE)
    out = np.zeros(n, dtype=np.float64)
    for index, freq in enumerate((261.63, 329.63, 392.00, 523.25, 659.25)):
        start = int(index * 0.12 * SFX_RATE)
        out[start:] += sine(freq, SFX_RATE, n - start) * exp_decay(n - start, SFX_RATE, 0.05, 0.75)
    shine = lowpass(noise(n, 94), ramp(n, 900.0, 5200.0), SFX_RATE) * bell(t_of(n, SFX_RATE), 1.0, 0.7)
    return mix(out * 0.24, shine * 0.18)


def build_stone_throw():
    return whoosh(0.24, 600.0, 2200.0, 0.07, 83, body=0.05)


def build_stone_land():
    n = int(0.22 * SFX_RATE)
    first = lowpass(noise(n, 84), 3000.0, SFX_RATE) * exp_decay(n, SFX_RATE, 0.0, 0.018)
    second = np.zeros(n, dtype=np.float64)
    offset = int(0.055 * SFX_RATE)
    second[offset:] = (lowpass(noise(n - offset, 85), 2200.0, SFX_RATE)
                       * exp_decay(n - offset, SFX_RATE, 0.0, 0.014))
    return mix(first * 0.8, second * 0.45)


SFX_BUILDERS = {
    "swing_longsword": build_swing_longsword,
    "swing_spear": build_swing_spear,
    "swing_yoyo": build_swing_yoyo,
    "swing_generic": build_swing_generic,
    "hit_flesh": build_hit_flesh,
    "hit_critical": build_hit_critical,
    "hit_wood": build_hit_wood,
    "hit_stone": build_hit_stone,
    "monster_hurt": build_monster_hurt,
    "monster_die": build_monster_die,
    "player_hurt": build_player_hurt,
    "player_defeat": build_player_defeat,
    "pickup_material": build_pickup_material,
    "absorb_material": build_absorb_material,
    "brew_open": build_brew_open,
    "brew_activate": build_brew_activate,
    "brew_stack": build_brew_stack,
    "brew_burst": build_brew_burst,
    "brew_expire": build_brew_expire,
    "brew_reject": build_brew_reject,
    "brew_overload": build_brew_overload,
    "heat_warning": build_heat_warning,
    "wheel_open": build_wheel_open,
    "wheel_close": build_wheel_close,
    "ui_click": build_ui_click,
    "ui_hover": build_ui_hover,
    "ui_back": build_ui_back,
    "ui_toggle": build_ui_toggle,
    "world_ready": build_world_ready,
    "gate_transition": build_gate_transition,
    "stone_throw": build_stone_throw,
    "stone_land": build_stone_land,
    "inspiration_ding": build_inspiration_ding,
    "inspiration_bell": build_inspiration_bell,
    "inspiration_chime": build_inspiration_chime,
    "inspiration_bell_soft": build_inspiration_bell_soft,
    "inspiration_merge": build_inspiration_merge,
    "inspiration_death": build_inspiration_death,
    "sage_stone": build_sage_stone,
}


# --- 音乐 -------------------------------------------------------------------


def pad_chord(freqs, n, rate, attack, release, detune=1.003):
    out = np.zeros(n, dtype=np.float64)
    for freq in freqs:
        out += sine(freq, rate, n) * 0.5
        out += sine(freq * detune, rate, n) * 0.3
        out += sine(freq * 0.5, rate, n) * 0.18
    env = exp_decay(n, rate, attack, release)
    a = max(int(attack * rate), 1)
    if a > 1:
        env[:a] *= np.linspace(0.0, 1.0, a)
    return out / max(len(freqs), 1) * env


def pluck(freq, n, rate, tau):
    tone = sine(freq, rate, n) * 0.7 + sine(freq * 2.0, rate, n) * 0.2 + sine(freq * 3.0, rate, n) * 0.08
    return tone * exp_decay(n, rate, 0.006, tau)


def build_music_menu():
    """A 小调慢速和弦铺底，适合主菜单。纯乐音，不含常驻噪声。"""
    rate = MUSIC_RATE
    chord_seconds = 4.0
    tail = 1.5
    total = int((chord_seconds * 4 + tail) * rate)
    out = np.zeros(total, dtype=np.float64)
    progression = (
        (220.00, 261.63, 329.63),
        (174.61, 220.00, 261.63),
        (261.63, 329.63, 392.00),
        (196.00, 246.94, 293.66),
    )
    for index, chord in enumerate(progression):
        start = int(index * chord_seconds * rate)
        length = total - start
        out[start:] += pad_to(pad_chord(chord, length, rate, 0.9, 2.4), total - start) * 0.30
    melody = (659.25, 587.33, 523.25, 440.00, 392.00, 523.25)
    for index, freq in enumerate(melody):
        start = int((0.6 + index * 2.2) * rate)
        if start >= total:
            break
        out[start:] += pad_to(pluck(freq, total - start, rate, 0.7), total - start) * 0.16
    # 不加常驻噪声床：低通白噪声会让整轨永远不安静，听起来就是持续的"沙沙"底噪。
    return make_seamless(out, rate, 1.5)


def build_music_wilds():
    """A 五声音阶稀疏拨弦 + 低音持续音，适合箱庭探索。纯乐音，不含常驻噪声。"""
    rate = MUSIC_RATE
    loop_seconds = 16.0
    tail = 1.5
    total = int((loop_seconds + tail) * rate)
    out = np.zeros(total, dtype=np.float64)
    drone = sine(110.0, rate, total) * 0.22 + sine(164.81, rate, total) * 0.10
    swell = 0.55 + 0.45 * np.sin(2.0 * math.pi * np.arange(total) / rate / loop_seconds * 2.0 - math.pi / 2.0)
    out += drone * swell
    scale = (440.00, 523.25, 587.33, 659.25, 783.99, 880.00)
    generator = rng(92)
    for index in range(11):
        start = int((0.4 + index * 1.42) * rate)
        if start >= total:
            break
        freq = float(scale[int(generator.integers(0, len(scale)))])
        out[start:] += pad_to(pluck(freq, total - start, rate, 0.55), total - start) * 0.13
    # 同上：探索音乐也保持纯乐音，需要风声时应做成会回到静音的阵风，而不是常驻噪声。
    return make_seamless(out, rate, 1.5)


def read_wav(path):
    with wave.open(path, "rb") as handle:
        frames = handle.getnframes()
        rate = handle.getframerate()
        channels = handle.getnchannels()
        data = np.frombuffer(handle.readframes(frames), dtype="<i2").astype(np.float64) / 32768.0
    if channels > 1:
        data = data.reshape(-1, channels).mean(axis=1)
    return data, rate


def short_time_db(data, rate, window=0.05, hop=0.025):
    size = int(window * rate)
    step = int(hop * rate)
    if data.size < size:
        return np.array([20.0 * math.log10(max(float(np.sqrt(np.mean(data ** 2))), 1e-9))])
    return np.array([
        20.0 * math.log10(max(float(np.sqrt(np.mean(data[start:start + size] ** 2))), 1e-9))
        for start in range(0, data.size - size + 1, step)
    ])


def spectral_flatness(segment):
    """频谱平坦度：0 接近纯乐音，1 接近白噪声。用来识别常驻噪声床。"""
    centered = segment - segment.mean()
    if centered.size < 256:
        return 0.0
    power = np.abs(np.fft.rfft(centered * np.hanning(centered.size))) ** 2 + 1e-20
    power = power[1:]
    return float(np.exp(np.mean(np.log(power))) / np.mean(power))


def self_check(written):
    """生成后自检，守住两类已经踩过的坑：

    1. 直流偏移：衰减正弦的首个正半周会让整段素材带上直流分量。
    2. 常驻噪声床：低通白噪声会让音乐整轨永远不安静，听感就是持续的沙沙底噪。
    """
    problems = []
    for path, is_music in written:
        data, rate = read_wav(path)
        name = os.path.basename(path)
        dc = float(data.mean())
        if abs(dc) > 0.005:
            problems.append("%s 直流偏移 %+.4f 偏高（应接近 0）" % (name, dc))
        if not is_music:
            continue
        levels = short_time_db(data, rate)
        quiet = float(levels.min())
        typical = float(np.median(levels))
        start = int(np.argmin(levels)) * int(0.025 * rate)
        flat = spectral_flatness(data[start:start + int(0.05 * rate)])
        if flat > 0.15:
            problems.append("%s 最安静处接近白噪声（频谱平坦度 %.3f）" % (name, flat))
        if typical - quiet < 8.0:
            problems.append("%s 动态范围只有 %.1f dB，疑似存在常驻噪声床" % (name, typical - quiet))
    for message in problems:
        print("  [自检] " + message)
    if not problems:
        print("  自检通过：无直流偏移，音乐不含常驻噪声床。")
    return not problems


def main():
    os.makedirs(SFX_DIR, exist_ok=True)
    os.makedirs(MUSIC_DIR, exist_ok=True)
    written = []
    print("音效 -> %s" % SFX_DIR)
    for name in sorted(SFX_BUILDERS):
        path = os.path.join(SFX_DIR, name + ".wav")
        write_wav(path, SFX_BUILDERS[name](), SFX_RATE)
        written.append((path, False))
    print("音乐 -> %s" % MUSIC_DIR)
    for name, builder, peak in (("music_menu", build_music_menu, -9.0), ("music_wilds", build_music_wilds, -11.0)):
        path = os.path.join(MUSIC_DIR, name + ".wav")
        write_wav(path, builder(), MUSIC_RATE, peak_db=peak, fade=0.0)
        written.append((path, True))
    print("完成：%d 个音效，2 段音乐。" % len(SFX_BUILDERS))
    print("自检 ->")
    return 0 if self_check(written) else 1


if __name__ == "__main__":
    sys.exit(main())
