"""执烛（照影界第 2 位）外部生图导入 —— 2026-11-02

把用户外部生成的 8 张图（洋红底）导入成工程素材：
  去水印 → 洋红键色抠图 → 裁切 → 按 rig / 图标 / 战场要求的画布规格重排。
源图放在 vibe_images/（zhizhu_*_v1.png），产物覆盖同名 PIL 替代件。
规格与 tools/gen_guanying_assets.py 同一套（key_magenta / trim / fit_into / square_icon）。
"""

import os
from PIL import Image, ImageDraw, ImageFilter

ROOT = r"D:\GodotProjects\myriad-veil"
VIBE = os.path.join(ROOT, "vibe_images")


def src(name):
    p = os.path.join(VIBE, name + ".png")
    if not os.path.exists(p):
        raise FileNotFoundError(p)
    return Image.open(p).convert("RGB")


def is_magenta(r, g, b):
    return ((r + b) * 0.5 - g) > 30.0


def key_magenta(im):
    """洋红键色抠图，并且**反解**半透明边的颜色。

    只把洋红当 alpha 用会留下粉紫色描边：边缘像素其实是
    `观测 = 真色 × (1-k) + 键色 × k`，所以扣完还要按 k 把键色减回去再除以 (1-k)。
    第一版没做这步，卡面合成时罗裙边缘一圈品红毛边全暴露了（2026-11-02）。
    """
    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size
    kr, kg, kb = 0xE6, 0x00, 0x7E
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            k = max(0.0, min(1.0, (((r + b) * 0.5 - g) - 30.0) / 70.0))
            if k <= 0.0:
                continue
            if k >= 0.98:
                px[x, y] = (0, 0, 0, 0)
                continue
            inv = 1.0 / (1.0 - k)
            rr = int(max(0.0, min(255.0, (r - kr * k) * inv)))
            gg = int(max(0.0, min(255.0, (g - kg * k) * inv)))
            bb = int(max(0.0, min(255.0, (b - kb * k) * inv)))
            px[x, y] = (rr, gg, bb, int(a * (1.0 - k)))
    return im


def scrub_watermark(im, box=(0.76, 0.88, 1.0, 1.0)):
    """右下角「豆包 AI 生成」：把浅色文字像素换成同一行水平镜像处的像素。
    地面 / 灯印 / 立绘都近似左右对称，镜像补块看不出来；深色像素一律不动。"""
    px = im.load()
    w, h = im.size
    x0, y0 = int(w * box[0]), int(h * box[1])
    for y in range(y0, h):
        for x in range(x0, w):
            r, g, b = px[x, y][:3]
            if is_magenta(r, g, b):
                continue
            mx = w - 1 - x
            lum = (r + g + b) / 3.0
            sat = max(r, g, b) - min(r, g, b)
            # 文字是浅灰白：亮度高、饱和低；铜灯/冷银高光饱和也低但亮度更高，阈值分开
            if lum > 105.0 and sat < 58.0:
                px[x, y] = px[mx, y][:3]
    return im


def content_bbox(im, step=1):
    """按非洋红内容算包围盒（RGB 输入）。"""
    px = im.load()
    w, h = im.size
    x0, y0, x1, y1 = w, h, 0, 0
    for y in range(0, h, step):
        for x in range(0, w, step):
            r, g, b = px[x, y][:3]
            if not is_magenta(r, g, b):
                x0 = min(x0, x); x1 = max(x1, x)
                y0 = min(y0, y); y1 = max(y1, y)
    return (x0, y0, x1 + 1, y1 + 1)


def crop_content(im, pad=4):
    bb = content_bbox(im, 1)
    w, h = im.size
    x0 = max(0, bb[0] - pad); y0 = max(0, bb[1] - pad)
    x1 = min(w, bb[2] + pad); y1 = min(h, bb[3] + pad)
    return im.crop((x0, y0, x1, y1))


def fit_into(im, box_w, box_h, margin=0):
    w, h = im.size
    s = min((box_w - margin * 2) / w, (box_h - margin * 2) / h)
    return im.resize((max(1, int(w * s)), max(1, int(h * s))), Image.LANCZOS)


