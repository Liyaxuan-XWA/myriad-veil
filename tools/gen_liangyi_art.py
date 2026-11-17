"""程序化生成两仪真人的骨骼分件与预览（2026-10-27）。

不需要外部生图配额：所有形状由 PIL 绘制，输出到
assets/characters/boss/liangyi_rig/。换正式美术时直接覆盖同名 PNG，
rig.tres 的关节/偏移不用改（分件都是整画布 900×720，offset = -joint）。
"""
from PIL import Image, ImageDraw, ImageFilter
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _art_common as ac  # noqa: E402

W, H = 900, 720
S = 3
OUT = "assets/characters/boss/liangyi_rig"
INK = (18, 20, 24, 255)
INK2 = (38, 42, 50, 255)
WHITE = (226, 220, 206, 255)
WHITE2 = (244, 240, 228, 255)
GOLD = (196, 154, 70, 255)
GOLD_L = (240, 210, 132, 255)
CYAN = (74, 168, 180, 255)
CYAN_L = (150, 228, 236, 255)
SKIN = (210, 182, 154, 255)
SKIN_D = (176, 144, 118, 255)
HAIR = (16, 16, 20, 255)


def canvas():
    return Image.new("RGBA", (W * S, H * S), (0, 0, 0, 0))


def sc(v):
    return int(round(v * S))


def pt(x, y):
    return (sc(x), sc(y))


def ell(d, box, fill=None, outline=None, width=1):
    d.ellipse([sc(box[0]), sc(box[1]), sc(box[2]), sc(box[3])],
              fill=fill, outline=outline, width=sc(width))


def poly(d, pts, fill=None, outline=None, width=1):
    d.polygon([pt(x, y) for x, y in pts], fill=fill)
    if outline:
        d.line([pt(x, y) for x, y in pts] + [pt(pts[0][0], pts[0][1])],
               fill=outline, width=sc(width), joint="curve")


def line(d, pts, fill, width=2):
    d.line([pt(x, y) for x, y in pts], fill=fill, width=sc(width), joint="curve")


def save(img, name):
    # ⚠ 先缩到 900×720 再润色：轮廓一个像素都不动，rig.tres 的锚点因此不用改
    img = img.resize((W, H), Image.LANCZOS)
    img = ac.polish(img)
    p = os.path.join(OUT, name)
    img.save(p)
    print("saved", p)


