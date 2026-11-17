#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""棋盘棋子平衡回合器（2026-11-07）

把 `tools/match_strength_probe.tscn` 的实测日志变成两张可以直接写回
`scripts/match/match_db.gd` 的表，并回答两个问题：
  ① 这一轮量完，哪些棋子还在带外（有效身板 / 输出 / 胜点）；
  ② 下一轮的 `ATTACK_CALIB` 与 `MEASURED_EHP_MULT` 该填多少。

口径（不要凭手感改）：
  有效身板 = 面板 × 实测减免，目标 = PIECE_HP_BASE × FACTORS.hp
  实测输出 ÷ 名义（A 口径，30 秒窗 = 一场同级对决的寿命），目标 1.00
  ⇒ 减免进 `MEASURED_EHP_MULT`，输出进 `ATTACK_CALIB`；
     `FACTORS` 两列是**设计角色**，本工具永远不动它。
  ⚠ 官方判据是「实测 ÷ 名义」（日志第 5 列），**不是**第 6 列那个「除以基准自检」的指数：
     基准自检会把量尺自己的二阶段时机耦合进每一行，面板一变就整体平移。

用法（在项目根）：
  python tools/match_balance_pass.py --ehp output/ms2_ehp.log --eff output/ms5_effA.log \\
      --death output/ms5_death.log --samples 8
  加 --apply --round 3 就直接写回 match_db.gd（只换数字与行尾那条 ÷x.xx 注释）。
