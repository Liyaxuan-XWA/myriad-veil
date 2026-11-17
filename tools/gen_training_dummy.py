"""Generate the training-dummy sprite used by the dojo."""

import math
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "characters", "training_dummy.png")

W, H = 256, 384
S = 4
cw, ch = W * S, H * S
img = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
d = ImageDraw.Draw(img)

INK = (28, 20, 14, 255)
WOOD_DARK = (72, 45, 26, 255)
WOOD = (122, 78, 42, 255)
WOOD_LIGHT = (168, 112, 62, 255)
STRAW_DARK = (142, 110, 58, 255)
STRAW = (192, 160, 92, 255)
STRAW_LIGHT = (224, 197, 128, 255)
ROPE = (105, 76, 43, 255)
TARGET_RED = (152, 45, 35, 255)
TARGET_RED_DARK = (104, 28, 24, 255)
TARGET_CREAM = (214, 191, 148, 255)


def sc(*vals):
    return tuple(int(v * S) for v in vals)


# Soft ground shadow
shadow = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
sd = ImageDraw.Draw(shadow)
sd.ellipse((48 * S, 342 * S, 210 * S, 378 * S), fill=(4, 3, 2, 150))
shadow = shadow.filter(ImageFilter.GaussianBlur(7 * S))
img.alpha_composite(shadow)

# Wooden base / cross feet
d.ellipse((46 * S, 340 * S, 210 * S, 372 * S), fill=INK, outline=INK)
d.ellipse((51 * S, 344 * S, 205 * S, 368 * S), fill=WOOD_DARK)
d.ellipse((58 * S, 348 * S, 198 * S, 364 * S), fill=WOOD)
d.ellipse((70 * S, 352 * S, 186 * S, 361 * S), fill=WOOD_LIGHT)
d.rectangle((114 * S, 356 * S, 142 * S, 370 * S), fill=WOOD_DARK)
d.line((84 * S, 356 * S, 172 * S, 356 * S), fill=(52, 31, 18, 255), width=int(3 * S))

# Main post
d.rounded_rectangle((115 * S, 142 * S, 141 * S, 354 * S), radius=int(7 * S),
                    fill=WOOD, outline=INK, width=int(3 * S))
d.line((121 * S, 154 * S, 121 * S, 344 * S), fill=WOOD_LIGHT, width=int(3 * S))
d.line((135 * S, 154 * S, 135 * S, 344 * S), fill=WOOD_DARK, width=int(2 * S))
for yy in (178, 232, 292, 326):
    d.line((118 * S, yy * S, 138 * S, (yy + 4) * S), fill=(80, 48, 27, 255), width=int(1.5 * S))

# Crossbar / wooden arms behind the straw body
d.rounded_rectangle((42 * S, 188 * S, 214 * S, 208 * S), radius=int(8 * S),
                    fill=WOOD_DARK, outline=INK, width=int(3 * S))
d.line((54 * S, 193 * S, 202 * S, 193 * S), fill=WOOD_LIGHT, width=int(3 * S))
# Straw wraps at the arm ends
for cx in (52, 204):
    d.ellipse(((cx - 17) * S, 180 * S, (cx + 17) * S, 216 * S), fill=STRAW_DARK, outline=INK,
              width=int(2 * S))
    for k in range(4):
        yy = 184 + k * 8
        d.line(((cx - 14) * S, yy * S, (cx + 14) * S, (yy + 1) * S),
               fill=STRAW if k % 2 == 0 else ROPE, width=int(2 * S))

# Straw torso (with ink outline + light rim)
d.rounded_rectangle((58 * S, 156 * S, 198 * S, 306 * S), radius=int(44 * S),
                    fill=STRAW_DARK, outline=INK, width=int(3 * S))
d.rounded_rectangle((63 * S, 161 * S, 193 * S, 300 * S), radius=int(40 * S),
                    fill=STRAW)