def make_body():
    body = canvas()
    d = ImageDraw.Draw(body)
    poly(d, [(318, 640), (590, 640), (610, 668), (292, 668)], fill=(0, 0, 0, 80))
    poly(d, [(392, 232), (452, 232), (452, 650), (300, 650), (340, 400)], fill=INK)
    # 竖向衣褶（墨半）：两条被布面裁住的暗带 + 一条提亮带
    fold_layer = Image.new("RGBA", body.size, (0, 0, 0, 0))
    fd = ImageDraw.Draw(fold_layer)
    fd.polygon([pt(360, 300), pt(372, 300), pt(348, 646), pt(332, 646)], fill=(0, 0, 0, 90))
    fd.polygon([pt(404, 300), pt(414, 300), pt(404, 646), pt(390, 646)], fill=(0, 0, 0, 70))
    fd.polygon([pt(386, 320), pt(394, 320), pt(388, 646), pt(378, 646)], fill=(220, 236, 240, 26))
    body = Image.alpha_composite(body, fold_layer.filter(ImageFilter.GaussianBlur(sc(3))))
    d = ImageDraw.Draw(body)
    poly(d, [(452, 232), (512, 232), (558, 400), (600, 650), (452, 650)], fill=WHITE)
    # 竖向衣褶（白半）：灰金暗带 + 冷白提亮带
    fold2 = Image.new("RGBA", body.size, (0, 0, 0, 0))
    gf = ImageDraw.Draw(fold2)
    gf.polygon([pt(486, 300), pt(498, 300), pt(520, 646), pt(506, 646)], fill=(120, 108, 86, 80))
    gf.polygon([pt(540, 380), pt(550, 380), pt(578, 646), pt(564, 646)], fill=(120, 108, 86, 60))
    gf.polygon([pt(514, 320), pt(522, 320), pt(540, 646), pt(530, 646)], fill=(255, 252, 240, 60))
    body = Image.alpha_composite(body, fold2.filter(ImageFilter.GaussianBlur(sc(3))))
    d = ImageDraw.Draw(body)
    line(d, [(452, 232), (446, 330), (458, 430), (450, 540), (454, 648)], GOLD, 5)
    line(d, [(302, 646), (598, 646)], GOLD, 6)
    line(d, [(306, 636), (594, 636)], GOLD_L, 2)
    ell(d, (424, 306, 488, 370), fill=WHITE2, outline=GOLD, width=3)
    d.pieslice([sc(424), sc(306), sc(488), sc(370)], 90, 270, fill=INK)
    ell(d, (438, 306, 466, 334), fill=INK)
    ell(d, (446, 342, 474, 370), fill=WHITE2)
    ell(d, (450, 316, 456, 322), fill=WHITE2)
    ell(d, (454, 350, 460, 356), fill=INK)
    # 交领阴影：领口往下两道淡影（只压内侧，外侧留亮边）
    line(d, [(432, 248), (422, 330), (410, 400)], (0, 0, 0, 55), 5)
    line(d, [(472, 248), (484, 330), (498, 400)], (120, 108, 86, 70), 4)
    # 下摆：双金线（内粗外细）+ 云头小弧，收敛成一条边而不是一排锯齿
    for xa in (322, 462):
        xb = xa + (256 if xa < 450 else 156)
        for k in range(4):
            cx0 = xa + (xb - xa) * (k + 0.5) / 4.0
            line(d, [(cx0 - 16, 618), (cx0 - 6, 610), (cx0 + 6, 618), (cx0 + 16, 612)],
                 (176, 140, 66, 110), 2)
    poly(d, [(438, 196), (472, 196), (478, 236), (432, 236)], fill=SKIN)
    line(d, [(432, 232), (478, 232)], GOLD, 4)
    poly(d, [(406, 220), (438, 196), (448, 232), (414, 252)], fill=INK)
    poly(d, [(494, 220), (466, 196), (456, 232), (488, 252)], fill=WHITE)
    line(d, [(406, 220), (438, 196), (448, 232)], GOLD, 3)
    line(d, [(494, 220), (466, 196), (456, 232)], GOLD, 3)
    ell(d, (408, 100, 492, 206), fill=SKIN)
    poly(d, [(402, 148), (406, 104), (430, 86), (450, 92), (470, 86), (494, 104),
             (498, 148), (486, 210), (470, 196), (450, 200), (430, 196), (414, 210)],
         fill=INK)
    poly(d, [(452, 92), (470, 86), (494, 104), (498, 148), (486, 210), (470, 196),
             (452, 200)], fill=WHITE2)
    ell(d, (424, 64, 476, 106), fill=INK, outline=GOLD, width=3)
    ell(d, (440, 54, 460, 74), fill=GOLD)
    ell(d, (468, 140, 490, 150), fill=WHITE2)
    ell(d, (478, 141, 486, 149), fill=INK)
    line(d, [(468, 132), (492, 136)], INK, 3)
    line(d, [(492, 156), (500, 166), (492, 172)], SKIN_D, 3)
    line(d, [(470, 182), (490, 184)], (120, 70, 60, 180), 2)
    ell(d, (440, 150, 456, 172), fill=SKIN_D)
    line(d, [(426, 84), (500, 70)], GOLD, 4)
    ell(d, (496, 66, 508, 78), fill=GOLD_L)
    # 冠面金丝（三道细弧）+ 冠沿高光
    for k in range(3):
        line(d, [(432 + k * 12, 60), (446 + k * 12, 54), (460 + k * 12, 60)], GOLD_L, 2)
    line(d, [(424, 100), (476, 96)], (255, 246, 214, 160), 2)
    # 面具：阴侧的冷光眼缝（细，不抢轮廓）
    line(d, [(470, 146), (489, 142)], (170, 240, 246, 210), 2)
    # 颧骨下的阴影，把脸从平面拉出体积
    line(d, [(414, 176), (432, 188), (452, 190)], (120, 96, 78, 110), 3)
    ell(d, (398, 238, 486, 326), fill=INK, outline=GOLD, width=4)
    ell(d, (414, 254, 470, 310), fill=INK2)
    line(d, [(410, 264), (434, 252), (458, 264), (482, 252)], GOLD, 3)
    save(body, "body.png")


