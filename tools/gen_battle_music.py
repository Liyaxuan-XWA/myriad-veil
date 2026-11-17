#!/usr/bin/env python3
"""生成 48 秒无缝循环 BGM。

三首战斗曲：国风武侠 / 紧张压迫 / 史诗管弦（开战时随机轮换）。
三首场景曲：原初位面（空灵舒缓）/ 苍澜大陆（木石打击 + 暗色合成器）/ 登录界面（神秘涌动）。
纯 numpy 合成，不依赖外部采样；改曲只改本文件后重跑：
    python tools/gen_battle_music.py            # 全部重出
    python tools/gen_battle_music.py title_veil  # 只重出登录界面那一首
输出：assets/audio/bgm/battle_*.wav / realm_primordial.wav / world_continent.wav / title_veil.wav
"""
from __future__ import annotations

import math
import os
import sys
import wave

import numpy as np

SR = 32000
DUR = 48.0
N = int(round(SR * DUR))
OUT_DIR = os.path.join("assets", "audio", "bgm")
RNG = np.random.default_rng(20261024)


# ===================== 基础工具 =====================

def hz(midi: float) -> float:
    return 440.0 * (2.0 ** ((float(midi) - 69.0) / 12.0))


def _t(n: int) -> np.ndarray:
    return np.arange(n, dtype=np.float64) / float(SR)


def env_adsr(n: int, attack: float, decay: float, sustain: float, release: float) -> np.ndarray:
    if n <= 0:
        return np.zeros(0)
    a = max(1, min(n, int(attack * SR)))
    r = max(1, min(max(0, n - a), int(release * SR)))
    d = max(0, min(max(0, n - a - r), int(decay * SR)))
    env = np.zeros(n, dtype=np.float64)
    env[:a] = np.linspace(0.0, 1.0, a, endpoint=False)
    if d > 0:
        env[a:a + d] = np.linspace(1.0, sustain, d, endpoint=False)
    body_end = a + d
    if body_end < n:
        env[body_end:] = np.linspace(sustain, 0.0, n - body_end, endpoint=False)
    return env


def env_pluck(n: int, attack: float, decay: float) -> np.ndarray:
    t = _t(n)
    a = np.clip(t / max(attack, 1e-5), 0.0, 1.0)
    return a * np.exp(-t / max(decay, 1e-4))


def noise(n: int) -> np.ndarray:
    return RNG.standard_normal(n)


def hpf_noise(n: int, k: int = 5) -> np.ndarray:
    x = noise(n)
    if k <= 1:
        return x
    smooth = np.convolve(x, np.ones(k, dtype=np.float64) / float(k), mode="same")
    return x - smooth


def sine(freq: float, n: int, phase: float = 0.0) -> np.ndarray:
    return np.sin(2.0 * math.pi * freq * _t(n) + phase)


def saw(freq: float, n: int, harmonics: int = 7, rolloff: float = 1.0) -> np.ndarray:
    t = _t(n)
    out = np.zeros(n, dtype=np.float64)
    for k in range(1, harmonics + 1):
        f = freq * k
        if f >= SR * 0.46:
            break
        out += np.sin(2.0 * math.pi * f * t + (0.25 if k % 2 else 0.0)) / (k ** rolloff)
    return out


# ===================== 乐器 =====================

def pluck(freq: float, dur: float = 0.8, bright: float = 1.0) -> np.ndarray:
    n = max(1, int(dur * SR))
    t = _t(n)
    env = env_pluck(n, 0.003, dur * 0.34)
    body = np.zeros(n, dtype=np.float64)
    for k, amp in ((1, 1.0), (2, 0.42), (3, 0.24), (4, 0.14), (5, 0.08), (6, 0.05)):
        body += amp * np.sin(2.0 * math.pi * freq * k * t + 0.13 * k)
    body += 0.18 * saw(freq * 1.003, n, harmonics=5, rolloff=1.6)
    body += 0.22 * bright * hpf_noise(n, 9) * np.exp(-t / 0.007)
    return body * env


def bowed(freq: float, dur: float, attack: float = 0.18, release: float = 0.3) -> np.ndarray:
    n = max(1, int(dur * SR))
    t = _t(n)
    vib = 1.0 + 0.0045 * np.sin(2.0 * math.pi * 5.1 * t) * np.clip(t / 0.35, 0.0, 1.0)
    body = np.zeros(n, dtype=np.float64)
    for k in range(1, 8):
        f = freq * k
        if f >= SR * 0.45:
            break
        body += np.sin(2.0 * math.pi * f * t * vib + 0.21 * k) / (k ** 1.25)
    body += 0.035 * hpf_noise(n, 7)
    env = env_adsr(n, attack, 0.08, 0.82, release)
    return body * env


def pad(freq: float, dur: float, attack: float = 0.7, release: float = 0.8) -> np.ndarray:
    n = max(1, int(dur * SR))
    t = _t(n)
    body = np.zeros(n, dtype=np.float64)
    for det in (-0.004, 0.0, 0.004):
        for k in range(1, 7):
            f = freq * (1.0 + det) * k
            if f >= SR * 0.45:
                break
            body += np.sin(2.0 * math.pi * f * t + 0.37 * k) / (k ** 1.35)
    env = env_adsr(n, attack, 0.15, 0.86, release)
    return body * env / 3.0


