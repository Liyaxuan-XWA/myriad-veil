"""执烛卡面合成（2026-11-02）

用户这批外部生图里没有卡面原图（提示词 §5 那张低机位仰拍还没生成），
但入场卡 / 图鉴卡 / 华彩三层都已经在读 card_boss_zhizhu.png。
留一张和实机完全不同的扁平矢量小人，等于玩家在游戏里看到的和卡片上是两个角色。

所以这里先用**已交付的三张**（定妆剪影 / 站起来的墨影 / 战场地面）合成一张过渡卡面，
等真正的卡面原图到了直接覆盖同名文件即可。构图按提示词 §5 的口径来：
上方留给悬灯与光池，中间是执烛本体，下方 1/3 被那条捅向前景的长影占掉。
"""

import os
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance

ROOT = r"D:\GodotProjects\myriad-veil"
W, H = 640, 960


def load(p):
    return Image.open(os.path.join(ROOT, p)).convert("RGBA")


def content(im):
    bb = im.getbbox()
    return im.crop(bb) if bb else im


def radial(size, color, power=2.6):
    """一张柔边光斑（中心实心 → 边缘透明），用来铺光池与影尖。"""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = img.load()
    c = (size - 1) * 0.5
    for y in range(size):
        for x in range(size):
            d = ((x - c) ** 2 + (y - c) ** 2) ** 0.5 / c
            a = max(0.0, 1.0 - d) ** power
            px[x, y] = (color[0], color[1], color[2], int(255 * a))
    return img


def soft(dst, src, pos, strength):
    """按强度叠一张光斑。
    ⚠ 不能用 `alpha_composite(src, pos, mask)`：PIL 那个方法的第三参是**源矩形**，
      传蒙版会报「Source must be a list or tuple」。强度直接乘进自己的 alpha 再正常合成。
    """
    s = src.copy()
    s.putalpha(s.split()[3].point(lambda v: int(v * strength / 255.0)))
    dst.alpha_composite(s, pos)


def main():
    # ---------- 底：战场地面压暗 + 冷调分级 ----------
    ground = load("assets/scenes/zhaoying_lamp_arena_ground.png").convert("RGB")
    ground = ground.resize((int(W * 1.35), int(W * 1.35)), Image.LANCZOS)
    x0 = (ground.width - W) // 2
    bg = ground.crop((x0, 0, x0 + W, H))
    bg = ImageEnhance.Brightness(bg).enhance(0.40)
    bg = ImageEnhance.Contrast(bg).enhance(1.16)
    card = bg.convert("RGBA")

    # 上方 1/4 留给「光与暗」：悬灯打下来的光池
    pool = radial(520, (168, 200, 226), 2.2).resize((600, 460), Image.LANCZOS)
    soft(card, pool, (int(W / 2 - 300), -60), 108)

    # ---------- 下方：那条捅向前景的长影（先画，本体压在它上面）----------
    shade = content(load("assets/effects/skills/zhizhu_shadow.png"))
    shade = shade.resize((250, 400), Image.LANCZOS)
    dark = Image.new("RGBA", shade.size, (5, 7, 15, 255))
    dark.putalpha(shade.split()[3].point(lambda v: int(v * 0.86)))
    card.alpha_composite(dark, (int(W / 2 - 125), H - 372))
    # 影尖亮点：整张卡最亮的一点，位置 = 射程读数
    tip = radial(150, (196, 232, 255), 2.0)
    soft(card, tip, (int(W / 2 - 75), H - 96), 176)

    # ---------- 中段：执烛本体（定妆图抠出来的那一张）----------
    # 脚落在长影起点上，头留在上方 1/4 的暗里 —— 别把脑袋顶出画
    body = content(load("assets/characters/boss/boss_zhizhu.png"))
    s = 620.0 / body.height
    body = body.resize((int(body.width * s), int(body.height * s)), Image.LANCZOS)
    card.alpha_composite(body, (int(W / 2 - body.width / 2), 700 - body.height))

    # ---------- 上方：一盏悬灯的暖光（灯形由本体手里那盏提供，这里只给光）----------
    glow = radial(300, (236, 196, 120), 2.4).resize((300, 280), Image.LANCZOS)
    soft(card, glow, (int(W / 2 - 150), 8), 118)
    d = ImageDraw.Draw(card)
    d.line([(W / 2 + 4, 0), (W / 2 + 4, 74)], fill=(120, 132, 152, 120), width=3)

    # 四角压黑，把视线收到中轴
    vign = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dv = ImageDraw.Draw(vign)
    dv.rectangle((0, 0, W, H), fill=(2, 3, 8, 165))
    hole = radial(700, (255, 255, 255), 1.5)
    mask = Image.new("L", (W, H), 0)
    mask.paste(hole.split()[3].resize((W, int(H * 0.95)), Image.LANCZOS),
               (0, int(H * 0.02)))
    vign.putalpha(Image.eval(mask, lambda v: max(0, 165 - v)))
    card.alpha_composite(vign)

    # ---------- 收尾：整体冷调 + 轻微模糊，让合成痕迹收敛 ----------
    card = card.filter(ImageFilter.GaussianBlur(0.6))
    overlay = Image.new("RGBA", (W, H), (26, 40, 74, 44))
    card.alpha_composite(overlay)
    card = ImageEnhance.Contrast(card).enhance(1.06)

    out = card.convert("RGB")
    for rel in ("assets/ui/codex/card_boss_zhizhu.png",
                "assets/ui/codex/holo/boss_04_b_art.png"):
        out.save(os.path.join(ROOT, rel))
        print("wrote", rel, out.size)


main()
