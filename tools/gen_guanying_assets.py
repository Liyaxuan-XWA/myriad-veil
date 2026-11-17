from PIL import Image, ImageEnhance
import os

ROOT = r"D:\GodotProjects\myriad-veil"
VIBE = os.path.join(ROOT, "vibe_images")

def path(name):
    for f in os.listdir(VIBE):
        if f.startswith(name) and f.lower().endswith(".png"):
            return os.path.join(VIBE, f)
    raise FileNotFoundError(name)

def key_magenta(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            diff = (r + b) * 0.5 - g
            k = max(0.0, min(1.0, (diff - 30.0) / 70.0))
            if k > 0.0:
                px[x, y] = (r, g, b, int(a * (1.0 - k)))
    return im

def trim(im: Image.Image, pad=6) -> Image.Image:
    bb = im.getbbox()
    if bb is None:
        return im
    x0, y0, x1, y1 = bb
    x0 = max(0, x0 - pad); y0 = max(0, y0 - pad)
    x1 = min(im.width, x1 + pad); y1 = min(im.height, y1 + pad)
    return im.crop((x0, y0, x1, y1))

def fit_into(im: Image.Image, box_w, box_h, margin=0) -> Image.Image:
    w, h = im.size
    scale = min((box_w - margin * 2) / w, (box_h - margin * 2) / h)
    nw, nh = max(1, int(w * scale)), max(1, int(h * scale))
    return im.resize((nw, nh), Image.LANCZOS)

def square_icon(im: Image.Image, size=256, margin=10) -> Image.Image:
    im = trim(im)
    im = fit_into(im, size, size, margin)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.alpha_composite(im, ((size - im.width) // 2, (size - im.height) // 2))
    return out

def remove_watermark(im: Image.Image, fill=None) -> Image.Image:
    im = im.convert("RGBA")
    w, h = im.size
    x0, y0 = int(w * 0.80), int(h * 0.955)
    if fill is None:
        fill = (0, 0, 0, 0)
    for y in range(y0, h):
        for x in range(x0, w):
            im.putpixel((x, y), fill)
    return im

# ---------- 卡面 640x960 ----------
card = Image.open(path("guanying_card_art_v2")).convert("RGBA")
# 先裁掉底部水印，再保持 2:3
card = card.crop((0, 0, card.width, card.height - 58))
# 源图 1024x1478 ≈ 0.693，裁到 2:3
tw = int(card.height * 2 / 3)
if tw < card.width:
    x0 = (card.width - tw) // 2
    card = card.crop((x0, 0, x0 + tw, card.height))
card = card.resize((640, 960), Image.LANCZOS)
os.makedirs(os.path.join(ROOT, "assets/ui/codex"), exist_ok=True)
card.save(os.path.join(ROOT, "assets/ui/codex/card_boss_guanying.png"))
print("card", card.size)

# ---------- BOSS 全身（含镜）900x720 ----------
concept = Image.open(path("guanying_concept_cel_v2")).convert("RGBA")
concept = remove_watermark(concept, (230, 0, 126, 255))
concept = key_magenta(concept)
concept = trim(concept, 4)
full = fit_into(concept, 900, 720, 8)
boss_canvas = Image.new("RGBA", (900, 720), (0, 0, 0, 0))
boss_canvas.alpha_composite(full, ((900 - full.width) // 2, 720 - full.height - 2))
os.makedirs(os.path.join(ROOT, "assets/characters/boss"), exist_ok=True)
boss_canvas.save(os.path.join(ROOT, "assets/characters/boss/boss_guanying.png"))
print("boss full", boss_canvas.size, "content", full.size)

# ---------- 无镜身体 900x720 ----------
body = Image.open(path("guanying_body_nomirror")).convert("RGBA")
body = remove_watermark(body, (230, 0, 126, 255))
body = key_magenta(body)
body = trim(body, 4)
body_fit = fit_into(body, 900, 720, 8)
rig_dir = os.path.join(ROOT, "assets/characters/boss/guanying_rig")
os.makedirs(rig_dir, exist_ok=True)
body_canvas = Image.new("RGBA", (900, 720), (0, 0, 0, 0))
body_canvas.alpha_composite(body_fit, ((900 - body_fit.width) // 2, 720 - body_fit.height - 2))
body_canvas.save(os.path.join(rig_dir, "body.png"))
print("body", body_fit.size, "paste", ((900 - body_fit.width) // 2, 720 - body_fit.height - 2))

# ---------- 镜器部件（以握把为旋转中心）520x520 ----------
mirror = Image.open(path("guanying_mirror_prop")).convert("RGBA")
mirror = remove_watermark(mirror, (230, 0, 126, 255))
mirror = key_magenta(mirror)
mirror = trim(mirror, 4)
# 握把大约在裁切图的 55% 宽、60% 高处
mw, mh = mirror.size
pivot = (int(mw * 0.55), int(mh * 0.60))
# 缩放到画布内，握把放在画布中心
scale = min(420.0 / mw, 420.0 / mh)
nw, nh = int(mw * scale), int(mh * scale)
mirror = mirror.resize((nw, nh), Image.LANCZOS)
pivot = (int(pivot[0] * scale), int(pivot[1] * scale))
mcanvas = Image.new("RGBA", (520, 520), (0, 0, 0, 0))
mcanvas.alpha_composite(mirror, (260 - pivot[0], 260 - pivot[1]))
mcanvas.save(os.path.join(rig_dir, "mirror.png"))
print("mirror", mirror.size, "pivot", pivot)

# ---------- 场景地面 ----------
ground = Image.open(path("zhaoying_arena_ground")).convert("RGB")
gw, gh = ground.size
ground = ground.crop((0, 0, gw - 110, gh - 58)).resize((1024, 1024), Image.LANCZOS)
# 浅水覆石调色：提亮冷调 + 水纹焦散（与 2026-11-01 落地版一致）
from PIL import ImageDraw, ImageFilter
import math, random
gp = ground.load()
for y in range(1024):
    for x in range(1024):
        r, g, b = gp[x, y]
        gp[x, y] = (min(255, int(r * 1.04 + 7)), min(255, int(g * 1.08 + 10)),
            min(255, int(b * 1.14 + 14)))
ground = ImageEnhance.Contrast(ground).enhance(0.96)
ov = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
d = ImageDraw.Draw(ov)
random.seed(23)
for i in range(26):
    base_y = random.randint(0, 1024)
    amp = random.randint(8, 34)
    freq = random.uniform(0.006, 0.018)
    phase = random.uniform(0, math.tau)
    alpha = random.randint(14, 38)
    pts = [(x, base_y + math.sin(x * freq + phase) * amp) for x in range(-10, 1035, 8)]
    d.line(pts, fill=(160, 215, 255, alpha), width=random.choice([1, 1, 2]))
ov = ov.filter(ImageFilter.GaussianBlur(2.0))
ground = Image.alpha_composite(ground.convert("RGBA"), ov).convert("RGB")
os.makedirs(os.path.join(ROOT, "assets/scenes"), exist_ok=True)
ground.save(os.path.join(ROOT, "assets/scenes/zhaoying_arena_ground.png"))
print("ground", ground.size)

# ---------- 地面镜印 ----------
seal = Image.open(path("mirror_seal_decal")).convert("RGBA")
seal = remove_watermark(seal, (230, 0, 126, 255))
seal = key_magenta(seal)
seal = square_icon(seal, 512, 4)
os.makedirs(os.path.join(ROOT, "assets/effects/skills"), exist_ok=True)
seal.save(os.path.join(ROOT, "assets/effects/skills/mirror_seal.png"))
print("seal", seal.size)

# ---------- 图标表切格 ----------
sheet = Image.open(path("guanying_icon_sheet")).convert("RGBA")
sheet = remove_watermark(sheet, (230, 0, 126, 255))
cw = sheet.width // 4
ch = sheet.height // 3
cell_names = [
    None, None, None, None,
    None, None, None, None,
    None, "equip_shuiyue_pao", "mat_zhaoying_jingsha", "soul_guanying",
]
# 技能图标：1 弧斩 / 2 直刺 / 3 镜花 / 4 碎镜 / 5 换镜 / 6 镜返 / 7 镜湖 / 8 备用
skill_names = {
    0: "skill_mirror_slash",
    1: "skill_mirror_thrust",
    2: "skill_mirror_bloom",
    3: "skill_mirror_shatter",
    4: "skill_mirror_swap",
    5: "skill_mirror_return",
    6: "skill_mirror_ring",
}
icon_dir = os.path.join(ROOT, "assets/ui/icon")
os.makedirs(icon_dir, exist_ok=True)
for i, name in enumerate(cell_names):
    if name is None:
        continue
    r, c = i // 4, i % 4
    cell = sheet.crop((c * cw + 18, r * ch + 18, (c + 1) * cw - 18, (r + 1) * ch - 18))
    cell = key_magenta(cell)
    icon = square_icon(cell, 256, 12)
    icon.save(os.path.join(icon_dir, name + ".png"))
    print("icon", name)

for i, name in skill_names.items():
    r, c = i // 4, i % 4
    cell = sheet.crop((c * cw + 18, r * ch + 18, (c + 1) * cw - 18, (r + 1) * ch - 18))
    cell = key_magenta(cell)
    icon = square_icon(cell, 256, 12)
    icon.save(os.path.join(icon_dir, name + ".png"))
    print("icon", name)

for name in ["guanying_myriad_icon", "guanying_echo_icon", "jingtan_chi_icon", "guanying_token_icon"]:
    im = Image.open(path(name)).convert("RGBA")
    im = remove_watermark(im, (230, 0, 126, 255))
    im = key_magenta(im)
    out_name = {
        "guanying_myriad_icon": "skill_mirror_myriad",
        "guanying_echo_icon": "skill_mirror_echo",
        "jingtan_chi_icon": "equip_jingtan_chi",
        "guanying_token_icon": "tr_guanying_ling",
    }[name]
    square_icon(im, 256, 12).save(os.path.join(icon_dir, out_name + ".png"))
    print("icon", out_name)

# ---------- 武器局内贴图 ----------
weapon = Image.open(path("jingtan_chi_weapon")).convert("RGBA")
weapon = remove_watermark(weapon, (230, 0, 126, 255))
weapon = key_magenta(weapon)
weapon = trim(weapon, 4)
wcanvas = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
weapon = fit_into(weapon, 512, 512, 18)
wcanvas.alpha_composite(weapon, ((512 - weapon.width) // 2, (512 - weapon.height) // 2))
os.makedirs(os.path.join(ROOT, "assets/effects/weapons"), exist_ok=True)
wcanvas.save(os.path.join(ROOT, "assets/effects/weapons/jingtan_chi.png"))
print("weapon", wcanvas.size)
print("done")