def bass_note(freq: float, dur: float, decay: float = 0.35) -> np.ndarray:
    n = max(1, int(dur * SR))
    t = _t(n)
    env = env_pluck(n, 0.004, decay)
    body = np.sin(2.0 * math.pi * freq * t)
    body += 0.35 * np.sin(2.0 * math.pi * freq * 2.0 * t + 0.1)
    body += 0.16 * saw(freq, n, harmonics=4, rolloff=1.6)
    return body * env


def brass(freq: float, dur: float, attack: float = 0.04) -> np.ndarray:
    n = max(1, int(dur * SR))
    t = _t(n)
    body = np.zeros(n, dtype=np.float64)
    for k, amp in ((1, 1.0), (2, 0.6), (3, 0.45), (4, 0.3), (5, 0.2), (6, 0.13), (7, 0.08)):
        f = freq * k
        if f >= SR * 0.45:
            break
        body += amp * np.sin(2.0 * math.pi * f * t + 0.08 * k)
    env = env_adsr(n, attack, 0.12, 0.72, 0.28)
    return body * env / 2.6


def choir(freq: float, dur: float) -> np.ndarray:
    n = max(1, int(dur * SR))
    t = _t(n)
    body = np.zeros(n, dtype=np.float64)
    for det in (-0.006, 0.0, 0.006):
        for k, amp in ((1, 1.0), (2, 0.25), (3, 0.16), (4, 0.08)):
            f = freq * (1.0 + det) * k
            if f >= SR * 0.45:
                break
            body += amp * np.sin(2.0 * math.pi * f * t + 0.2 * k)
    env = env_adsr(n, 0.8, 0.2, 0.9, 0.9)
    return body * env / 3.0


def bell(freq: float, dur: float = 4.0) -> np.ndarray:
    n = max(1, int(dur * SR))
    t = _t(n)
    body = np.zeros(n, dtype=np.float64)
    for ratio, amp, decay in ((1.0, 1.0, 1.8), (2.01, 0.5, 1.25),
                              (3.9, 0.25, 0.85), (5.4, 0.14, 0.6), (7.1, 0.08, 0.42)):
        body += amp * np.sin(2.0 * math.pi * freq * ratio * t + 0.2 * ratio) * np.exp(-t / decay)
    body += 0.02 * hpf_noise(n, 9) * np.exp(-t / 0.25)
    return body * env_pluck(n, 0.002, 2.4)


def flute(freq: float, dur: float) -> np.ndarray:
    n = max(1, int(dur * SR))
    t = _t(n)
    vib = 1.0 + 0.0055 * np.sin(2.0 * math.pi * 5.0 * t) * np.clip(t / 0.35, 0.0, 1.0)
    body = np.sin(2.0 * math.pi * freq * t * vib)
    body += 0.22 * np.sin(2.0 * math.pi * freq * 2.0 * t * vib + 0.15)
    body += 0.08 * np.sin(2.0 * math.pi * freq * 3.0 * t * vib + 0.3)
    body += 0.018 * hpf_noise(n, 7) * np.clip(t / 0.2, 0.0, 1.0)
    env = env_adsr(n, 0.08, 0.06, 0.82, 0.32)
    return body * env / 1.3


# ===================== 打击乐 =====================

def kick(dur: float = 0.4, f0: float = 92.0, f1: float = 42.0) -> np.ndarray:
    n = max(1, int(dur * SR))
    t = _t(n)
    f = f1 + (f0 - f1) * np.exp(-t / 0.055)
    phase = 2.0 * math.pi * np.cumsum(f) / SR
    body = np.sin(phase) * np.exp(-t / 0.22)
    body += 0.18 * hpf_noise(n, 7) * np.exp(-t / 0.008)
    return body


def taiko(dur: float = 0.75, f0: float = 128.0, f1: float = 58.0) -> np.ndarray:
    n = max(1, int(dur * SR))
    t = _t(n)
    f = f1 + (f0 - f1) * np.exp(-t / 0.07)
    phase = 2.0 * math.pi * np.cumsum(f) / SR
    body = np.sin(phase) * np.exp(-t / 0.24)
    body += 0.12 * np.sin(phase * 1.58) * np.exp(-t / 0.16)
    body += 0.22 * hpf_noise(n, 8) * np.exp(-t / 0.012)
    return body


def snare(dur: float = 0.3) -> np.ndarray:
    n = max(1, int(dur * SR))
    t = _t(n)
    body = hpf_noise(n, 8) * np.exp(-t / 0.105)
    body += 0.55 * np.sin(2.0 * math.pi * 185.0 * t) * np.exp(-t / 0.07)
    return body


def hat(dur: float = 0.09, open_hat: bool = False) -> np.ndarray:
    n = max(1, int(dur * SR))
    t = _t(n)
    return hpf_noise(n, 13) * np.exp(-t / (0.13 if open_hat else 0.028))


def gong(dur: float = 3.2, freq: float = 82.0) -> np.ndarray:
    n = max(1, int(dur * SR))
    t = _t(n)
    body = np.zeros(n, dtype=np.float64)
    for ratio, amp, decay in ((1.0, 0.9, 2.4), (2.71, 0.42, 1.7),
                              (4.13, 0.24, 1.2), (5.62, 0.15, 0.9), (7.21, 0.08, 0.7)):
        body += amp * np.sin(2.0 * math.pi * freq * ratio * t + 0.2 * ratio) * np.exp(-t / decay)
    body += 0.05 * hpf_noise(n, 9) * np.exp(-t / 0.8)
    return body * env_pluck(n, 0.006, 2.2)


