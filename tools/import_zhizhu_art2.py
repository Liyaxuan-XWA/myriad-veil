"""执烛第二轮外部生图导入（2026-11-02 · 10 张）

按 `docs/执烛待生成美术_提示词.md` 的优先级交付：卡面 / 水墨卡 / 墨迹长条 / 墨团 /
影尖火苗 / 立地界灯 / 定妆v2 / 身体v2 / 灯笼v2 / 执烛令v2。

键色与去水印函数**直接复用第一轮**（`import_zhizhu_art`），避免两套抠图口径漂移；
线稿层与水墨收片也复用既有华彩 / 卡包管线，不自己另发明一套。

⚠ 角色两件姿势不一致是这批最大的问题：定妆图 v2 是**抬手挑灯**，身体件 v2 是**双手垂立**。
  rig 只需要 body + lantern 两件，所以按身体件实测的垂手位置挂灯，
  并把 `boss_zhizhu.png` 立绘改成「body + lantern 合成」—— 保证立绘与 rig 一模一样，
  不会出现「图鉴里抬手、战场上垂手」。定妆图 v2 只当参考，不进包。
"""

import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import import_zhizhu_art as A          # noqa: E402  第一轮：键色 / 去水印 / 裁切 / 图标
from build_boss_ink_cards import grade as ink_grade      # noqa: E402  纸白点校正
from build_plain_holo_cards import make_lines            # noqa: E402  虎妖标准线稿

ROOT = A.ROOT
VIBE = A.VIBE
V2 = "v2"


def src(key):
    p = os.path.join(VIBE, "%s_%s.png" % (key, V2))
    if not os.path.exists(p):
        raise FileNotFoundError(p)
    return Image.open(p).convert("RGB")


def scrub_corner(im, box=(0.66, 0.86, 1.0, 1.0), radius=8):
    """水印框内做高斯模糊：水印是高频笔画、底纹是低频色块，一把模糊就把字抹掉而看不出动过。

    前面试过三种补块口径，都不干净或留接缝：
      · 固定阈值 `lum > 105` —— 暗底卡面底色中位数只有 11，只擦得掉最亮几个点；
      · 按框内中位数 ±dev 换镜像 —— 水印是「亮笔画 + 更暗描边」两层，只掉一层更像字，
        而且纸面/水纹的镜像源和原处纹理对不上，会露出一块矩形接缝；
      · 整块 FLIP —— 镜像的是框自己，等于把水印搬到框左边。
    """
    w, h = im.size
    x0, y0 = int(w * box[0]), int(h * box[1])
    patch = im.crop((x0, y0, w, h)).filter(ImageFilter.GaussianBlur(radius))
    out = im.copy()
    out.paste(patch, (x0, y0))
    return out


def wm(im, box=(0.70, 0.88, 1.0, 1.0)):
    return scrub_corner(im, box)


def scrub_corner_rgba(im, box=(0.62, 0.84, 1.0, 1.0), radius=7):
    """键色**之后**再擦：只模糊 RGB、alpha 原样保留。
    先模糊会把洋红底糊进素材边缘，键完就留下一圈去色解不开的绿边（执烛令踩过）。
    """
    w, h = im.size
    x0, y0 = int(w * box[0]), int(h * box[1])
    r, g, b, a = im.split()
    rgb = Image.merge("RGB", (r, g, b)).crop((x0, y0, w, h)).filter(ImageFilter.GaussianBlur(radius))
    out = im.copy()
    out.paste(rgb, (x0, y0))
    out.putalpha(a)
    return out


def to_card(im, size=(640, 960)):
    """收片：先放大到目标尺寸**再**擦水印，最后才轻锐化。

    ⚠ 顺序不能反：源图只有 256×384，水印在那上面只有 ~30×8 px，
      补完再放大 + UnsharpMask 会把残留的笔画边缘重新勾出来（实测留一层麻点状残影）。
      放到 640×960 上擦才有足够像素，锐化也就不会二次放大它。
    """
    out = im.convert("RGB").resize(size, Image.LANCZOS)
    out = scrub_corner(out)
    out = out.filter(ImageFilter.UnsharpMask(radius=1.4, percent=58, threshold=3))
    return ImageEnhance.Contrast(out).enhance(1.04)