"""
import argparse, glob, io, math, os, re

BAND_LO, BAND_HI = 0.86, 1.18
NAME = {"boss_huyao": "虎妖", "boss_01": "刀客", "boss_01_c": "剑客", "boss_02": "两仪",
        "boss_02_b": "定阵", "boss_02_c": "气君", "boss_03": "赫连霄", "boss_03_b": "离照",
        "boss_03_c": "晏无咎", "boss_04": "观澜", "boss_04_b": "执烛", "boss_04_c": "叠纸",
        "world_core_lianqi": "古猿", "world_core_zhuji": "苍角",
        "world_core_jiedan": "火麟", "world_core_shihou": "石犼"}


def table_of(s, name):
    i = s.find("const %s :=" % name)
    if i < 0:
        return {}
    seg = s[i:s.find("\n}", i) + 2]
    return {m.group(1): float(m.group(2))
            for m in re.finditer(r'"([\w_]+)":\s*([-\d.]+)', seg)}


def read_db(path):
    s = io.open(path, encoding="utf-8", errors="replace").read()
    fac = {m.group(1): (float(m.group(2)), float(m.group(3)))
           for m in re.finditer(r'"([\w_]+)"\s*:\s*\[(\d+\.\d+),\s*(\d+\.\d+)\]', s)}
    hp_base = float(re.search(r"const PIECE_HP_BASE := ([\d.]+)", s).group(1))
    dps_base = float(re.search(r"const PIECE_DPS_BASE := ([\d.]+)", s).group(1))
    return fac, table_of(s, "ATTACK_CALIB"), table_of(s, "MEASURED_EHP_MULT"), hp_base, dps_base


def lines(fn):
    if not fn or not os.path.exists(fn):
        return []
    return io.open(fn, encoding="utf-8", errors="replace").read().splitlines()


def parse_ehp(fns):
    out = {}
    for fn in fns:
        for ln in lines(fn):
            if not (ln.startswith("MS EHP boss") or ln.startswith("MS EHP world")) or "单发" in ln:
                continue
            t = ln.split()
            out[t[2]] = (float(t[3]), float(t[5]))
    return out


def parse_selfcheck(fns):
    """`MS EFF 基准自检 boss_02 打量尺 = 988 DPS（名义 855）` ⇒ 量尺**自己**作为一张牌的读数。

    eff 轴向会跳过 `id == ref` 的那只（它是对面的靶子），所以量尺作为棋子时
    在表里没有行 —— 但它是可被玩家选的一张牌，同样要在带内。基准自检那一对
    镜像局（量尺打量尺）就是它的样本，这里把它接回来参与折算。"""
    out = {}
    for fn in fns:
        for ln in lines(fn):
            if "基准自检" not in ln:
                continue
            m = re.search(r"基准自检 (\S+) 打量尺 = ([\d.]+) DPS（名义 ([\d.]+)）", ln)
            if m:
                out[m.group(1)] = float(m.group(2)) / max(float(m.group(3)), 1.0)
    return out


def parse_eff(fns):
    """id -> (实测÷名义, 杀尺, 同格极差%, 自己掉血%, 组内σ%, ±SE%)。后给的日志覆盖先给的。

    新表头末尾多了「组内σ / ±SE」两列，所以按**空白切词**、从"杀尺"往回数，不写死列号。
    ⚠ 老日志没这两列；从"杀尺"往回数会正好抓到「极差 / 先后手差」当成 σ 与 SE，
    而先后手差是棋子的位置依赖、不是噪声，拿它当 SE 会把置信度算反方向。
    所以先认这个文件自己的表头：表头里没有"组内σ"就当没有（退回 None，由 se_eff 用极差保守估算）。"""
    out = {}
    for fn in fns:
        ls = lines(fn)
        has_se = any(ln.startswith("MS EFF 卡") and "组内σ" in ln for ln in ls)
        for ln in ls:
            if not (ln.startswith("MS EFF boss") or ln.startswith("MS EFF world")):
                continue
            if "生成失败" in ln:
                continue
            t = ln.split()
            mm = re.search(r"杀尺 (\d+)/(\d+)", ln)
            sig = se = None
            k = t.index("杀尺") if has_se and "杀尺" in t else -1
            if k >= 2:
                try:
                    sig = float(t[k - 2].rstrip("%"))
                    se = float(t[k - 1].rstrip("%"))
                except ValueError:
                    sig = se = None
            out[t[2]] = (float(t[5]), mm.group(0) if mm else "",
                         float(t[9].rstrip("%")), float(t[7].rstrip("%")), sig, se)
    return out


def parse_death(fns):
    out = {}
    for fn in fns:
        for ln in lines(fn):
            m = re.search(r"MS DEATH ([\w_]+)\s+>>> 胜点 ([\d.]+) / (\d+) = (\d+)%", ln)
            if m:
                out[m.group(1)] = (float(m.group(2)), int(m.group(3)), int(m.group(4)))
    return out


def newest(pat):
    f = sorted(glob.glob(pat), key=os.path.getmtime)
    return f[-1] if f else None


# 极差 → σ 的 d2 常数（ASTM/SPC 表，按样本数 n 查）。
# ⚠ 日志里那一列是 **极差 (max−min)/均值**，不是 σ；早先这里写死 1.128 = d2(n=2)，
#   等于把 8 样本的极差当成 2 样本的，σ 被夸大约 2.5 倍、SE 跟着夸大，
#   结果是"整池置信不足"这种假象。换算错了比不换算更坏。
D2 = [0.0, 0.0, 1.128, 1.693, 2.059, 2.326, 2.534, 2.704, 2.847, 2.970, 3.079,
      3.171, 3.258, 3.338, 3.408, 3.472, 3.532, 3.587, 3.635, 3.680, 3.720]


def d2_of(n):
    if n <= 1:
        return 1e9
    if n < len(D2):
        return D2[n]
    return D2[-1] + 0.02 * (n - len(D2) + 1)


def se_of(spread_pct, samples):
    """SE% = 极差 / d2(n) / sqrt(n)。"""
    n = max(int(samples), 1)
    return spread_pct / d2_of(n) / math.sqrt(n)


def se_eff(e, samples):
    """优先用探针直接打出来的「组内 σ ÷ √n」；老日志没有这两列，退回极差当 σ 的保守上界。"""
    if not e:
        return None
    if len(e) > 5 and e[5] is not None:
        return e[5]
    if not e[2]:
        return None          # 基准自检那行是合成进池的，没有真实散布，别给它挂"高置信"
    return se_of(e[2], samples)


def conf(spread_pct, samples, se=None):
    if se is None:
        if not spread_pct:
            return "-"
        se = se_of(spread_pct, samples)
    if se > 15:
        return "低 ±%.0f%%" % se
    if se > 8:
        return "中 ±%.0f%%" % se
    return "高 ±%.0f%%" % se


def apply_db(path, new_cal, new_mit, mit_changed, rnd):
    """只换数字（calib 连同行尾那条 ÷x.xx 注释一起重写），其它一个字不碰。"""
    raw = io.open(path, encoding="utf-8", newline="").read()
    nl = "\r\n" if "\r\n" in raw else "\n"
    t = raw.replace("\r\n", "\n")
    if new_cal:
        i0 = t.find("const ATTACK_CALIB :=")
        j0 = t.find("\n}", i0) + 2
        block, done = t[i0:j0], []
        for key, new in sorted(new_cal.items()):
            # 只吃掉「键 + 数字」，逗号与行尾注释原样留在原地
            pat = r'("%s"\s*:\s*)([-\d.]+)' % re.escape(key)
            m = re.search(pat, block)
            if not m:
                print("!! ATTACK_CALIB 里没有 %s —— 不擅自加行" % key)
                continue
            old = float(m.group(2))
            # ⚠ 只换数字，**行尾注释一个字都不动**：自动改注释会把"旧 3931 ÷0.74"这类
            # 已经过期的算式留在代码里，比不改更坏。审计说明由人按轮次重写一遍。
            rep = m.group(1) + "%d.0" % round(new)
            block = block[:m.start()] + rep + block[m.end():]
            done.append((key, old, new))
        t = t[:i0] + block + t[j0:]
        print("### 写回 ATTACK_CALIB（%d 只）" % len(done))
        for k, o, n in done:
            print("  %-22s %10.0f → %10.0f" % (k, o, n))
    if new_mit and mit_changed:
        i1 = t.find("const MEASURED_EHP_MULT :=")
        j1 = t.find("\n}", i1) + 2
        block = t[i1:j1]
        for key, new in new_mit.items():
            block, n = re.subn('("%s":\\s*)[\\d.]+' % re.escape(key),
                               lambda m, v=new: m.group(1) + "%.2f" % v, block)
            if not n:
                print("!! MEASURED_EHP_MULT 里没有 %s" % key)
        t = t[:i1] + block + t[j1:]
        print("### 写回 MEASURED_EHP_MULT（只在有减免变化 >0.08 时）")
    io.open(path, "w", encoding="utf-8", newline=nl).write(t)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default="scripts/match/match_db.gd")
    ap.add_argument("--ehp", action="append", default=[])
    ap.add_argument("--eff", action="append", default=[])
    ap.add_argument("--death", action="append", default=[])
    ap.add_argument("--samples", type=int, default=8, help="每只的样本数（= 2 侧 × reps）")
    ap.add_argument("--apply", action="store_true", help="把建议值写回 match_db.gd")
    ap.add_argument("--round", default="", help="写回注释里标的轮次")
    a = ap.parse_args()
    ehp_f = a.ehp or [n for n in [newest("output/*ehp*.log")] if n]
    eff_f = a.eff or [n for n in [newest("output/*eff*.log")] if n]
    dth_f = a.death or [n for n in [newest("output/*death*.log")] if n]
    fac, cal, mit_old, HP, DPS = read_db(a.db)
    ehp, eff, dth = parse_ehp(ehp_f), parse_eff(eff_f), parse_death(dth_f)
    selfcheck = parse_selfcheck(eff_f)
    for k, v in selfcheck.items():
        if k not in eff and v > 0:
            eff[k] = (v, "基准自检（镜像局）", 0.0, 0.0, None, None)
            print("↪ 量尺 %s 作为棋子用基准自检补一行：实测÷名义 = %.2f" % (k, v))
    print("读入：ehp=%s eff=%s death=%s" % (ehp_f, eff_f, dth_f))
    print("设计带 ±20%% = %.2f~%.2f ｜ 血量基准 %.0f ｜ DPS 基准 %.0f ｜ 样本 %d\n"
          % (BAND_LO, BAND_HI, HP, DPS, a.samples))
    hdr = ["卡", "名", "面板血", "有效HP实测", "HP比设计", "建议减免", "名义DPS",
           "实测÷名义", "现calib", "建议calib", "杀尺", "胜点", "置信", "判语"]
    print("| " + " | ".join(hdr) + " |")
    print("|" + "|".join(["---"] * len(hdr)) + "|")
    off_hp, off_dps, off_win, lowconf = [], [], [], []
    new_mit, new_cal, rows = {}, {}, []
    for id_ in fac:
        f_hp, f_dps = fac[id_]
        design = HP * f_hp
        panel = design / mit_old.get(id_, 1.0)
        note = []
        geo_eff = ratio_hp = meas_mit = float("nan")
        if id_ in ehp:
            p, m = ehp[id_]
            geo_eff = math.sqrt(max(p, 1.0) * max(m, 1.0))
            ratio_hp = geo_eff / design
            meas_mit = geo_eff / panel
            new_mit[id_] = round(meas_mit, 2)
            if not (BAND_LO <= ratio_hp <= BAND_HI):
                off_hp.append("%s %.2f" % (NAME[id_], ratio_hp))
            if abs(meas_mit - mit_old.get(id_, 1.0)) > 0.08:
                note.append("减免该更新 %.2f→%.2f" % (mit_old.get(id_, 1.0), meas_mit))
        e = eff.get(id_)
        ratio_dps = float("nan")
        if e and e[0] > 0:
            ratio_dps = e[0]
            new_cal[id_] = cal[id_] / ratio_dps
            if not (BAND_LO <= ratio_dps <= BAND_HI):
                off_dps.append("%s %.2f" % (NAME[id_], ratio_dps))
            if se_eff(e, a.samples) is not None and se_eff(e, a.samples) > 10:
                lowconf.append("%s(±%.0f%%)" % (NAME[id_], se_eff(e, a.samples)))
        w = dth.get(id_)
        if w:
            if w[2] <= 20:
                off_win.append("%s %d%%" % (NAME[id_], w[2]))
            elif w[2] >= 90 and w[1] >= 4:
                off_win.append("%s %d%%(饱和)" % (NAME[id_], w[2]))
        rows.append((id_, ratio_dps, [id_, NAME.get(id_, "?"), "%.0f" % panel,
                                      "%.0f" % geo_eff, "%.2f" % ratio_hp, "%.2f" % meas_mit,
                                      "%.0f" % (DPS * f_dps), "%.2f" % ratio_dps,
                                      "%.0f" % cal.get(id_, 0), "%.0f" % new_cal.get(id_, 0),
                                      e[1] if e else "-",
                                      "%d%%(%d/%d)" % (w[2], w[0], w[1]) if w else "-",
                                      conf(e[2] if e else None, a.samples, se_eff(e, a.samples)), " ".join(note)]))
    for _, key, cells in sorted(rows, key=lambda r: -(r[1] if r[1] == r[1] and not math.isnan(r[1]) else 0)):
        print("| " + " | ".join(cells) + " |")
    mit_changed = any(abs(new_mit.get(k, v) - v) > 0.08 for k, v in mit_old.items())
    print("\n带外：有效身板 %s ｜ 输出 %s ｜ 胜负 %s" % (off_hp or "无", off_dps or "无", off_win or "无"))
    if lowconf:
        print("⚠ 置信不足（±SE>10%%，读不出带边），这几行的建议值先别落盘：%s" % " ".join(lowconf))
    if a.apply:
        apply_db(a.db, new_cal, new_mit, mit_changed, a.round)
    else:
        print("\n（加 --apply --round N 就直接写回；现在只出报告）")


if __name__ == "__main__":
    main()