def cymbal(dur: float = 2.0) -> np.ndarray:
    n = max(1, int(dur * SR))
    t = _t(n)
    env = np.clip(t / 0.05, 0.0, 1.0) * np.exp(-t / 1.2)
    return hpf_noise(n, 16) * env


# ===================== 混音 =====================

class Mix:
    def __init__(self) -> None:
        self.buf = np.zeros((N, 2), dtype=np.float64)

    def add(self, start_sec: float, sig: np.ndarray, pan: float = 0.0, gain: float = 1.0) -> None:
        if sig is None or len(sig) == 0:
            return
        sig = np.asarray(sig, dtype=np.float64)
        n = len(sig)
        start = int(round(start_sec * SR)) % N
        pan = max(-1.0, min(1.0, float(pan)))
        left = math.sqrt((1.0 - pan) * 0.5)
        right = math.sqrt((1.0 + pan) * 0.5)
        first = min(n, N - start)
        self.buf[start:start + first, 0] += sig[:first] * left * gain
        self.buf[start:start + first, 1] += sig[:first] * right * gain
        rest = n - first
        if rest > 0:
            rest = min(rest, N)
            self.buf[:rest, 0] += sig[first:first + rest] * left * gain
            self.buf[:rest, 1] += sig[first:first + rest] * right * gain


def add_reverb(mix: Mix, amount: float = 1.0) -> None:
    dry = mix.buf.copy()
    taps = ((0.089, 0.16, 0.35), (0.157, 0.11, -0.4),
            (0.241, 0.08, 0.55), (0.379, 0.055, -0.5))
    for delay, gain, pan in taps:
        d = int(delay * SR)
        dl = np.roll(dry[:, 0], d)
        dr = np.roll(dry[:, 1], d)
        mix.buf[:, 0] += (dl * (1.0 - max(0.0, pan)) + dr * max(0.0, pan)) * gain * amount
        mix.buf[:, 1] += (dr * (1.0 + min(0.0, pan)) + dl * -min(0.0, pan)) * gain * amount


def finish(mix: Mix, name: str, target_peak: float = 0.86,
        seam_fade: float = 0.008) -> str:
    x = mix.buf - np.mean(mix.buf, axis=0, keepdims=True)
    # 轻微软限幅，避免叠加峰值过硬
    drive = 1.15
    x = np.tanh(x * drive) / math.tanh(drive)
    peak = float(np.max(np.abs(x))) if x.size else 0.0
    if peak > 1e-9:
        x *= target_peak / peak
    # 无缝循环：首尾各 8ms 淡入/淡出，消除接缝爆音；对 48 秒循环几乎不可闻
    # ⚠ seam_fade = 0 时跳过：留给「首尾本就是满幅」的曲子（登录界面），
    #   那条线改用 tools/loop_title_bgm.py 的折叠交叉淡化接缝，效果比淡入淡出好得多
    if seam_fade > 0.0:
        seam = max(1, int(seam_fade * SR))
        ramp = np.linspace(0.0, 1.0, seam)[:, None]
        x[:seam] *= ramp
        x[-seam:] *= ramp[::-1]
    jump = float(np.max(np.abs(x[0] - x[-1]))) if x.size else 0.0
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name)
    pcm = np.clip(x, -1.0, 1.0)
    pcm = (pcm * 32767.0).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    rms = float(np.sqrt(np.mean(np.square(x)))) if x.size else 0.0
    print("[music] %s  %.1fs  peak=%.2f  rms=%.3f  seam=%.4f" % (
        path, N / SR, target_peak, rms, jump))
    return path


# ===================== 曲目 1：国风武侠 =====================