def make_arm():
    arm = canvas()
    d = ImageDraw.Draw(arm)
    ell(d, (398, 238, 486, 326), fill=INK, outline=GOLD, width=4)
    ell(d, (414, 254, 470, 310), fill=INK2)
    poly(d, [(414, 252), (470, 262), (604, 388), (626, 430), (590, 452),
             (536, 400), (444, 318)], fill=INK)
    poly(d, [(470, 262), (604, 388), (626, 430), (594, 446), (544, 398),
             (456, 306)], fill=WHITE)
    line(d, [(586, 444), (630, 438)], GOLD, 7)
    line(d, [(580, 430), (624, 426)], GOLD_L, 2)
    ell(d, (596, 408, 646, 456), fill=SKIN, outline=SKIN_D, width=2)
    for i in range(4):
        x = 620 + i * 7
        line(d, [(x, 428), (x + 6, 452)], SKIN_D, 2)
    line(d, [(606, 434), (638, 440)], GOLD, 3)
    line(d, [(636, 430), (724, 286)], GOLD, 7)
    line(d, [(640, 424), (728, 280)], GOLD_L, 2)
    ell(d, (708, 256, 748, 296), fill=GOLD, outline=GOLD_L, width=2)
    for i in range(11):
        a = math.radians(-62 + i * 11)
        r = 92 + (i % 3) * 8
        x2 = 728 + math.cos(a) * r
        y2 = 276 + math.sin(a) * r
        line(d, [(728, 276), (x2, y2)],
             (235, 236, 228, 210) if i % 2 == 0 else (176, 226, 230, 190), 3)
    for i in range(3):
        ell(d, (744 + i * 12, 300 + i * 6, 752 + i * 12, 308 + i * 6), fill=GOLD_L)
    save(arm, "arm.png")


def make_leg(name, cx, front):
    leg = canvas()
    d = ImageDraw.Draw(leg)
    ell(d, (cx - 26, 574, cx + 26, 626), fill=INK, outline=GOLD, width=3)
    if front:
        poly(d, [(466, 604), (504, 604), (510, 676), (534, 700), (462, 700),
                 (454, 654)], fill=INK)
        poly(d, [(466, 604), (486, 604), (492, 668), (512, 690), (462, 690),
                 (458, 654)], fill=INK2)
        line(d, [(462, 690), (512, 690)], GOLD, 3)
        line(d, [(470, 612), (500, 612)], GOLD_L, 2)
    else:
        poly(d, [(400, 604), (438, 604), (440, 676), (466, 700), (394, 700),
                 (386, 654)], fill=INK)
        poly(d, [(400, 604), (420, 604), (418, 668), (438, 690), (394, 690),
                 (388, 654)], fill=INK2)
        line(d, [(394, 690), (438, 690)], GOLD, 3)
        line(d, [(402, 612), (432, 612)], GOLD_L, 2)
    save(leg, name)


def make_sash():
    sash = canvas()
    d = ImageDraw.Draw(sash)
    ell(d, (428, 548, 472, 592), fill=GOLD, outline=GOLD_L, width=2)
    poly(d, [(432, 566), (380, 610), (300, 700), (338, 712), (410, 636),
             (458, 590)], fill=INK)
    poly(d, [(458, 574), (500, 620), (560, 700), (526, 714), (474, 640),
             (444, 596)], fill=WHITE)
    line(d, [(432, 566), (380, 610), (300, 700)], GOLD, 3)
    line(d, [(458, 574), (500, 620), (560, 700)], GOLD, 3)
    ell(d, (436, 584, 464, 612), fill=WHITE2, outline=GOLD, width=2)
    d.pieslice([sc(436), sc(584), sc(464), sc(612)], 90, 270, fill=INK)
    save(sash, "sash.png")


## 光环的中心（画布坐标）。外环与太极盘**共用**这一个中心。
HALO_CX, HALO_CY = 450, 268


