#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 AI 生成的整首曲子处理成《万界秘境》能直接循环的 BGM。

用途：登录界面 / 任何需要「一首长曲裁成无缝循环」的场合。
主力调用者是 title_screen.gd 的 BGM_TITLE（assets/audio/bgm/title_veil.wav）。

处理链（顺序不能换）：
  ① 读入任意采样率 / 声道数的 WAV
  ② 20Hz 高通去直流（drone 类垫底最容易积直流，循环点会"咚"一下）
  ③ 重采样到 32kHz（与本项目其余 5 首 BGM 同规格）
  ④ 截取 [offset, offset+seconds+xfade) 这一段
  ⑤ 等功率交叉淡化：把尾巴叠回头部 —— 循环接缝处音量不塌、相位不跳
  ⑥ 峰值归一化到 target_peak，写 16bit PCM WAV

为什么是「尾巴叠回头部」而不是「首尾各淡一下」：
  后者在接缝处会掉一个音量坑（两段都接近 0），循环时能听见"呼吸"；
  前者把尾巴的能量补进头部，接缝处的总能量恒定，听不出断点。

用法：
  python tools/loop_title_bgm.py --src raw.wav --dst assets/audio/bgm/title_veil.wav
  python tools/loop_title_bgm.py --src raw.wav --dst out.wav --seconds 75 --xfade 8 --offset 4.5
"""

from __future__ import annotations

import argparse
import sys
from math import gcd
from pathlib import Path

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, resample_poly, sosfilt

SR_OUT = 32000


def read_wav(path: Path) -> tuple[np.ndarray, int]:
    """读 WAV → (float64 [n, ch] 且峰值 <= 1.0, 采样率)。支持 8/16/24/32bit 与浮点。"""
    sr, data = wavfile.read(str(path))
    if data.dtype == np.uint8:
        x = (data.astype(np.float64) - 128.0) / 128.0
    elif data.dtype == np.int16:
        x = data.astype(np.float64) / 32768.0
    elif data.dtype == np.int32:
        # 32bit 整型既可能是 PCM 也可能是浮点容器，按量级判断
        if np.max(np.abs(data)) > 2_000_000:
            x = data.astype(np.float64) / 2147483648.0
        else:
            x = data.astype(np.float64)
    else:
        x = data.astype(np.float64)
    if x.ndim == 1:
        x = x[:, None]
    return x, sr


def to_sr(x: np.ndarray, sr_in: int, sr_out: int) -> np.ndarray:
    """多相重采样，按 gcd 求最小上/下采样比，避免不必要的中间放大。"""
    if sr_in == sr_out:
        return x
    g = gcd(sr_in, sr_out)
    return resample_poly(x, sr_out // g, sr_in // g, axis=0)


def dc_block(x: np.ndarray, sr: int, cutoff: float = 20.0) -> np.ndarray:
    """20Hz 高通，二阶 Butterworth 零相位。只去直流与次声，不动音乐本体。"""
    sos = butter(2, cutoff, btype="highpass", fs=sr, output="sos")
    return sosfilt(sos, x, axis=0)


def fold_loop(seg: np.ndarray, seconds: int, xfade: float, sr: int) -> np.ndarray:
    """把 seg 的尾巴等功率叠进头部，返回长度 = seconds * sr 的循环体。"""
    n_loop = int(round(seconds * sr))
    n_xf = int(round(xfade * sr))
    head = seg[:n_loop].copy()
    tail = seg[n_loop:n_loop + n_xf]
    n_xf = min(n_xf, len(tail), n_loop)
    if n_xf <= 0:
        return head
    t = np.linspace(0.0, 1.0, n_xf, endpoint=False)
    # t=0 时全部取尾巴（保证 out[0] ≈ 循环末尾的延续），t→1 时全部取头部
    fade_head = np.sin(0.5 * np.pi * t)[:, None]
    fade_tail = np.cos(0.5 * np.pi * t)[:, None]
    head[:n_xf] = head[:n_xf] * fade_head + tail[:n_xf] * fade_tail
    return head


def seam_report(x: np.ndarray, sr: int) -> str:
    """接缝体检：首末样本的跳变量，以及整曲的最大相邻跳变，用来判断有没有"咔"。"""
    if len(x) < 2:
        return "样本过短"
    step_max = float(np.max(np.abs(np.diff(x, axis=0))))
    seam = float(np.max(np.abs(x[0] - x[-1])))
    ratio = seam / step_max if step_max > 1e-9 else 0.0
    verdict = "OK" if ratio < 1.5 else "⚠ 接缝跳变偏大，考虑加大 --xfade"
    return f"接缝跳变 {seam:.5f} / 曲内最大跳变 {step_max:.5f}（{ratio:.2f}×）{verdict}"


def main() -> int:
    ap = argparse.ArgumentParser(description="裁切 + 无缝循环 + 降采样，产出可直接循环的 BGM")
    ap.add_argument("--src", required=True, help="原始整首 WAV")
    ap.add_argument("--dst", required=True, help="输出 WAV 路径")
    ap.add_argument("--seconds", type=int, default=68, help="循环体长度（秒），默认 68")
    ap.add_argument("--xfade", type=float, default=6.0, help="交叠时长（秒），默认 6")
    ap.add_argument("--offset", type=float, default=0.0, help="从第几秒开始截（跳过引子），默认 0")
    ap.add_argument("--target-peak", type=float, default=0.89, help="峰值归一化目标，默认 0.89 ≈ -1dBFS")
    ap.add_argument("--sr", type=int, default=SR_OUT, help=f"输出采样率，默认 {SR_OUT}")
    args = ap.parse_args()

    src, dst = Path(args.src), Path(args.dst)
    if not src.exists():
        print(f"找不到源文件：{src}", file=sys.stderr)
        return 1

    x, sr_in = read_wav(src)
    dur_in = len(x) / sr_in
    print(f"读入 {src.name}：{dur_in:.2f}s / {sr_in}Hz / {x.shape[1]}ch")

    x = dc_block(x, sr_in)
    x = to_sr(x, sr_in, args.sr)
    sr = args.sr

    need = int(round((args.offset + args.seconds + args.xfade) * sr))
    if len(x) < need:
        # 素材比目标短：把循环体压到「素材长度 - 交叠」并明确告警，不静默产出残次品
        args.seconds = max(1, int((len(x) / sr) - args.xfade - args.offset))
        need = int(round((args.offset + args.seconds + args.xfade) * sr))
        print(f"⚠ 素材不足，循环体自动压到 {args.seconds}s")

    start = int(round(args.offset * sr))
    seg = x[start:start + need]
    loop = fold_loop(seg, args.seconds, args.xfade, sr)

    peak = float(np.max(np.abs(loop)))
    if peak > 1e-9:
        loop = loop * (args.target_peak / peak)

    dst.parent.mkdir(parents=True, exist_ok=True)
    pcm = np.clip(loop, -1.0, 1.0)
    wavfile.write(str(dst), sr, (pcm * 32767.0).astype(np.int16))

    size_mb = dst.stat().st_size / 1048576.0
    print(f"输出 {dst}：{args.seconds}s / {sr}Hz / {loop.shape[1]}ch / {size_mb:.1f}MB")
    print(f"峰值 {peak:.3f} → 归一化 {args.target_peak:.3f}")
    print(seam_report(loop, sr))
    print("⚠ 改完 assets 下的音频记得跑：godot --headless --path . --import")
    return 0


if __name__ == "__main__":
    sys.exit(main())