def square_icon(im, size=256, margin=12):
    im = im.copy()
    bb = im.getbbox()
    if bb:
        im = im.crop(bb)
    im = fit_into(im, size, size, margin)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.alpha_composite(im, ((size - im.width) // 2, (size - im.height) // 2))
    return out


def paste_bottom_center(canvas, sprite, cx_frac=0.5, foot_pad=2):
    x = int(canvas.width * cx_frac - sprite.width / 2)
    y = canvas.height - sprite.height - foot_pad
    canvas.alpha_composite(sprite, (max(0, x), max(0, y)))
    return (x, y)


def hand_joint(canvas, cx=None, cy=None):
    """在**最终 rig 画布**上量抬手的手，返回 rig 局部坐标（画布中心 = 原点）。

    在成品画布上量而不是在源图上量再换算：少一层缩放/裁切链就没有一处会算错的机会。
    ⚠ 第一版按「最靠上 + 最靠右」打分，选中了脸（脸的 y 更小，权重压过 x），
      灯笼挂点因此掉到胸腹之间。改成只在上半幅的右半区取最右的一簇皮肤 ——
      脸在水平中心，天然被排除。
    """
    px = canvas.load()
    w, h = canvas.size
    cx = w * 0.5 if cx is None else cx
    cy = h * 0.5 if cy is None else cy
    pts = []
    for y in range(0, int(cy)):
        for x in range(int(cx * 1.16), w):
            r, g, b, a = px[x, y]
            if a < 128 or is_magenta(r, g, b):
                continue
            if r > 150 and g > 120 and b > 110 and (max(r, g, b) - min(r, g, b)) < 90:
                pts.append((x, y))
    if not pts:
        return None
    xs = sorted(pts, key=lambda p: -p[0])[:80]
    hx = sum(p[0] for p in xs) / len(xs)
    hy = sum(p[1] for p in xs) / len(xs)
    return (int(round(hx - cx)), int(round(hy - cy)))


def sink_bottom(path, frac=0.30):
    """把图标最底部那条水印糊痕沉进本格自己的底色里。

    第 16 格（执烛令）右下角的「豆包 AI 生成」即使横向镜像补过仍留一条糊带；
    令牌是居中圆牌，下缘本来就融进暗底，沉下去看不出来。
    """
    im = Image.open(path).convert("RGBA")
    px = im.load()
    w, h = im.size
    sx0, sy0 = int(w * 0.03), int(h * 0.90)
    rs = gs = bs = n = 0
    for y in range(sy0, min(h, sy0 + 12)):
        for x in range(sx0, min(w, sx0 + 12)):
            r, g, b, _a = px[x, y]
            rs += r
            gs += g
            bs += b
            n += 1
    bg = (rs // max(n, 1), gs // max(n, 1), bs // max(n, 1))
    y0 = int(h * (1.0 - frac))
    for y in range(y0, h):
        k = ((y - y0) / float(h - y0)) ** 1.5
        for x in range(w):
            r, g, b, a = px[x, y]
            px[x, y] = (int(r + (bg[0] - r) * k), int(g + (bg[1] - g) * k),
                        int(b + (bg[2] - b) * k), a)
    im.save(path)
    return bg


def main():
    boss_dir = os.path.join(ROOT, "assets", "characters", "boss")
    rig_dir = os.path.join(boss_dir, "zhizhu_rig")
    fx_dir = os.path.join(ROOT, "assets", "effects", "skills")
    wpn_dir = os.path.join(ROOT, "assets", "effects", "weapons")
    scenes_dir = os.path.join(ROOT, "assets", "scenes")
    icon_dir = os.path.join(ROOT, "assets", "ui", "icon")
    for d in (boss_dir, rig_dir, fx_dir, wpn_dir, scenes_dir, icon_dir):
        os.makedirs(d, exist_ok=True)

    # ---------- 1. 定妆全身（含灯）→ boss_zhizhu.png 900×720 ----------
    concept = scrub_watermark(src("zhizhu_concept_v1"))
    fig = key_magenta(crop_content(concept))
    full = fit_into(fig, 900, 720, 8)
    canvas = Image.new("RGBA", (900, 720), (0, 0, 0, 0))
    paste_bottom_center(canvas, full, 0.5)
    canvas.save(os.path.join(boss_dir, "boss_zhizhu.png"))
    print("boss_zhizhu.png", full.size)

    # ---------- 2. 身体件（无灯）→ rig/body.png，并量抬手位置 ----------
    body_raw = scrub_watermark(src("zhizhu_body_v1"))
    body_keyed = key_magenta(crop_content(body_raw))
    body_fit = fit_into(body_keyed, 900, 720, 8)
    canvas = Image.new("RGBA", (900, 720), (0, 0, 0, 0))
    px, py = paste_bottom_center(canvas, body_fit, 0.5)
    canvas.save(os.path.join(rig_dir, "body.png"))
    joint = hand_joint(canvas)
    print("body.png", body_fit.size, "paste", (px, py), "lantern joint(局部)", joint)

    # ---------- 3. 灯笼件 → rig/lantern.png ----------
    # 目标高度 = 定妆图实测比例：灯笼 ≈ 身高的 1/3（body 内容 704px → 灯 236px）。
    # 源图只有 384px，按 rig 画布放大反而糊，所以这里是**缩小**。
    # ⚠ 画布只留 4px 边，不再用 520² 大方图：提钩到画布中心的距离会被
    #   `BossBase.head_top_y()` 当成「本体最高点」，画布上半的空白直接把血条
    #   顶到头顶上方 40px（2026-11-02 实机截图抓到）。
    #   提钩改由 rig.tres 的 part_offset 对回原点，所以这里把该偏移量一起打出来。
    lamp_raw = scrub_watermark(src("zhizhu_lantern_v1"))
    lamp_keyed = key_magenta(crop_content(lamp_raw))
    lamp_fit = fit_into(lamp_keyed, 300, 236, 2)
    pad = 4
    cw, ch = lamp_fit.width + pad * 2, lamp_fit.height + pad * 2
    hook_y = pad + lamp_fit.height * 0.045      # 提钩 = 内容顶往下 4.5%
    lc = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    lc.alpha_composite(lamp_fit, (pad, pad))
    lc.save(os.path.join(rig_dir, "lantern.png"))
    print("lantern.png", lc.size, "hook_y %.1f" % hook_y,
          "part_offset.y %.1f" % (ch / 2.0 - hook_y))

    # ---------- 4. 披影 / 地面投影剪影 → fx/zhizhu_shadow.png ----------
    hem = key_magenta(crop_content(scrub_watermark(src("zhizhu_hemshadow_v1"))))
    hem_fit = fit_into(hem, 512, 512, 6)
    hc = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    hc.alpha_composite(hem_fit, ((512 - hem_fit.width) // 2, (512 - hem_fit.height) // 2))
    hc.save(os.path.join(fx_dir, "zhizhu_shadow.png"))
    print("zhizhu_shadow.png", hem_fit.size)

    # ---------- 5. 地面纹理 → scenes/…1024²（RGB，可平铺）----------
    ground = scrub_watermark(src("zhizhu_ground_v1"), (0.70, 0.86, 1.0, 1.0))
    ground = ground.resize((1024, 1024), Image.LANCZOS).filter(ImageFilter.SMOOTH)
    ground.convert("RGB").save(os.path.join(scenes_dir, "zhaoying_lamp_arena_ground.png"))
    print("ground 1024 sq")

    # ---------- 6. 灯印 decal → fx/lamp_seal.png ----------
    seal = key_magenta(crop_content(scrub_watermark(src("zhizhu_seal_v1"), (0.70, 0.86, 1.0, 1.0))))
    seal = fit_into(seal, 512, 512, 4)
    sc = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    sc.alpha_composite(seal, ((512 - seal.width) // 2, (512 - seal.height) // 2))
    sc.save(os.path.join(fx_dir, "lamp_seal.png"))
    print("lamp_seal.png", seal.size)

    # ---------- 7. 局内武器 → weapons/changye_ren.png ----------
    wp = key_magenta(crop_content(scrub_watermark(src("zhizhu_weapon_v1"))))
    wp = fit_into(wp, 470, 470, 6)
    wc = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    wc.alpha_composite(wp, ((512 - wp.width) // 2, (512 - wp.height) // 2))
    wc.save(os.path.join(wpn_dir, "changye_ren.png"))
    print("weapon", wp.size)

    # ---------- 8. 图标 4×4 表 → 14 张 256² ----------
    sheet = src("zhizhu_icon_sheet_v1")
    cw, ch = sheet.width // 4, sheet.height // 4
    # 第 16 格（右下）被水印压住：先整体去水印，再把该格右半换成镜像补块
    sheet = scrub_watermark(sheet, (0.70, 0.86, 1.0, 1.0))
    cell16 = sheet.crop((3 * cw, 3 * ch, 4 * cw, 4 * ch))
    mirrored = cell16.transpose(Image.FLIP_LEFT_RIGHT)
    patch = Image.new("RGB", cell16.size)
    patch.paste(cell16, (0, 0))
    patch.paste(mirrored.crop((cell16.width // 2, 0, cell16.width, cell16.height)),
                (cell16.width // 2, 0))
    sheet.paste(patch, (3 * cw, 3 * ch))
    names = [
        "skill_shadow_cut", "skill_shadow_reach", "skill_shadow_bind", "skill_shadow_step",
        "skill_shadow_dim", "skill_shadow_beam", "skill_shadow_split", "skill_shadow_longnight",
        "skill_shadow_lamp", "equip_changye_ren", "equip_zhului_zhui", "mat_zhaoying_zhulei",
        "soul_zhizhu", None, None, "tr_zhizhu_ling",
    ]
    for i, name in enumerate(names):
        if name is None:
            continue
        r, c = i // 4, i % 4
        cell = sheet.crop((c * cw + 6, r * ch + 6, (c + 1) * cw - 6, (r + 1) * ch - 6))
        cell = key_magenta(cell)
        square_icon(cell, 256, 8).save(os.path.join(icon_dir, name + ".png"))
        print("icon", name)
    # 令牌那张的右下角压着水印，补块后仍有一条糊带 —— 沉进底色
    sink_bottom(os.path.join(icon_dir, "tr_zhizhu_ling.png"))
    print("done")


if __name__ == "__main__":
    main()