# straw strands
for i in range(56):
    x = 72 + (i * 37) % 108
    y = 170 + (i * 53) % 126
    ln = 6 + (i * 7) % 12
    col = STRAW_LIGHT if i % 3 else STRAW_DARK
    d.line((x * S, y * S, (x + (3 if i % 2 else -3)) * S, (y + ln) * S), fill=col,
           width=int(1.5 * S))
# side shading
d.arc((60 * S, 158 * S, 196 * S, 304 * S), 70, 130, fill=(104, 78, 40, 220), width=int(4 * S))
d.line((72 * S, 180 * S, 72 * S, 284 * S), fill=(225, 199, 132, 170), width=int(4 * S))

# Straw head and neck rope
d.ellipse((88 * S, 76 * S, 168 * S, 152 * S), fill=STRAW_DARK, outline=INK, width=int(3 * S))
d.ellipse((93 * S, 81 * S, 163 * S, 147 * S), fill=STRAW)
for i in range(18):
    x = 104 + (i * 29) % 48
    y = 90 + (i * 19) % 42
    d.line((x * S, y * S, (x + (2 if i % 2 else -2)) * S, (y + 7) * S),
           fill=STRAW_LIGHT if i % 2 else STRAW_DARK, width=int(1.5 * S))
d.arc((90 * S, 78 * S, 166 * S, 150 * S), 205, 320, fill=(236, 215, 160, 220), width=int(3 * S))
d.rounded_rectangle((112 * S, 144 * S, 144 * S, 158 * S), radius=int(5 * S), fill=ROPE,
                    outline=INK, width=int(2 * S))
d.line((114 * S, 151 * S, 142 * S, 151 * S), fill=(149, 112, 62, 255), width=int(2 * S))

# Ropes around the torso
for yy, tilt in ((168, 2), (266, -2), (286, 1)):
    d.line(((64 - tilt) * S, yy * S, (192 + tilt) * S, (yy + 4) * S), fill=ROPE,
           width=int(6 * S))
    d.line(((66 - tilt) * S, (yy - 2) * S, (190 + tilt) * S, (yy + 2) * S), fill=(160, 121, 70, 255),
           width=int(2 * S))
# diagonal rope cross on the lower torso
d.line((80 * S, 270 * S, 176 * S, 298 * S), fill=ROPE, width=int(5 * S))
d.line((176 * S, 270 * S, 80 * S, 298 * S), fill=ROPE, width=int(5 * S))

# Painted target
cx, cy = 128, 218
for r, col in ((58, TARGET_CREAM), (50, TARGET_RED_DARK), (42, TARGET_CREAM),
               (32, TARGET_RED), (23, TARGET_CREAM), (13, TARGET_RED_DARK),
               (6, TARGET_CREAM)):
    d.ellipse(((cx - r) * S, (cy - r) * S, (cx + r) * S, (cy + r) * S),
              outline=INK if r == 58 else None, width=int(2 * S), fill=col)
# small highlights on the target
d.arc(((cx - 50) * S, (cy - 50) * S, (cx + 50) * S, (cy + 50) * S), 200, 250,
      fill=(255, 232, 185, 170), width=int(2 * S))

# A couple of old hit marks on the left shoulder
for (x, y, ln, ang) in ((80, 178, 14, 0.5), (176, 184, 12, -0.4)):
    d.line((x * S, y * S, (x + math.cos(ang) * ln) * S, (y + math.sin(ang) * ln) * S),
           fill=(90, 60, 32, 220), width=int(2 * S))

# Warm rim light on the left silhouette
rim = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
rd = ImageDraw.Draw(rim)
rd.arc((57 * S, 155 * S, 199 * S, 307 * S), 120, 205, fill=(255, 218, 145, 150), width=int(3 * S))
rd.arc((87 * S, 75 * S, 169 * S, 153 * S), 120, 200, fill=(255, 226, 160, 150), width=int(2 * S))
rim = rim.filter(ImageFilter.GaussianBlur(1.2 * S))
img.alpha_composite(rim)

img = img.resize((W, H), Image.Resampling.LANCZOS)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
img.save(OUT)
print("saved", OUT)
