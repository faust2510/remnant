#!/usr/bin/env python3
"""V4 音频合成器：12 个程序化音效 + 1 首可无缝循环的垫乐。

完全合成（numpy + scipy），不下载、不引用任何第三方音频素材；固定随机种子，重跑结果一致。

    python3 tools/gen_sfx.py            # 重新生成 assets/sfx/*.wav + assets/music/camp_loop.ogg，并打印校验表
    python3 tools/gen_sfx.py --verify   # 只校验现有产物

产物规格：
    * 音效：44.1 kHz / 单声道 / 16-bit PCM wav，0.05-0.6 s，峰值归一化 -3 dBFS，首尾淡入淡出无爆音。
    * 垫乐：44.1 kHz / 立体声，60 s 以上，A 小调，60 BPM，环形构造 + 环形混响，结尾与开头首尾相接。
"""
from __future__ import annotations

import argparse
import math
import struct
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np
from scipy.signal import butter, fftconvolve, sosfilt

ROOT = Path(__file__).resolve().parent.parent
SFX_DIR = ROOT / "assets" / "sfx"
MUSIC_DIR = ROOT / "assets" / "music"
TMP_DIR = ROOT / "tools" / "out"

SR = 44100
PEAK_DB = -3.0
MUSIC_LOOP_SECONDS = 64.0


# --------------------------------------------------------------------------- 基础工具

def N(seconds: float) -> int:
    return int(round(seconds * SR))


def tt(n: int) -> np.ndarray:
    return np.arange(n, dtype=np.float64) / SR


def noise(n: int, seed: int) -> np.ndarray:
    return np.random.default_rng(seed).standard_normal(n)


def tone(freq, n: int, phase0: float = 0.0) -> np.ndarray:
    """正弦；freq 可以是标量，也可以是长度 n 的瞬时频率数组（用于滑音）。"""
    if np.isscalar(freq):
        ph = phase0 + 2.0 * np.pi * float(freq) * tt(n)
    else:
        f = np.asarray(freq, dtype=np.float64)
        ph = phase0 + 2.0 * np.pi * np.cumsum(f) / SR
    return np.sin(ph)


def sweep(f0: float, f1: float, n: int, curve: str = "exp") -> np.ndarray:
    x = np.linspace(0.0, 1.0, n)
    if curve == "exp":
        return f0 * (f1 / f0) ** x
    return f0 + (f1 - f0) * x


def _sos(kind: str, fc, order: int = 2):
    nyq = SR * 0.5
    if kind == "band":
        lo, hi = fc
        return butter(order, [max(lo, 20.0) / nyq, min(hi, 19000.0) / nyq], btype="bandpass", output="sos")
    return butter(order, min(fc, 19000.0) / nyq, btype=kind, output="sos")


def lp(x: np.ndarray, fc: float, order: int = 2) -> np.ndarray:
    return sosfilt(_sos("low", fc, order), x)


def hp(x: np.ndarray, fc: float, order: int = 2) -> np.ndarray:
    return sosfilt(_sos("high", fc, order), x)


def bp(x: np.ndarray, lo: float, hi: float, order: int = 2) -> np.ndarray:
    return sosfilt(_sos("band", (lo, hi), order), x)


def decay_env(n: int, tau: float, attack: float = 0.002) -> np.ndarray:
    env = np.exp(-tt(n) / max(tau, 1e-4))
    a = int(attack * SR)
    if a > 1:
        env[:a] *= 0.5 - 0.5 * np.cos(np.pi * np.arange(a) / a)
    return env


def swell_env(n: int, attack: float, release: float, sustain: float = 1.0) -> np.ndarray:
    env = np.full(n, float(sustain))
    a = max(1, min(int(attack * SR), n))
    r = max(1, min(int(release * SR), n))
    env[:a] *= 0.5 - 0.5 * np.cos(np.pi * np.arange(a) / a)
    env[n - r:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(r) / r)
    return env