def make_wuxia() -> Mix:
    bpm = 100.0
    beat = 60.0 / bpm
    bar = beat * 4.0
    bars = 20
    mix = Mix()

    # 持续低音与弦乐铺底
    for midi_note, pan in ((38, 0.0), (45, 0.25), (50, -0.2)):
        mix.add(0.0, pad(hz(midi_note), DUR, 1.4, 1.0), pan=pan, gain=0.055)

    chord_sections = [
        (0, (50, 53, 57)),    # Dm
        (4, (50, 53, 57)),
        (8, (46, 50, 53)),    # Bb
        (12, (43, 46, 50)),   # Gm
        (16, (50, 53, 57)),   # Dm
    ]
    for start_bar, chord in chord_sections:
        dur = bar * 4.0
        for i, note in enumerate(chord):
            mix.add(start_bar * bar, pad(hz(note), dur, 0.55, 0.7),
                    pan=(-0.28 + 0.28 * i), gain=0.038)
        mix.add(start_bar * bar, bass_note(hz(chord[0] - 12), dur, 1.4), gain=0.11)

    # 锣 / 大鼓骨架
    for b in range(bars):
        t0 = b * bar
        mix.add(t0, taiko(0.85, 120.0, 56.0), gain=0.38)
        mix.add(t0 + beat * 2.0, taiko(0.55, 105.0, 60.0), gain=0.17)
        mix.add(t0 + beat * 3.5, kick(0.28, 84.0, 44.0), gain=0.10)
        for e in range(8):
            mix.add(t0 + e * beat * 0.5, hat(0.07), pan=0.45 if e % 2 else -0.45, gain=0.035)
        if b % 4 == 0:
            mix.add(t0, gong(3.0, 82.0), pan=0.15, gain=0.16)
        if b in (7, 11, 15, 19):
            for k in range(6):
                mix.add(t0 + beat * 2.0 + k * beat / 6.0,
                        taiko(0.24, 120.0, 78.0), gain=0.10 + 0.02 * k)

    # 低音拨弦与木鱼式点缀
    roots = [38, 38, 34, 31, 38]
    for b in range(bars):
        root = roots[min(4, b // 4)]
        mix.add(b * bar, pluck(hz(root + 12), 0.55), pan=-0.18, gain=0.13)
        mix.add(b * bar + beat * 2.0, pluck(hz(root + 19), 0.5), pan=0.22, gain=0.09)
        mix.add(b * bar + beat * 1.5, pluck(hz(74), 0.22, 0.8), pan=0.55, gain=0.055)
        mix.add(b * bar + beat * 3.5, pluck(hz(69), 0.22, 0.8), pan=0.55, gain=0.05)

    # 古筝主旋律（第 3~11 小节）
    melody = [
        (4, 0.0, 62, 0.5), (4, 0.5, 65, 0.5), (4, 1.0, 67, 1.0), (4, 2.0, 69, 0.5),
        (4, 2.5, 72, 0.5), (4, 3.0, 69, 0.5), (4, 3.5, 67, 0.5),
        (5, 0.0, 65, 0.75), (5, 0.75, 67, 0.75), (5, 1.5, 69, 1.5), (5, 3.0, 74, 0.5), (5, 3.5, 72, 0.5),
        (6, 0.0, 69, 1.0), (6, 1.0, 72, 0.5), (6, 1.5, 74, 0.5), (6, 2.0, 77, 1.0), (6, 3.0, 74, 1.0),
        (7, 0.0, 72, 0.5), (7, 0.5, 69, 0.5), (7, 1.0, 67, 1.0), (7, 2.0, 65, 0.5), (7, 2.5, 67, 0.5), (7, 3.0, 69, 1.0),
        (8, 0.0, 69, 1.0), (8, 1.0, 72, 0.5), (8, 1.5, 74, 0.5), (8, 2.0, 77, 1.5),
        (9, 0.0, 74, 1.0), (9, 1.0, 72, 0.5), (9, 1.5, 69, 0.5), (9, 2.0, 67, 1.0), (9, 3.0, 65, 1.0),
        (10, 0.0, 62, 0.5), (10, 0.5, 65, 0.5), (10, 1.0, 69, 1.0), (10, 2.0, 74, 1.0), (10, 3.0, 72, 1.0),
        (11, 0.0, 69, 0.5), (11, 0.5, 67, 0.5), (11, 1.0, 65, 1.5), (11, 2.5, 62, 1.5),
    ]
    for b, bt, midi_note, dur_beats in melody:
        mix.add(b * bar + bt * beat, pluck(hz(midi_note), dur_beats * beat * 1.7, 1.0),
                pan=(-0.18 if b % 2 == 0 else 0.18), gain=0.20)

    # 二胡长音（第 12~19 小节），与古筝形成对答
    erhu = [
        (12, 0.0, 69, 2.0), (12, 2.0, 67, 2.0),
        (13, 0.0, 65, 2.5), (13, 2.5, 67, 1.5),
        (14, 0.0, 69, 2.0), (14, 2.0, 72, 2.0),
        (15, 0.0, 74, 1.5), (15, 1.5, 72, 1.0), (15, 2.5, 69, 1.5),
        (16, 0.0, 67, 2.0), (16, 2.0, 69, 2.0),
        (17, 0.0, 72, 2.0), (17, 2.0, 74, 2.0),
        (18, 0.0, 77, 1.5), (18, 1.5, 74, 1.0), (18, 2.5, 72, 1.5),
        (19, 0.0, 69, 2.0), (19, 2.0, 67, 1.0), (19, 3.0, 65, 1.0),
    ]
    for b, bt, midi_note, dur_beats in erhu:
        mix.add(b * bar + bt * beat, bowed(hz(midi_note), dur_beats * beat * 1.1),
                pan=0.12, gain=0.12)
    # 第 12 小节起加入古筝分解和弦，避免只有长音
    for b in range(12, 20):
        root = 50 if b < 16 else 50
        for k, interval in enumerate((0, 7, 12, 15)):
            mix.add(b * bar + k * beat, pluck(hz(root + interval), 0.45),
                    pan=(-0.35 + 0.12 * k), gain=0.055)

    add_reverb(mix, 1.0)
    return mix


# ===================== 曲目 2：紧张压迫 =====================

def make_tense() -> Mix:
    bpm = 140.0
    beat = 60.0 / bpm
    bar = beat * 4.0
    bars = 28
    mix = Mix()

    roots = (36, 32, 29, 31)
    triads = ((48, 51, 55), (44, 48, 51), (41, 44, 48), (43, 47, 50))
    ostinato = (0, 0, 12, 0, 7, 0, 10, 7, 0, 0, 12, 0, 7, 0, 15, 7)

    # 低音 16 分固定音型
    for b in range(bars):
        root = roots[(b // 4) % 4]
        for step in range(16):
            midi_note = root + ostinato[step]
            dur = beat / 4.0 * 0.92
            mix.add(b * bar + step * beat / 4.0,
                    bass_note(hz(midi_note), dur, 0.09), pan=-0.12, gain=0.105)

    # 鼓组
    for b in range(bars):
        t0 = b * bar
        for k in range(4):
            mix.add(t0 + k * beat, kick(0.3), gain=0.30 if k % 2 == 0 else 0.22)
        mix.add(t0 + beat, snare(0.24), gain=0.20)
        mix.add(t0 + beat * 3.0, snare(0.24), gain=0.20)
        hat_div = 16 if b >= 8 else 8
        for e in range(hat_div):
            mix.add(t0 + e * beat * 4.0 / hat_div, hat(0.06),
                    pan=0.55 if e % 2 else -0.55, gain=0.026)
        if b % 4 == 3:
            mix.add(t0 + beat * 3.0, hat(0.22, True), pan=0.2, gain=0.05)

    # 弦乐短促和弦：每小节 1、3 拍
    for b in range(bars):
        triad = triads[(b // 4) % 4]
        for hit_beat in (0.0, 2.0):
            for i, note in enumerate(triad):
                mix.add(b * bar + hit_beat * beat,
                        brass(hz(note), 0.24, 0.012), pan=(-0.2 + 0.2 * i),
                        gain=0.035)

    # 高频不谐和音 / 警报感，后半段加入
    for b in range(12, bars):
        t0 = b * bar
        mix.add(t0, bowed(hz(83), bar * 0.9, 0.4, 0.5), pan=0.5, gain=0.020)
        mix.add(t0, bowed(hz(84), bar * 0.9, 0.4, 0.5), pan=-0.5, gain=0.016)

    # 工业撞击：每 4 小节
    for b in range(0, bars, 4):
        mix.add(b * bar, gong(2.6, 69.0), pan=-0.25, gain=0.10)

    # 最后两小节军鼓滚奏，接回 0 小节的大鼓
    for b in (26, 27):
        t0 = b * bar
        for e in range(16):
            g = 0.08 + 0.10 * (e / 15.0) + (0.04 if b == 27 else 0.0)
            mix.add(t0 + e * beat / 4.0, snare(0.14), pan=0.1, gain=g)

    # 开场与段落转换的冲击
    for b in (0, 8, 16, 24):
        mix.add(b * bar, kick(0.6, 100.0, 38.0), gain=0.28)
        mix.add(b * bar, cymbal(1.8), pan=0.3, gain=0.10)

    add_reverb(mix, 0.7)
    return mix


# ===================== 曲目 3：史诗管弦 =====================

def make_epic() -> Mix:
    bpm = 90.0
    beat = 60.0 / bpm
    bar = beat * 4.0
    bars = 18
    mix = Mix()

    progression = (
        (57, 60, 64), (53, 57, 60), (48, 52, 55), (55, 59, 62),
        (57, 60, 64), (53, 57, 60), (48, 52, 55), (55, 59, 62),
        (57, 60, 64), (53, 57, 60), (48, 52, 55), (55, 59, 62),
        (57, 60, 64), (53, 57, 60), (48, 52, 55), (55, 59, 62),
        (57, 60, 64), (57, 60, 64),
    )
    roots = (45, 41, 36, 43)

    # 管弦铺底：每两小节换一次和弦
    for b in range(0, bars, 2):
        chord = progression[b]
        dur = bar * 2.0
        for i, note in enumerate(chord):
            mix.add(b * bar, pad(hz(note), dur, 0.65, 0.8),
                    pan=(-0.35 + 0.35 * i), gain=0.060)
        root = roots[(b // 2) % 4]
        mix.add(b * bar, bass_note(hz(root), dur, 1.6), gain=0.12)
        # 合唱在第二段起进入
        if b >= 8:
            for i, note in enumerate(chord):
                mix.add(b * bar, choir(hz(note), dur), pan=(-0.25 + 0.25 * i), gain=0.028)

    # 定音鼓
    for b in range(bars):
        t0 = b * bar
        root = roots[(b // 2) % 4]
        mix.add(t0, taiko(0.95, 112.0, 50.0), gain=0.40)
        mix.add(t0 + beat * 2.0, taiko(0.55, 96.0, 54.0), gain=0.18)
        mix.add(t0 + beat * 3.5, taiko(0.35, 88.0, 60.0), gain=0.10)
        if b % 4 == 3:
            for e in range(8):
                mix.add(t0 + beat * 3.0 + e * beat / 8.0,
                        taiko(0.22, 104.0, 66.0), gain=0.08 + 0.01 * e)

    # 铜管主旋律（第 3 小节起）
    melody = [
        (4, 0.0, 69, 2.0), (4, 2.0, 72, 1.0), (4, 3.0, 76, 1.0),
        (5, 0.0, 74, 2.0), (5, 2.0, 72, 1.0), (5, 3.0, 69, 1.0),
        (6, 0.0, 71, 2.0), (6, 2.0, 74, 1.0), (6, 3.0, 72, 1.0),
        (7, 0.0, 69, 3.0), (7, 3.0, 67, 1.0),
        (8, 0.0, 69, 2.0), (8, 2.0, 72, 1.0), (8, 3.0, 76, 1.0),
        (9, 0.0, 79, 2.0), (9, 2.0, 76, 1.0), (9, 3.0, 74, 1.0),
        (10, 0.0, 72, 2.0), (10, 2.0, 74, 1.0), (10, 3.0, 76, 1.0),
        (11, 0.0, 74, 2.0), (11, 2.0, 72, 1.0), (11, 3.0, 69, 1.0),
        (12, 0.0, 69, 1.0), (12, 1.0, 72, 1.0), (12, 2.0, 76, 2.0),
        (13, 0.0, 79, 2.0), (13, 2.0, 76, 1.0), (13, 3.0, 72, 1.0),
        (14, 0.0, 74, 2.0), (14, 2.0, 71, 1.0), (14, 3.0, 74, 1.0),
        (15, 0.0, 72, 3.0), (15, 3.0, 69, 1.0),
        (16, 0.0, 76, 2.0), (16, 2.0, 74, 1.0), (16, 3.0, 72, 1.0),
        (17, 0.0, 69, 4.0),
    ]
    for b, bt, midi_note, dur_beats in melody:
        mix.add(b * bar + bt * beat, brass(hz(midi_note), dur_beats * beat * 0.94),
                pan=-0.05, gain=0.15)
        mix.add(b * bar + bt * beat, brass(hz(midi_note - 12), dur_beats * beat * 0.94),
                pan=0.2, gain=0.055)

    # 镲片与段落冲击
    for b in (0, 4, 8, 12, 16):
        mix.add(b * bar, cymbal(2.4), pan=0.25, gain=0.12)
        mix.add(b * bar, kick(0.7, 96.0, 38.0), gain=0.22)
        mix.add(b * bar, gong(3.4, 74.0), pan=-0.2, gain=0.11)

    add_reverb(mix, 1.15)
    return mix


# ===================== 曲目 4：原初位面（空灵、舒缓） =====================

def make_primordial() -> Mix:
    bpm = 60.0
    beat = 60.0 / bpm
    bar = beat * 4.0
    bars = 12
    mix = Mix()
    # Dmaj7 / Bm7 / Gmaj7 / Asus2，每个和弦 3 小节（12 秒）
    chords = [
        (50, 54, 57, 61),
        (47, 50, 54, 57),
        (43, 47, 50, 54),
        (45, 49, 52, 57),
    ]
    for idx, chord in enumerate(chords):
        start = float(idx * 3) * bar
        dur = bar * 3.0
        for i, note in enumerate(chord):
            mix.add(start, pad(hz(note), dur, 1.8, 1.6),
                    pan=(-0.42 + 0.28 * float(i)), gain=0.042)
        mix.add(start, bass_note(hz(chord[0] - 12), dur, 3.4), gain=0.055)
        if idx >= 1:
            for i, note in enumerate(chord[:3]):
                mix.add(start, choir(hz(note), dur),
                        pan=(-0.25 + 0.25 * float(i)), gain=0.020)

    # 稀疏的钟/磬旋律（D 五声），给空灵空间留白
    bells = [
        (2.0, 74, 5.0, -0.2), (7.0, 78, 5.0, 0.25), (12.0, 81, 6.0, -0.1),
        (18.0, 76, 5.0, 0.3), (24.0, 74, 6.0, 0.2), (29.0, 78, 5.0, -0.25),
        (34.0, 81, 6.0, 0.1), (39.0, 76, 5.0, -0.2), (43.0, 74, 5.0, 0.2),
    ]
    for start, midi_note, dur, pan in bells:
        mix.add(start, bell(hz(midi_note), dur), pan=pan, gain=0.075)

    # 低频颂钵，只在段落起点出现
    for start in (0.0, 16.0, 32.0):
        mix.add(start, gong(6.0, 58.0), pan=0.15, gain=0.045)
    # 很轻的持续高音气流
    mix.add(0.0, pad(hz(86), DUR, 3.0, 2.0), pan=0.4, gain=0.012)

    add_reverb(mix, 1.45)
    return mix


# ===================== 曲目 5：苍澜大陆（开阔探索） =====================

def soft_heartbeat(dur: float = 0.55, f0: float = 68.0, f1: float = 36.0) -> np.ndarray:
    """纯低频心跳：无噪声瞬态、无高频敲击，只留闷闷的两下起伏。"""
    n = max(1, int(dur * SR))
    t = _t(n)
    f = f1 + (f0 - f1) * np.exp(-t / 0.08)
    phase = 2.0 * math.pi * np.cumsum(f) / SR
    body = np.sin(phase) * np.exp(-t / 0.22)
    body += 0.14 * np.sin(phase * 2.0) * np.exp(-t / 0.12)
    return body * np.clip(t / 0.025, 0.0, 1.0)


def wind_swell(dur: float) -> np.ndarray:
    """低频风声：带通噪声 + 中间强、两头弱的长包络，不刺耳。"""
    n = max(1, int(dur * SR))
    t = _t(n)
    x = hpf_noise(n, 5)
    x = np.convolve(x, np.ones(41, dtype=np.float64) / 41.0, mode="same")
    env = np.sin(math.pi * t / dur) ** 2
    return x * env


def wood_mallet(freq: float, dur: float = 0.5) -> np.ndarray:
    """木质马林巴/木琴：短促、温暖，不要金属钟声的尾音。"""
    n = max(1, int(dur * SR))
    t = _t(n)
    env = env_pluck(n, 0.003, dur * 0.34)
    body = np.sin(2.0 * math.pi * freq * t)
    body += 0.30 * np.sin(2.0 * math.pi * freq * 3.9 * t + 0.1) * np.exp(-t / 0.10)
    body += 0.10 * np.sin(2.0 * math.pi * freq * 9.2 * t + 0.2) * np.exp(-t / 0.05)
    body += 0.10 * hpf_noise(n, 9) * np.exp(-t / 0.006)
    return body * env / 1.2


def stone_tick(freq: float = 1450.0, dur: float = 0.16) -> np.ndarray:
    """石片/木块的短促敲击：中高频、低音量，避免高频嘶声。"""
    n = max(1, int(dur * SR))
    t = _t(n)
    body = np.sin(2.0 * math.pi * freq * t) * np.exp(-t / 0.035)
    body += 0.32 * np.sin(2.0 * math.pi * freq * 1.68 * t + 0.2) * np.exp(-t / 0.022)
    body += 0.16 * hpf_noise(n, 11) * np.exp(-t / 0.005)
    return body * env_pluck(n, 0.001, 0.08)


def synth_drone(freq: float, dur: float, attack: float = 1.2, release: float = 1.4) -> np.ndarray:
    """非弦乐的持续合成器低音：纯正弦谐波，慢起慢收，没有弓弦质感。"""
    n = max(1, int(dur * SR))
    t = _t(n)
    body = np.sin(2.0 * math.pi * freq * t)
    body += 0.24 * np.sin(2.0 * math.pi * freq * 2.0 * t + 0.1)
    body += 0.10 * np.sin(2.0 * math.pi * freq * 3.0 * t + 0.2)
    env = env_adsr(n, attack, 0.2, 0.9, release)
    return body * env / 1.3


def make_continent() -> Mix:
    """苍澜大陆：木石打击 / 危机感 / 不吵 / 不诡异。

    以木琴/石片敲击为主，低频只做持续合成器铺底；没有弦乐、铜管、竹笛、
    钟声、风声或低频鼓点。节奏稀疏，靠小调和声与敲击密度推进。
    """
    bpm = 80.0
    beat = 60.0 / bpm
    bar = beat * 4.0
    bars = 16
    mix = Mix()
    chords = [
        (50, 53, 57),
        (46, 50, 53),
        (43, 46, 50),
        (45, 49, 52),
    ]
    # 持续合成器低音：只铺和声，不做脉冲
    for b in range(0, bars, 2):
        chord = chords[(b // 2) % 4]
        start = float(b) * bar
        dur = bar * 2.0
        mix.add(start, synth_drone(hz(chord[0] - 12), dur, 0.9, 1.2), gain=0.045)
        mix.add(start, synth_drone(hz(chord[0] - 5), dur, 1.1, 1.4), gain=0.015)

    # 木琴动机：每小节 2~3 个音，全部落在和弦内，不密集
    for b in range(bars):
        chord = chords[(b // 2) % 4]
        t0 = float(b) * bar
        if b % 2 == 0:
            mix.add(t0, wood_mallet(hz(chord[0] + 12), 0.55), pan=-0.28, gain=0.110)
            mix.add(t0 + beat * 2.0, wood_mallet(hz(chord[2] + 12), 0.50), pan=0.22, gain=0.085)
        else:
            mix.add(t0, wood_mallet(hz(chord[1] + 12), 0.55), pan=0.28, gain=0.100)
            mix.add(t0 + beat * 2.0, wood_mallet(hz(chord[2] + 12), 0.50), pan=-0.22, gain=0.080)
            mix.add(t0 + beat * 3.0, wood_mallet(hz(chord[0] + 12), 0.45), pan=0.10, gain=0.070)

    # 石片敲击：只做稀疏的节拍点，音量很小；每两小节才出现一次小过门
    for b in range(bars):
        t0 = float(b) * bar
        mix.add(t0 + beat * 1.5, stone_tick(1450.0), pan=0.35, gain=0.038)
        mix.add(t0 + beat * 3.5, stone_tick(1180.0), pan=-0.35, gain=0.032)
        if b % 2 == 1:
            mix.add(t0 + beat * 3.75, stone_tick(1720.0), pan=0.15, gain=0.026)

    # 后半段加一层高八度木琴，只敲弱拍，制造逼近感
    for b in range(8, bars):
        chord = chords[(b // 2) % 4]
        t0 = float(b) * bar
        mix.add(t0 + beat * 1.0, wood_mallet(hz(chord[1] + 24), 0.35), pan=-0.15, gain=0.045)
        mix.add(t0 + beat * 3.0, wood_mallet(hz(chord[2] + 24), 0.35), pan=0.15, gain=0.038)

    add_reverb(mix, 0.85)
    return mix


# ===================== 曲目 6：登录界面（神秘涌动） =====================

def hold_pad(freq: float, dur: float, attack: float = 1.2,
        release: float = 1.4) -> np.ndarray:
    """保持型 pad：真正的 ADSR —— 起音后**满幅保持**到结尾，只在最后 release 秒收。

    ⚠ 不能直接用 pad()：它内部的 env_adsr 会把 decay 之后的整段都当成 release 斜坡，
      12 秒的音实际从第 2.5 秒起一路衰减到 0，尾巴是静音 —— 那样的曲子接不了循环
      （每 12 秒断一口气）。这一首全靠持续垫底撑氛围，必须换成保持型包络。
    """
    n = max(1, int(dur * SR))
    t = _t(n)
    body = np.zeros(n, dtype=np.float64)
    for det in (-0.004, 0.0, 0.004):
        for k in range(1, 7):
            f = freq * (1.0 + det) * k
            if f >= SR * 0.45:
                break
            body += np.sin(2.0 * math.pi * f * t + 0.37 * k) / (k ** 1.35)
    env = np.ones(n, dtype=np.float64)
    a = max(1, min(n, int(attack * SR)))
    r = max(0, min(n - a, int(release * SR)))
    env[:a] = np.linspace(0.0, 1.0, a, endpoint=False)
    if r > 0:
        env[n - r:] = np.linspace(1.0, 0.0, r)
    return body * env / 3.0


def make_title() -> Mix:
    """登录界面：神秘、涌动、停得住。

    与「原初位面」同一族音色（pad + 钟磬 + 吟唱），但和声换成 B 小调色彩，
    并加一层 50BPM 的缓慢心跳与次低频 drone —— 那张美术的三处漩涡本来就是
    「要被吸进去」的，只空灵不够，得有一点压迫感。

    ⚠ 刻意不写旋律、不做段落推进：登录界面可能被挂着很久，任何一次"高潮"
      都会变成干扰；变化只靠和声块换根音（每 12 秒一次）。
    """
    mix = Mix()
    # B 小调色彩：Bm add9 → Gmaj7 → Em7 → F#m7，每段 12 秒（4 段 = 48 秒整）
    chords = [
        (59, 62, 66, 69),
        (55, 59, 62, 66),
        (52, 55, 59, 62),
        (54, 57, 61, 64),
    ]
    for idx, chord in enumerate(chords):
        start = float(idx * 12)
        # ⚠ 首段几乎无起音、末段几乎无收尾：这首要接成 48 秒循环，
        #   两端都淡到静音的话，循环起来就是「每 48 秒断一次气」
        atk = 0.02 if idx == 0 else 2.4
        rel = 0.02 if idx == len(chords) - 1 else 2.2
        for i, note in enumerate(chord):
            mix.add(start, hold_pad(hz(note), 12.0, atk, rel),
                    pan=(-0.40 + 0.26 * float(i)), gain=0.040)
        # 低音：-12 给和声根（每段换），-24 是贯穿全曲的恒定律动底（不换，见下）
        mix.add(start, bass_note(hz(chord[0] - 12), 12.0, 3.8), gain=0.050)
        # 女声吟唱只给根音与三音，且越靠后越淡，避免变成"有人在唱"
        for i, note in enumerate(chord[:2]):
            mix.add(start, choir(hz(note), 12.0), pan=(-0.2 + 0.4 * float(i)),
                    gain=0.026 - 0.004 * float(idx))

    # 恒定次低频 drone：整 48 秒不断，跨和声块也不换音 —— 它就是"涌动"的底
    # ⚠ 同样要用 hold_pad：synth_drone 的包络也会一路衰减，接缝处会漏气
    mix.add(0.0, hold_pad(hz(35), DUR, 0.05, 0.05), gain=0.040)

    # 心跳：50 BPM 的一强一弱两下（lub-dub），全曲贯穿 —— 「涌动」全靠它
    pulse = 1.2
    t0 = 0.0
    while t0 < DUR - 1.0:
        mix.add(t0, soft_heartbeat(0.55, 62.0, 34.0), gain=0.075)
        mix.add(t0 + 0.26, soft_heartbeat(0.42, 54.0, 30.0), gain=0.042)
        t0 += pulse

    # 古琴泛音：B 羽五声（B D E F# A），平均 6 秒一个音 —— 宁可少，不要多
    plucks = [
        (3.0, 71, -0.22), (9.5, 74, 0.18), (15.0, 78, -0.10), (21.5, 74, 0.24),
        (27.0, 71, 0.12), (33.5, 66, -0.20), (39.0, 69, 0.16), (45.0, 71, -0.14),
    ]
    for start, note, pan in plucks:
        mix.add(start, pluck(hz(note), 2.6, 0.55), pan=pan, gain=0.055)

    # 钟磬：只在段落交界出现，给"这个空间有多大"一个刻度
    for start, note, pan in ((0.0, 83, 0.18), (24.0, 86, -0.16)):
        mix.add(start, bell(hz(note), 7.0), pan=pan, gain=0.045)
    for start in (12.0, 36.0):
        mix.add(start, gong(5.5, 52.0), pan=0.10, gain=0.038)

    # 极轻的风，只在两次钟之间铺一层空气
    for start in (6.0, 30.0):
        mix.add(start, wind_swell(10.0), pan=-0.10, gain=0.010)

    add_reverb(mix, 1.35)
    return mix


def main() -> None:
    # 曲名 → (构建函数, 输出文件名, 峰值, 接缝淡入淡出秒数)
    # ⚠ 单曲重出：python tools/gen_battle_music.py title_veil
    builders = {
        "battle_wuxia": (make_wuxia, "battle_wuxia.wav", 0.84, 0.008),
        "battle_tense": (make_tense, "battle_tense.wav", 0.86, 0.008),
        "battle_epic": (make_epic, "battle_epic.wav", 0.84, 0.008),
        "realm_primordial": (make_primordial, "realm_primordial.wav", 0.78, 0.008),
        "world_continent": (make_continent, "world_continent.wav", 0.62, 0.008),
        # 登录界面首尾是满幅的，交给 loop_title_bgm.py 折叠接缝，不要 8ms 淡出
        "title_veil": (make_title, "title_veil.wav", 0.78, 0.0),
    }
    wanted = sys.argv[1:] or list(builders.keys())
    for key in wanted:
        if key not in builders:
            print("[music] 未知曲名：%s（可选：%s）" % (key, ", ".join(builders.keys())))
            continue
        build, name, peak, seam = builders[key]
        finish(build(), name, peak, seam)


if __name__ == "__main__":
    main()