# ============ 亮度 ↔ alpha ============

def white_to_alpha(im):
    """白底黑墨 → 透明底黑墨。

    ⚠ 第一版写成 `alpha = 亮度`，等于把**纸**留下、把**墨**抠掉 ——
      整张图四个角全是实心灰块，接进走廊后地上糊了一大片。
      要的是反亮度：纸白=透明，浓墨=不透明。
    """
    lum = np.asarray(im.convert("L"), np.float32) / 255.0
    alpha = np.clip((1.0 - lum - 0.04) / 0.86, 0.0, 1.0)
    out = Image.new("RGBA", im.size, (8, 8, 12, 0))
    out.putalpha(Image.fromarray((alpha * 255.0).astype(np.uint8), "L"))
    return out


def black_to_lum(im):
    """黑底亮焰 → 透明底亮焰（亮度当 alpha，颜色原样保留，加色混合用）。"""
    arr = np.asarray(im.convert("RGB"), np.float32)
    a = np.clip(arr.max(axis=2) * 1.06, 0.0, 255.0).astype(np.uint8)
    out = im.convert("RGBA").copy()
    out.putalpha(Image.fromarray(a, "L"))
    return out


# ============ 角色件 ============

def hang_point(canvas):
    """在成品 rig 画布上找**垂手**的握点：中段高度、偏左的那一簇冷白像素。

    ⚠ 第一轮这里踩过的坑不能重犯：按「最上+最右」打分会选中脸。
      手在内容 42%~70% 高度这一带，脸在 35% 以上，用高度带先把脸排除掉。
    """
    px = canvas.load()
    w, h = canvas.size
    y0, y1 = int(h * 0.42), int(h * 0.72)
    pts = []
    for y in range(y0, y1):
        for x in range(0, w // 2):
            r, g, b, a = px[x, y]
            if a < 128:
                continue
            if r > 145 and g > 125 and b > 150 and b >= g and (max(r, g, b) - min(r, g, b)) < 95:
                pts.append((x, y))
    if len(pts) < 12:
        return None
    left = sorted(pts, key=lambda p: p[0])[:60]
    cx = sum(p[0] for p in left) / len(left)
    cy = sum(p[1] for p in left) / len(left)
    return (int(round(cx - w * 0.5)), int(round(cy - h * 0.5)))


def build_rig_pieces(body_dir):
    body_raw = src("zhizhu_body")
    body_keyed = A.key_magenta(A.crop_content(body_raw))
    body_fit = A.fit_into(body_keyed, 900, 720, 8)
    canvas = Image.new("RGBA", (900, 720), (0, 0, 0, 0))
    A.paste_bottom_center(canvas, body_fit, 0.5)
    canvas.save(os.path.join(body_dir, "body.png"))
    joint = hang_point(canvas)

    lamp_keyed = A.key_magenta(A.crop_content(src("zhizhu_lantern")))
    # 灯 ≈ 身高 1/3（body 内容 704 → 236）；画布只留 4px 边，
    # 否则上半的透明留白会被 head_top_y() 当成身体（第一轮踩过）
    lamp_fit = A.fit_into(lamp_keyed, 300, 236, 2)
    pad = 4
    cw, ch = lamp_fit.width + pad * 2, lamp_fit.height + pad * 2
    hook_y = pad + lamp_fit.height * 0.042
    lc = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    lc.alpha_composite(lamp_fit, (pad, pad))
    lc.save(os.path.join(body_dir, "lantern.png"))
    offset_y = ch / 2.0 - hook_y

    # 立绘 = body + lantern 合成，和 rig 完全一致：
    # 灯笼画布上的提钩在 (cw/2, hook_y)，要落在握点的画布坐标上
    full = canvas.copy()
    full.alpha_composite(lc, (int(450 + joint[0] - cw / 2), int(360 + joint[1] - hook_y)))
    return joint, (cw, ch), round(offset_y, 1), full


# ============ 主流程 ============

def main():
    boss_dir = os.path.join(ROOT, "assets", "characters", "boss")
    rig_dir = os.path.join(boss_dir, "zhizhu_rig")
    fx_dir = os.path.join(ROOT, "assets", "effects", "skills")
    holo = os.path.join(ROOT, "assets", "ui", "codex", "holo")
    icon_dir = os.path.join(ROOT, "assets", "ui", "icon")

    # ---------- P0-1 卡面 ----------
    card = to_card(src("zhizhu_card")).convert("RGBA")
    card.convert("RGB").save(os.path.join(ROOT, "assets/ui/codex/card_boss_zhizhu.png"))
    card.convert("RGB").save(os.path.join(holo, "boss_04_b_art.png"))
    # 华彩视差背景层：同场景重绘的无人物原片这次没给，先从卡面派生
    # （渲染端 bg_scale=0.5 + 视差位移，本来就是当远景用的）
    bg = card.convert("RGB").filter(ImageFilter.GaussianBlur(7))
    bg = ImageEnhance.Brightness(bg).enhance(0.62)
    bg = ImageEnhance.Color(bg).enhance(0.82)
    bg.save(os.path.join(holo, "boss_04_b_bg.png"))
    lines = make_lines(card, 21.0)
    lines.save(os.path.join(holo, "boss_04_b_lines.png"))
    print("card 640x960 + bg(blur7/0.62) + lines(mean~21)")

    # ---------- P0-2 水墨卡 ----------
    ink = to_card(src("zhizhu_ink"))
    ink = ink_grade(ink)
    ink = ImageEnhance.Sharpness(ink).enhance(1.10)
    ink.save(os.path.join(holo, "boss_04_b_ink.png"))
    print("ink card", ink.size, "→ 再跑 bake_boss_ink_maps.py boss_04_b")

    # ---------- P0-3 / P0-4 墨迹 ----------
    stroke = white_to_alpha(scrub_corner(src("zhizhu_stroke"), (0.72, 0.72, 1.0, 1.0), 7)).resize((768, 192), Image.LANCZOS)
    stroke.save(os.path.join(fx_dir, "ink_stroke_long.png"))
    blob = white_to_alpha(scrub_corner(src("zhizhu_blob"))).resize((512, 512), Image.LANCZOS)
    blob.save(os.path.join(fx_dir, "ink_blob.png"))
    print("ink stroke 768x192 · ink blob 512sq")

    # ---------- P1-5 影尖火苗 ----------
    # 黑底上亮度就是 alpha，水印那几笔会被当成火苗的一部分 —— 先按中位数自适应擦掉
    flame = black_to_lum(wm(src("zhizhu_flame"), (0.72, 0.90, 1.0, 1.0)))
    flame = flame.resize((256, 256), Image.LANCZOS)
    flame.save(os.path.join(fx_dir, "lamp_flame_tip.png"))
    print("flame tip 256sq")

    # ---------- P1-6 立地界灯 ----------
    post = A.key_magenta(A.crop_content(src("zhizhu_lamppost")))
    post = A.fit_into(post, 384, 768, 4)
    pc = Image.new("RGBA", (448, 832), (0, 0, 0, 0))
    pc.alpha_composite(post, ((448 - post.width) // 2, 832 - post.height - 4))
    pc.save(os.path.join(fx_dir, "lamp_post.png"))
    print("lamp post", post.size, "→ 448x832 画布，石座贴底")

    # ---------- P2-7 角色件 ----------
    joint, lamp_canvas, offset_y, full = build_rig_pieces(rig_dir)
    full.save(os.path.join(boss_dir, "boss_zhizhu.png"))
    print("rig body+lantern · 握点(局部)", joint, "· 灯笼画布", lamp_canvas,
          "· part_offset.y", offset_y)

    # ---------- P2-8 执烛令图标 ----------
    ling = scrub_corner_rgba(A.key_magenta(A.crop_content(src("zhizhu_ling_icon"))))
    A.square_icon(ling, 256, 8).save(os.path.join(icon_dir, "tr_zhizhu_ling.png"))
    print("icon tr_zhizhu_ling")
    print("done")


if __name__ == "__main__":
    main()