def bell_tone(f0: float, n: int) -> np.ndarray:
    """略有非谐分音的钟体：比纯正弦更像“晶体/金属”。"""
    parts = ((1.0, 1.00, 1.0), (2.0, 0.42, 0.62), (3.0, 0.17, 0.45), (4.19, 0.09, 0.30), (5.43, 0.05, 0.22))
    out = np.zeros(n)
    for ratio, amp, dec in parts:
        out += tone(f0 * ratio, n) * amp * np.exp(-tt(n) / (0.11 * dec))
    return out


def make_ir(dur: float, tau: float, seed: int) -> np.ndarray:
    """指数衰减的暗噪声脉冲响应（单位能量），给短音效加一层房间尾。"""
    n = N(dur)
    ir = noise(n, seed) * np.exp(-tt(n) / tau)
    ir = lp(hp(ir, 220.0), 6200.0)
    a = int(0.004 * SR)
    ir[:a] *= np.linspace(0.0, 1.0, a)
    return ir / math.sqrt(float(np.sum(ir * ir)) or 1.0)


def reverb(x: np.ndarray, wet: float, ir: np.ndarray) -> np.ndarray:
    y = fftconvolve(x, ir, mode="full")[: x.size]
    return x + wet * y


def fade(x: np.ndarray, fade_in_ms: float = 1.0, fade_out_ms: float = 8.0) -> np.ndarray:
    n = x.size
    a = min(int(fade_in_ms * SR / 1000.0), n // 2)
    r = min(int(fade_out_ms * SR / 1000.0), n // 2)
    if a > 1:
        x[:a] *= 0.5 - 0.5 * np.cos(np.pi * np.arange(a) / a)
    if r > 1:
        x[n - r:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(r) / r)
    return x


def normalize(x: np.ndarray, db: float = PEAK_DB) -> np.ndarray:
    peak = float(np.max(np.abs(x)))
    if peak <= 1e-9:
        return x
    return x * (10.0 ** (db / 20.0) / peak)


# --------------------------------------------------------------------------- 音效

def s_slash() -> np.ndarray:
    """近战挥砍：一层下扫的气流 + 一层低频推势，短促、有方向感。"""
    n = N(0.24)
    whoosh = bp(noise(n, 11), 480.0, 2700.0) * decay_env(n, 0.075, 0.004)
    body = tone(sweep(310.0, 108.0, n), n) * decay_env(n, 0.09, 0.003) * 0.55
    air = hp(noise(n, 12), 4200.0) * decay_env(n, 0.11, 0.006) * 0.30
    return whoosh * 0.95 + body + air


def s_hit_light() -> np.ndarray:
    """轻击：极短的高频“啪”+ 下行木体，适合高击杀频率，不刺耳。"""
    n = N(0.11)
    click = hp(noise(n, 21), 3200.0) * decay_env(n, 0.008, 0.0006) * 0.65
    body = tone(sweep(420.0, 190.0, n), n) * decay_env(n, 0.035, 0.0015) * 0.95
    knock = bp(noise(n, 22), 900.0, 2400.0) * decay_env(n, 0.02, 0.001) * 0.45
    return click + body + knock


def s_hit_heavy() -> np.ndarray:
    """重击：低频闷响 + 轻微饱和的碎裂声，比轻击更“沉”。"""
    n = N(0.26)
    sub = tone(sweep(122.0, 48.0, n), n) * decay_env(n, 0.085, 0.002) * 1.0
    crunch = np.tanh(2.2 * bp(noise(n, 31), 200.0, 2200.0)) * decay_env(n, 0.045, 0.001) * 0.42
    thud = tone(sweep(220.0, 120.0, n), n) * decay_env(n, 0.05, 0.001) * 0.32
    click = hp(noise(n, 32), 2500.0) * decay_env(n, 0.006, 0.0005) * 0.40
    return sub + crunch + thud + click


def s_enemy_death() -> np.ndarray:
    """敌人溃散：下行“叹息”音 + 沙化尾音，属灵军兵消散而不是血肉打击。"""
    n = N(0.38)
    f = sweep(430.0, 92.0, n)
    voice = tone(f, n) * 0.55 + tone(f * 2.01, n) * 0.16 + tone(f * 3.02, n) * 0.06
    voice *= decay_env(n, 0.15, 0.004)
    puff = lp(noise(n, 41), 2500.0) * decay_env(n, 0.10, 0.006) * 0.32
    return reverb(np.tanh(1.5 * (voice + puff)), 0.22, make_ir(0.28, 0.09, 42))


def s_pickup_gem() -> np.ndarray:
    """拾取宝石：A5->E6 两记钟音，明亮但收得住，重复播放不烦。"""
    n = N(0.30)
    out = np.zeros(n)
    for f0, dt, amp in ((880.0, 0.0, 1.0), (1318.5, 0.055, 0.55)):
        k = int(dt * SR)
        m = n - k
        out[k:] += bell_tone(f0, m) * decay_env(m, 0.10, 0.0015) * amp
    out += hp(noise(n, 51), 5000.0) * decay_env(n, 0.01, 0.0005) * 0.07
    return reverb(out, 0.20, make_ir(0.35, 0.12, 52))


def s_pickup_coin() -> np.ndarray:
    """拾取银币：更短更“金属”，双记高音 ping，和宝石的钟声区分开。"""
    n = N(0.17)
    out = np.zeros(n)
    for f0, dt, amp, tau in ((1568.0, 0.0, 1.0, 0.028), (2093.0, 0.05, 0.6, 0.022)):
        k = int(dt * SR)
        m = n - k
        out[k:] += tone(f0, m) * decay_env(m, tau, 0.0006) * amp
        out[k:] += tone(f0 * 2.76, m) * decay_env(m, tau * 0.6, 0.0004) * amp * 0.22
    out += hp(noise(n, 61), 4000.0) * decay_env(n, 0.008, 0.0004) * 0.14
    return out


def s_level_up() -> np.ndarray:
    """领受升级：A 小三和弦的管风琴齐奏上浮，带高频微光与长混响，是“恩典降临”。"""
    n = N(0.60)
    out = np.zeros(n)
    env = swell_env(n, 0.06, 0.44, 1.0)
    for f0, amp in ((220.0, 1.0), (261.63, 0.85), (329.63, 0.78), (440.0, 0.46), (659.25, 0.16)):
        out += (tone(f0, n) + 0.34 * tone(2.0 * f0, n) + 0.11 * tone(3.0 * f0, n)) * env * amp
    shimmer = tone(1760.0, n) * np.linspace(0.0, 1.0, n) ** 2 * decay_env(n, 0.25, 0.02) * 0.09
    return reverb(out * 0.42 + shimmer, 0.28, make_ir(0.5, 0.18, 71))


def s_fuse() -> np.ndarray:
    """武器合成 / 祝圣：纯五度钟声 + 低频圣坛底 + 上升微光，庄重、明亮、不吵。"""
    n = N(0.55)
    out = np.zeros(n)
    for f0, amp, dt in ((329.63, 1.0, 0.0), (493.88, 0.68, 0.02), (659.25, 0.32, 0.09)):
        k = int(dt * SR)
        m = n - k
        out[k:] += bell_tone(f0, m) * decay_env(m, 0.16, 0.002) * amp
    out += tone(sweep(110.0, 98.0, n), n) * decay_env(n, 0.22, 0.02) * 0.34
    out += hp(noise(n, 81), 6000.0) * np.linspace(0.0, 1.0, n) ** 3 * 0.09
    return reverb(out, 0.30, make_ir(0.55, 0.2, 82))


def s_boss() -> np.ndarray:
    """Boss 出现：55/58.3 Hz 拍频低频 + 小调二度铜管簇，压迫感来自拍频而不是音量。"""
    n = N(0.60)
    sub = (tone(55.0, n) + 0.8 * tone(58.27, n) + 0.32 * tone(110.0, n)) * swell_env(n, 0.05, 0.40, 1.0)
    brass = (0.5 * tone(110.0, n) + 0.45 * tone(116.54, n) + 0.28 * tone(164.81, n) + 0.17 * tone(220.0, n))
    brass = np.tanh(1.8 * brass) * swell_env(n, 0.08, 0.34, 1.0)
    breath = bp(noise(n, 91), 200.0, 4000.0) * swell_env(n, 0.15, 0.38, 1.0) * 0.26
    return reverb((sub * 0.42 + brass * 0.34 + breath) * 0.9, 0.33, make_ir(0.6, 0.22, 92))


def s_hurt() -> np.ndarray:
    """玩家受伤：闷肉击 + 一点撕裂噪声，短、钝、不血腥。"""
    n = N(0.16)
    thud = tone(sweep(240.0, 95.0, n), n) * decay_env(n, 0.055, 0.0015) * 1.0
    body = lp(np.tanh(2.0 * noise(n, 101)), 1200.0) * decay_env(n, 0.04, 0.0015) * 0.42
    tear = bp(noise(n, 102), 1500.0, 3800.0) * decay_env(n, 0.02, 0.001) * 0.22
    return thud + body + tear


def s_defeat() -> np.ndarray:
    """玩家死亡（也复用为 Boss 死亡）：小调三和弦整体下滑 + 次低频坠落 + 长混响。"""
    n = N(0.60)
    out = np.zeros(n)
    for f0, amp in ((110.0, 1.0), (130.81, 0.78), (164.81, 0.66)):
        f = sweep(f0, f0 * 0.72, n)
        out += (tone(f, n) + 0.30 * tone(2.0 * f, n)) * decay_env(n, 0.30, 0.006) * amp
    out += tone(sweep(80.0, 38.0, n), n) * decay_env(n, 0.25, 0.01) * 0.85
    out += lp(noise(n, 111), 900.0) * decay_env(n, 0.28, 0.02) * 0.22
    return reverb(out * 0.7, 0.34, make_ir(0.6, 0.22, 112))


def s_ui() -> np.ndarray:
    """UI 基本音：极短的木质电子滴答；悬停/点击/暂停都靠音高与音量偏移复用它。"""
    n = N(0.07)
    out = tone(1250.0, n) * decay_env(n, 0.012, 0.0006)
    out += tone(2500.0, n) * decay_env(n, 0.007, 0.0004) * 0.32
    out += lp(noise(n, 121), 2500.0) * decay_env(n, 0.004, 0.0003) * 0.22
    return out


SFX_TABLE = (
    # 文件名, 生成函数, 淡入 ms, 设计意图
    ("slash", s_slash, 1.0, "近战挥砍：下扫气流 + 低频推势"),
    ("hit_light", s_hit_light, 1.0, "命中（轻）：高频啪 + 下行木体"),
    ("hit_heavy", s_hit_heavy, 1.0, "命中（重/暴击底）：低频闷响 + 饱和碎裂"),
    ("enemy_death", s_enemy_death, 1.0, "敌人溃散：下行叹息 + 沙化尾"),
    ("pickup_gem", s_pickup_gem, 1.0, "拾取宝石：A5-E6 双钟音"),
    ("pickup_coin", s_pickup_coin, 1.0, "拾取银币：双记金属 ping"),
    ("level_up", s_level_up, 3.0, "领受升级：小三和弦管风琴上浮"),
    ("fuse", s_fuse, 3.0, "合成/祝圣：五度钟声 + 圣坛底"),
    ("boss", s_boss, 3.0, "Boss 出现：拍频低频 + 二度铜管簇"),
    ("hurt", s_hurt, 1.0, "玩家受伤：闷击 + 撕裂噪声"),
    ("defeat", s_defeat, 3.0, "玩家/Boss 死亡：三和弦下滑 + 次低频坠落"),
    ("ui", s_ui, 0.5, "UI 基础滴答（复用于悬停/点击/暂停）"),
)
SFX_MIN_SECONDS = 0.05
SFX_MAX_SECONDS = 0.60


# --------------------------------------------------------------------------- 垫乐

CHORDS = {
    # 根音保持低音区，上方三音做声部交叠，避免糊成一片
    "Am": (110.00, 164.81, 220.00, 261.63),
    "F": (87.31, 130.81, 174.61, 220.00),
    "C": (130.81, 196.00, 261.63, 329.63),
    "G": (98.00, 146.83, 196.00, 246.94),
}
PROGRESSION = ("Am", "F", "C", "G")
FORMANTS_A = ((700.0, 1.00, 90.0), (1090.0, 0.60, 110.0), (2440.0, 0.24, 160.0))


def _organ(f0: float, dur: float, channel: int, amp: float) -> np.ndarray:
    n = N(dur)
    det = 5.0 if channel == 0 else -5.0
    base = f0 * 2.0 ** (det / 1200.0)
    x = tone(base, n) + 0.44 * tone(2.0 * base, n) + 0.17 * tone(3.0 * base, n) + 0.07 * tone(4.0 * base, n)
    # 管风琴 tremulant：极浅的振幅抖动
    ph = 0.0 if channel == 0 else 1.7
    x *= 1.0 + 0.045 * np.sin(2.0 * np.pi * 5.2 * tt(n) + ph)
    return x * swell_env(n, 0.45, 1.15, 1.0) * amp


def _choir(f0: float, dur: float, channel: int, amp: float) -> np.ndarray:
    n = N(dur)
    t = tt(n)
    vib = 2.0 * np.pi * 4.6 * t + (0.0 if channel == 0 else 2.1)
    cents = (6.0 if channel == 0 else -6.0) * (1.0 + 0.35 * np.sin(vib))
    x = np.zeros(n)
    k = 1
    while f0 * k < 3200.0:
        fh = f0 * k * 2.0 ** (cents / 1200.0)
        w = 0.0
        for fc, fa, fw in FORMANTS_A:
            w += fa * math.exp(-0.5 * ((f0 * k - fc) / fw) ** 2)
        w = w / (k ** 0.75) + 0.02
        x += tone(fh, n) * w
        k += 1
    return x * swell_env(n, 0.60, 1.30, 1.0) * amp


def _pedal(f0: float, dur: float, amp: float) -> np.ndarray:
    n = N(dur)
    x = tone(f0, n) + 0.35 * tone(2.0 * f0, n) + 0.15 * tone(3.0 * f0, n)
    return x * swell_env(n, 0.9, 1.4, 1.0) * amp


def _add_wrap(buf: np.ndarray, i0: int, sig: np.ndarray) -> None:
    L = buf.size
    n = sig.size
    i0 %= L
    end = i0 + n
    if end <= L:
        buf[i0:end] += sig
    else:
        k = L - i0
        buf[i0:] += sig[:k]
        buf[: end - L] += sig[k:]


def _reverb_circular(x: np.ndarray, ir: np.ndarray, wet: float) -> np.ndarray:
    """环形卷积：混响尾巴绕回开头，循环接缝处不会有断掉的残响。"""
    L = x.size
    irw = np.zeros(L)
    m = min(ir.size, L)
    irw[:m] = ir[:m]
    y = np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(irw), L)
    return x + wet * y


def build_music() -> tuple[np.ndarray, np.ndarray]:
    bpm = 60.0
    bar = 60.0 / bpm * 4.0            # 4 秒一小节
    bars = 16                          # 16 x 4 s = 64 s
    L = int(round(bar * bars * SR))
    left = np.zeros(L)
    right = np.zeros(L)

    note_dur = bar * 1.20              # 尾音压过下一小节，段落之间不留硬缝
    bass_dur = bar * 1.05

    organ_cache: dict = {}
    choir_cache: dict = {}
    bass_cache: dict = {}

    def organ(f0, ch):
        key = (round(f0, 3), ch)
        if key not in organ_cache:
            organ_cache[key] = _organ(f0, note_dur, ch, 0.30)
        return organ_cache[key]

    def choir(f0, ch):
        key = (round(f0, 3), ch)
        if key not in choir_cache:
            choir_cache[key] = _choir(f0, note_dur, ch, 0.15)
        return choir_cache[key]

    def pedal(f0):
        key = round(f0, 3)
        if key not in bass_cache:
            bass_cache[key] = _pedal(f0, bass_dur, 0.26)
        return bass_cache[key]

    for b in range(bars):
        name = PROGRESSION[b % len(PROGRESSION)]
        tones = CHORDS[name]
        start = int(round(b * bar * SR))
        full = b >= 2                       # 前两小节只留 pedal + 低层，慢慢浮上来
        thin = b >= 12                      # 最后四小节抽掉合唱层，收气
        for ch, buf in ((0, left), (1, right)):
            for i, f0 in enumerate(tones):
                _add_wrap(buf, start, organ(f0, ch))
                if full and not thin:
                    _add_wrap(buf, start, choir(f0 * 2.0, ch))
                if i == 0:
                    _add_wrap(buf, start, pedal(f0 * 0.5))

    # 稀疏的高音对句：只在 4/6/8/10/12/14 小节落一个长音，给 64 秒一个“呼吸点”
    for b, f0 in ((4, 880.0), (6, 1318.5), (8, 1046.5), (10, 880.0), (12, 1318.5), (14, 987.77)):
        start = int(round(b * bar * SR))
        n = N(bar * 1.6)
        sig = tone(f0, n) * swell_env(n, 1.1, 1.9, 1.0) * 0.055
        _add_wrap(left, start, sig)
        _add_wrap(right, start, sig)

    # 房间空气：极低电平的带通噪声，环形（噪声本身不需要首尾相接）
    for ch, buf in ((0, left), (1, right)):
        air = bp(noise(L, 201 + ch), 2000.0, 6000.0) * 0.006
        buf += air

    # 环形混响，左右用不同种子的 IR 制造宽度
    ir_l = make_ir(3.2, 0.95, 301)
    ir_r = make_ir(3.2, 0.95, 302)
    left = _reverb_circular(left, ir_l, 0.38)
    right = _reverb_circular(right, ir_r, 0.38)

    left = hp(left, 28.0)
    right = hp(right, 28.0)
    peak = max(float(np.max(np.abs(left))), float(np.max(np.abs(right))))
    gain = 10.0 ** (PEAK_DB / 20.0) / max(peak, 1e-9)
    return left * gain, right * gain


# --------------------------------------------------------------------------- 写出

def write_wav(path: Path, data: np.ndarray, channels: int = 1) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = np.clip(np.round(data * 32767.0), -32768, 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def prune_stale() -> None:
    """删掉本表之外的历史音效（含 .import），保证 assets/sfx 只有当前这一套。"""
    keep = {f"{name}.wav" for name, _fn, _fi, _i in SFX_TABLE}
    for path in sorted(SFX_DIR.glob("*.wav")):
        if path.name not in keep:
            path.unlink(missing_ok=True)
            Path(str(path) + ".import").unlink(missing_ok=True)
            print(f"  prune {path.name}")


def generate_sfx() -> None:
    for name, fn, fade_in, _intent in SFX_TABLE:
        x = np.asarray(fn(), dtype=np.float64)
        x = fade(x, fade_in, 8.0)
        x = normalize(x, PEAK_DB)
        # 首尾必须归零，否则 Godot 里会听到爆音
        x[0] = 0.0
        x[-1] = 0.0
        write_wav(SFX_DIR / f"{name}.wav", x, 1)
        print(f"  sfx  {name}.wav  {x.size / SR:.3f}s")


def generate_music() -> Path:
    left, right = build_music()
    TMP_DIR.mkdir(parents=True, exist_ok=True)
    tmp_wav = TMP_DIR / "camp_loop.wav"
    inter = np.empty(left.size * 2, dtype=np.float64)
    inter[0::2] = left
    inter[1::2] = right
    write_wav(tmp_wav, inter, 2)
    MUSIC_DIR.mkdir(parents=True, exist_ok=True)
    ogg = MUSIC_DIR / "camp_loop.ogg"
    ffmpeg = _find_ffmpeg()
    if ffmpeg is None:
        wav_out = MUSIC_DIR / "camp_loop.wav"
        write_wav(wav_out, inter, 2)
        print("  music camp_loop.wav  (ffmpeg 不可用，落 wav)")
        return wav_out
    # 优先 libvorbis，退而用 ffmpeg 自带的 vorbis 编码器（-strict -2）；
    # 两者都逐样本对齐，解码后长度 == 源长度，循环才不会漂移。
    attempts = (
        ["-c:a", "libvorbis", "-qscale:a", "6"],
        ["-c:a", "vorbis", "-strict", "-2", "-qscale:a", "8"],
    )
    last_err = ""
    for codec in attempts:
        try:
            subprocess.run(
                [ffmpeg, "-y", "-hide_banner", "-loglevel", "error", "-i", str(tmp_wav)]
                + codec
                + ["-ar", str(SR), "-ac", "2", "-map_metadata", "-1", str(ogg)],
                check=True, capture_output=True, text=True,
            )
            last_err = ""
            break
        except subprocess.CalledProcessError as exc:
            last_err = (exc.stderr or "").strip().splitlines()[-1:] and (exc.stderr or "").strip().splitlines()[-1] or "encode failed"
            ogg.unlink(missing_ok=True)
    if last_err or not ogg.exists():
        wav_out = MUSIC_DIR / "camp_loop.wav"
        write_wav(wav_out, inter, 2)
        print(f"  music camp_loop.wav  ({last_err or 'no encoder'} -> wav 兜底)")
        return wav_out
    print(f"  music camp_loop.ogg  {left.size / SR:.3f}s  ({codec[1]})")
    return ogg


def _find_ffmpeg():
    for cand in ("/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "ffmpeg"):
        try:
            subprocess.run([cand, "-version"], capture_output=True, check=True)
            return cand
        except (OSError, subprocess.CalledProcessError):
            continue
    return None


# --------------------------------------------------------------------------- 校验

def _wav_stats(path: Path) -> dict:
    with wave.open(str(path), "rb") as w:
        ch, sw, sr, frames = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(frames)
    if sw != 2:
        raise SystemExit(f"{path.name}: 期望 16-bit PCM，实际 {sw * 8}-bit")
    data = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
    peak = float(np.max(np.abs(data))) if data.size else 0.0
    rms = float(np.sqrt(np.mean(data * data))) if data.size else 0.0
    return {
        "dur": frames / float(sr),
        "sr": sr,
        "ch": ch,
        "peak_db": 20.0 * math.log10(peak) if peak > 0 else -999.0,
        "rms_db": 20.0 * math.log10(rms) if rms > 0 else -999.0,
        "head": float(abs(data[0])) if data.size else 0.0,
        "tail": float(abs(data[-1])) if data.size else 0.0,
    }


def _ogg_stats(path: Path, ffprobe: str, ffmpeg: str) -> dict:
    probe = subprocess.run(
        [ffprobe, "-v", "error", "-show_entries", "format=duration:stream=sample_rate,channels",
         "-of", "default=noprint_wrappers=1", str(path)],
        capture_output=True, text=True, check=True,
    ).stdout
    vals = dict(line.split("=", 1) for line in probe.strip().splitlines() if "=" in line)
    # 保持立体声解码：单声道下混会让峰值失真（左右相位不同），测不到真实峰值
    raw = subprocess.run(
        [ffmpeg, "-v", "error", "-i", str(path), "-f", "s16le", "-ac", "2", "-ar", str(SR), "pipe:1"],
        capture_output=True, check=True,
    ).stdout
    data = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
    peak = float(np.max(np.abs(data))) if data.size else 0.0
    rms = float(np.sqrt(np.mean(data * data))) if data.size else 0.0
    return {
        "dur": float(vals.get("duration", 0.0)),
        "sr": int(vals.get("sample_rate", 0)),
        "ch": int(vals.get("channels", 0)),
        "peak_db": 20.0 * math.log10(peak) if peak > 0 else -999.0,
        "rms_db": 20.0 * math.log10(rms) if rms > 0 else -999.0,
        "decoded": data.size,
    }


def verify(expect_files: bool = True) -> int:
    ok = True
    print("\n== 音效校验（wave 模块读取 + 峰值/首尾检查）==")
    print("| 文件 | 时长 s | 采样率 | 声道 | 峰值 dBFS | RMS dBFS | 首样点 | 尾样点 | 判定 |")
    print("| --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    for name, _fn, _fi, _intent in SFX_TABLE:
        path = SFX_DIR / f"{name}.wav"
        if not path.exists():
            print(f"| {name}.wav | - | - | - | - | - | - | - | 缺失 |")
            ok = False
            continue
        st = _wav_stats(path)
        verdict = "ok"
        if not (SFX_MIN_SECONDS <= st["dur"] <= SFX_MAX_SECONDS):
            verdict = f"时长越界({SFX_MIN_SECONDS}-{SFX_MAX_SECONDS})"
        if st["sr"] != SR or st["ch"] != 1:
            verdict = "格式不符"
        if abs(st["peak_db"] - PEAK_DB) > 0.15:
            verdict = "峰值不是 -3dBFS"
        if st["head"] > 1e-4 or st["tail"] > 1e-4:
            verdict = "首尾未归零"
        if verdict != "ok":
            ok = False
        print(f"| {name}.wav | {st['dur']:.3f} | {st['sr']} | {st['ch']} | {st['peak_db']:.2f} | "
              f"{st['rms_db']:.2f} | {st['head']:.5f} | {st['tail']:.5f} | {verdict} |")

    print("\n== 垫乐校验（ffprobe + ffmpeg 解码取峰值）==")
    ogg = MUSIC_DIR / "camp_loop.ogg"
    wav = MUSIC_DIR / "camp_loop.wav"
    ffmpeg = _find_ffmpeg()
    if ogg.exists() and ffmpeg is not None:
        ffprobe = str(Path(ffmpeg).with_name("ffprobe"))
        st = _ogg_stats(ogg, ffprobe, ffmpeg)
        frames = st["decoded"] // max(st["ch"], 1)
        verdict = "ok"
        if not (60.0 <= st["dur"] <= 90.0):
            verdict = "时长不在 60-90s"
        if st["sr"] != SR:
            verdict = "采样率不符"
        # 有损编码会有 <1 dB 的过冲，只要不越 0 dBFS 就正常
        if st["peak_db"] > -1.0:
            verdict = "峰值可能削波"
        if abs(frames - round(st["dur"] * SR)) > SR * 0.02:
            verdict = "解码帧数与时长不符（循环会漂移）"
        if verdict != "ok":
            ok = False
        print(f"| camp_loop.ogg | {st['dur']:.3f} | {st['sr']} | {st['ch']} | {st['peak_db']:.2f} | "
              f"{st['rms_db']:.2f} | 解码帧 {frames}（源 {round(st['dur'] * SR)}） | {verdict} |")
    elif wav.exists():
        st = _wav_stats(wav)
        print(f"| camp_loop.wav | {st['dur']:.3f} | {st['sr']} | {st['ch']} | {st['peak_db']:.2f} | "
              f"{st['rms_db']:.2f} | - | wav 兜底 |")
    else:
        print("| camp_loop | 缺失 |")
        if expect_files:
            ok = False

    print("\n== 循环接缝检查（wav 源）==")
    tmp_wav = TMP_DIR / "camp_loop.wav"
    if tmp_wav.exists():
        with wave.open(str(tmp_wav), "rb") as w:
            frames = w.getnframes()
            raw = w.readframes(frames)
        data = np.frombuffer(raw, dtype="<i2").astype(np.float64).reshape(-1, 2)
        d = np.abs(np.diff(data, axis=0))
        seam = float(np.max(np.abs(data[0] - data[-1])))
        typical = float(np.percentile(d.max(axis=1), 99.0))
        print(f"接缝跳变 {seam:.5f} / 相邻样点 99 分位 {typical:.5f}"
              f" -> {'连续' if seam <= typical * 2.0 else '可能有缝'}")
    return 0 if ok else 1


def main() -> int:
    ap = argparse.ArgumentParser(description="V4 音频合成器")
    ap.add_argument("--verify", action="store_true", help="只校验，不重新生成")
    args = ap.parse_args()
    if not args.verify:
        print("== 生成音效 ==")
        generate_sfx()
        prune_stale()
        print("== 生成垫乐 ==")
        generate_music()
    return verify(expect_files=True)


if __name__ == "__main__":
    sys.exit(main())