def make_halo():
    """身后光环的**外圈**（会整圈自转的那一层）：金 / 青环 + 八卦 + 方位点。

    ⚠ 2026-10-28 拆件：原来外圈和太极盘画在同一张 halo.png 里，而 halo 节点是要
      **整圈自转**的 —— 太极盘跟着转，转到 45° 就不像太极图了（用户报「不像太极图」）。
      把整圈旋转关掉，用户又报「光环不会旋转了」。两全的做法就是拆成两层：
        · `halo.png`  ← 这里，外环 + 八卦，**转**（环状图案旋转是法阵感，不违和）
        · `taiji.png` ← `make_taiji()`，太极盘，**不转**（对称图形必须始终直立）
      两层在 rig.tres 里各自一件，halo 的 z 比 taiji 低一格。

    赛璐璐口径：实色、统一粗细，不用高斯柔光与低 alpha 叠层。
    """
    halo = canvas()
    d = ImageDraw.Draw(halo)
    ccx, ccy = HALO_CX, HALO_CY
    # 外三环：金 / 青 / 亮金，实色等粗
    ell(d, (ccx - 246, ccy - 246, ccx + 246, ccy + 246), outline=GOLD, width=6)
    ell(d, (ccx - 232, ccy - 232, ccx + 232, ccy + 232), outline=CYAN, width=3)
    ell(d, (ccx - 210, ccy - 210, ccx + 210, ccy + 210), outline=GOLD_L, width=2)
    # 八卦：交给公共模块，与特效贴图 liangyi_bagua 用同一套卦象画法
    ac.draw_bagua_ring(d, sc(ccx), sc(ccy), sc(214), GOLD_L, width=sc(3),
                       bar_len=sc(30), bar_gap=sc(10))
    # 方位点：实心小圆，金 / 青交替
    for k in range(18):
        a = math.radians(k * 20 + 8)
        rad = 250 + (k % 3) * 12
        x = ccx + math.cos(a) * rad
        y = ccy + math.sin(a) * rad
        ell(d, (x - 3, y - 3, x + 3, y + 3),
            fill=GOLD if k % 2 == 0 else CYAN)
    save(halo, "halo.png")


def make_taiji():
    """身后光环的**内盘**：标准太极图，**不参与旋转**。

    太极的 S 曲线靠两个半圆拼出来：**圆心在 ±r/2、半径 r/2**
    （写成 ±r 会变成一黑一白两个圆盘 —— 2026-10-28 踩过）。
    鱼眼半径 r/6，黑区点白、白区点黑。
    """
    tj = canvas()
    d = ImageDraw.Draw(tj)
    ccx, ccy = HALO_CX, HALO_CY
    r = 178
    half = r // 2
    eye = r // 6
    ell(d, (ccx - r, ccy - r, ccx + r, ccy + r), fill=WHITE, outline=GOLD, width=4)
    d.pieslice([sc(ccx - r), sc(ccy - r), sc(ccx + r), sc(ccy + r)], 90, 270, fill=INK)
    ell(d, (ccx - half, ccy - half - half, ccx + half, ccy - half + half), fill=INK)
    ell(d, (ccx - half, ccy + half - half, ccx + half, ccy + half + half), fill=WHITE)
    ell(d, (ccx - eye, ccy - half - eye, ccx + eye, ccy - half + eye), fill=WHITE2)
    ell(d, (ccx - eye, ccy + half - eye, ccx + eye, ccy + half + eye), fill=INK2)
    save(tj, "taiji.png")


def make_preview():
    preview = canvas()
    for name in ["halo", "sash", "leg_back", "body", "leg_front", "arm"]:
        part = Image.open(os.path.join(OUT, name + ".png")).resize((W * S, H * S))
        preview.alpha_composite(part)
    preview.resize((W, H), Image.LANCZOS).save(os.path.join(OUT, "preview.png"))
    print("preview saved")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    make_body()
    make_arm()
    make_leg("leg_back.png", 422, False)
    make_leg("leg_front.png", 478, True)
    make_sash()
    make_halo()
    make_taiji()
    make_preview()
