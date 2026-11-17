"""位面星图旋转木马的静态预览：新底图 + 代码画环的前三档与深处一档。

只用来给你一次看全「画风对不对」和「结构对不对」，不进游戏、不改代码。
环的位置是改版前 GATE_LAYOUT 的四点（前排三格 + 深处一格）；
现在代码里的槽位改成了 domain_star_map.gd 的 SLOTS，半径收小约 12%。
本脚本只用于「门 sprite 观感对不对」的一次性预览，不参与落盘。
"""
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import math

BG = ".scratch/位面星图/realm_select_bg_clean.png"
OLD = ".scratch/位面星图/realm_select_bg_backup_with_gates.png"
OUT = "output/star_map_carousel_mock.png"
DW, DH = 1280, 720

# (源图坐标 cx, cy, r, 颜色, 界名, 是否在深处)
SLOTS = [
	(654, 801, 220, (122, 219, 255), "凡界", False),
	(1365, 818, 258, (255, 199, 97), "冲和界", False),
	(2074, 780, 215, (219, 168, 255), "赤霄界", False),
	(1365, 270, 150, (210, 224, 255), "照影界", True),
]


def cover(im, w=DW, h=DH):
	s = max(w / im.size[0], h / im.size[1])
	r = im.resize((round(im.size[0] * s), round(im.size[1] * s)), Image.LANCZOS)
	x = (r.size[0] - w) // 2
	y = (r.size[1] - h) // 2
	return r.crop((x, y, x + w, y + h))


def draw_gate(base, cx, cy, rad, color, name, depth, font, small):
	sx = DW / 2730.0
	x, y, r = cx * sx, cy * DW / 2730.0, rad * sx
	dim = 0.42 if depth else 1.0
	tint = tuple(int(c * dim) for c in color)
	layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
	d = ImageDraw.Draw(layer)
	# 辉光：三层由粗到细，模拟代码里描边+外发光的观感
	for wdt, alpha in ((14, 46), (7, 96), (3, 210)):
		d.ellipse([x - r, y - r, x + r, y + r], outline=tint + (int(alpha * dim),), width=wdt)
	d.ellipse([x - r * 0.9, y - r * 0.9, x + r * 0.9, y + r * 0.9],
	          fill=tint + (int(26 * dim),))
	glow = layer.filter(ImageFilter.GaussianBlur(9))
	base.alpha_composite(glow)
	base.alpha_composite(layer)
	d2 = ImageDraw.Draw(base)
	# 铭牌统一挂在环的正下方（深处那格也挂下面，不再刻在镜面里）
	w_pl, h_pl = 128, 30
	px, py = x - w_pl // 2, y + r + 10
	plate_a = 90 if depth else 200
	d2.rounded_rectangle([px, py, px + w_pl, py + h_pl], radius=6, fill=(16, 14, 26, 205), outline=tint + (plate_a,))
	tb = d2.textbbox((0, 0), name, font=font)
	d2.text((x - (tb[2] - tb[0]) / 2, py + 3), name, font=font, fill=(236, 232, 220, 255 if not depth else 130))
	if depth:
		d2.text((x - 34, py + h_pl + 4), "深处 · 不可点", font=small, fill=(190, 186, 176, 150))


def main():
	try:
		font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 19)
		small = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 14)
		title = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 20)
	except Exception:
		font = small = title = ImageFont.load_default()

	new = cover(Image.open(BG).convert("RGB")).convert("RGBA")
	for cx, cy, r, col, name, depth in SLOTS:
		draw_gate(new, cx, cy, r, col, name, depth, font, small)

	old = cover(Image.open(OLD).convert("RGB")).convert("RGBA")
	ST = 30
	canvas = Image.new("RGB", (DW, (DH + ST) * 2), (8, 6, 14))
	d = ImageDraw.Draw(canvas)
	d.text((12, 5), "现在：四扇镜门画死在底图里，铭牌三套口径", fill=(255, 214, 150), font=title)
	canvas.paste(old, (0, ST))
	y1 = DH + ST
	d.text((12, y1 + 5), "新：纯星云底图 + 代码画环（前排三格可点，深处一格压暗不可点）", fill=(150, 226, 255), font=title)
	canvas.paste(new.convert("RGB"), (0, y1 + ST))
	canvas.save(OUT)
	print("saved", OUT, canvas.size)


if __name__ == "__main__":
	main()
