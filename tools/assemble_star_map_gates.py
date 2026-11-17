"""把四张独立光门 sprite 加性合成到纯星云底图上，产出旋转木马的观感预览。

sprite 是「纯黑底 + 只有门自己的辉光」，所以合成只能用加性：黑底加进去等于不加。
不能直接 alpha 混合，否则黑底会把星云压成一块死黑方框。

尺寸对齐靠实测的环带峰值半径，不靠目测：
    缩放系数 = 源图里那扇门的半径 / sprite 里环带的峰值半径
半径口径 = 改版前画死在底图里的那四扇门（GATE_LAYOUT 的旧值）。
domain_star_map.gd 现在用的是 SLOTS，半径整体收了约 12%（面板可视区只有 1082×532，
原尺寸下辉光会压到信息条），所以这里的数**不再等于代码里的数**，只用来还原旧观感。
"""
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import numpy as np
import glob

BG = ".scratch/位面星图/realm_select_bg_clean.png"
OUT_FULL = ".scratch/位面星图/realm_select_bg_gated.png"
OUT_MOCK = "output/star_map_carousel_mock.png"
DW, DH = 1280, 720

# domain_id, 界名, 源图中心 x, y, 环半径, sprite 通配, 是否深处格
LAYOUT = [
	("domain_01", "凡界", 1365, 818, 258, "gate_domain_01_fanjie", False),
	("domain_02", "冲和界", 654, 801, 220, "gate_domain_02_chonghe", False),
	("domain_03", "赤霄界", 2074, 780, 215, "gate_domain_03_chixiao", False),
	("domain_04", "照影界", 1365, 270, 150, "gate_domain_04_zhaoying", True),
]
# 照影界是「镜」不是「洞」：加性画不出暗面，所以镜面内部要先压暗再叠环。
# 与 tools/composite_mirror_gate.py 的 INNER_DIM / WATER 同一口径。
MIRROR_INNER_DIM = 0.55
MIRROR_WATER = (16, 24, 42)


def ring_radius_px(a):
	"""径向亮度剖面的峰值半径 = 环带所在半径。"""
	lum = a @ np.array([.299, .587, .114], np.float32)
	h, w = lum.shape
	yy, xx = np.mgrid[0:h, 0:w]
	r = np.hypot(xx - w * 0.5, yy - h * 0.5).astype(np.int32)
	prof = np.bincount(r.ravel(), weights=lum.ravel(), minlength=600) / np.maximum(np.bincount(r.ravel(), minlength=600), 1)
	return int(np.argmax(prof[40:500]) + 40)


def sprite_path(pat):
	c = sorted(glob.glob("vibe_images/%s_*.png" % pat))
	if not c:
		raise SystemExit("找不到 sprite：%s" % pat)
	return c[-1]


def lum(a):
	return a @ np.array([.299, .587, .114], np.float32)


def annulus_mean(a, cx, cy, r, lo=0.82, hi=1.18):
	"""环带 ±18% 那一圈的平均 RGB —— 跟原画对账就量这个。"""
	h, w = a.shape[:2]
	yy, xx = np.mgrid[0:h, 0:w]
	d = np.hypot(xx - cx, yy - cy) / float(r)
	m = (d >= lo) & (d <= hi)
	return a[m].mean(0) if m.sum() else np.zeros(3, np.float32)


def ring_layer(pat, src_r):
	"""按源半径缩放后的 sprite 图层，以及它的边长。"""
	a = np.asarray(Image.open(sprite_path(pat)).convert("RGB"), np.float32) / 255.0
	side = int(round(a.shape[1] * src_r / float(ring_radius_px(a))))
	g = np.asarray(Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).resize((side, side), Image.LANCZOS), np.float32) / 255.0
	return g, side


def calibrate_gain(bg, g, side, src_r, cx, cy, old_ref, target_mult=1.0):
	"""反解加性增益，使合成后环带亮度 == 原画那扇门的环带亮度（可再乘一个目标系数）。

	合成是加性的，环带均值对增益线性：mean(bg + k*sprite) = mean(bg) + k*mean(sprite)，
	所以 k 直接解出来。不这么算就只能目测，目测的第一版实测四扇门全部过曝成白边。
	"""
	crop = np.zeros_like(bg)
	h, w = bg.shape[:2]
	x0, y0 = int(cx - side / 2), int(cy - side / 2)
	sx0, sy0 = max(0, x0), max(0, y0)
	sx1, sy1 = min(w, x0 + side), min(h, y0 + side)
	crop[sy0:sy1, sx0:sx1] = g[sy0 - y0:sy1 - y0, sx0 - x0:sx1 - x0]
	ol = float(lum(annulus_mean(old_ref, cx, cy, src_r))) * target_mult
	bl = float(lum(annulus_mean(bg, cx, cy, src_r)))
	sl = float(lum(annulus_mean(crop, cx, cy, src_r)))
	if sl <= 1e-6:
		return 1.0
	return float(np.clip((ol - bl) / sl, 0.02, 2.0))


def composite_gate(bg, pat, src_r, cx, cy, dim=1.0, mirror=False, gain=1.0):
	a = np.asarray(Image.open(sprite_path(pat)).convert("RGB"), np.float32) / 255.0
	r_px = ring_radius_px(a)
	scale = src_r / float(r_px)
	side = int(round(a.shape[1] * scale))
	im = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).resize((side, side), Image.LANCZOS)
	g = np.asarray(im, np.float32) / 255.0 * dim * gain

	h, w = bg.shape[:2]
	x0 = int(cx - side / 2)
	y0 = int(cy - side / 2)
	x1, y1 = x0 + side, y0 + side
	sx0, sy0 = max(0, x0), max(0, y0)
	sx1, sy1 = min(w, x1), min(h, y1)
	if sx1 <= sx0 or sy1 <= sy0:
		return bg
	g = g[sy0 - y0:sy1 - y0, sx0 - x0:sx1 - x0]

	if mirror:
		# 镜面内部压暗：只压到环带半径的 0.86 倍以内，边缘羽化，避免切出硬圆盘
		yy, xx = np.mgrid[0:g.shape[0], 0:g.shape[1]]
		d = np.hypot(xx - g.shape[1] / 2, yy - g.shape[0] / 2)
		inner = np.clip((src_r * 0.86 - d) / (src_r * 0.22), 0, 1)
		water = np.array(MIRROR_WATER, np.float32) / 255.0
		region = bg[sy0:sy1, sx0:sx1]
		bg[sy0:sy1, sx0:sx1] = region * (1 - inner[..., None]) + (region * MIRROR_INNER_DIM + water * (1 - MIRROR_INNER_DIM)) * inner[..., None]

	# 加性：sprite 的黑底加进去等于不加，辉光照原样落在星云上
	bg[sy0:sy1, sx0:sx1] = np.clip(bg[sy0:sy1, sx0:sx1] + g, 0, 1)
	return bg


def cover(im, w=DW, h=DH):
	s = max(w / im.size[0], h / im.size[1])
	r = im.resize((round(im.size[0] * s), round(im.size[1] * s)), Image.LANCZOS)
	x = (r.size[0] - w) // 2
	y = (r.size[1] - h) // 2
	return r.crop((x, y, x + w, y + h))


def plaques(img, fonts):
	"""铭牌统一挂在每扇门的正下方；深处那格压暗并标注不可点。"""
	d = ImageDraw.Draw(img, "RGBA")
	font, small = fonts
	sx = DW / 2730.0
	for _did, name, cx, cy, r, _pat, depth in LAYOUT:
		x, y, rr = cx * sx, cy * sx, r * sx
		# 铭牌贴在辉光外沿之下：环半径 + 该门辉光的经验外扩
		pad = rr * (0.34 if not depth else 0.5)
		w_pl, h_pl = 132, 32
		px, py = x - w_pl / 2, y + rr + pad
		d.rounded_rectangle([px, py, px + w_pl, py + h_pl], radius=7,
		                    fill=(14, 12, 24, 210), outline=(180, 172, 156, 70 if depth else 150), width=1)
		tb = d.textbbox((0, 0), name, font=font)
		d.text((x - (tb[2] - tb[0]) / 2, py + 5), name, font=font, fill=(238, 234, 224, 130 if depth else 255))
		if depth:
			# 深处那格的说明挪到环的正上方：下方正对着凡界门的辉光，压在上面读不出来
			sb = d.textbbox((0, 0), "深处 · 暂不可入", font=small)
			d.text((x - sb[2] / 2, y - rr - pad - 24), "深处 · 暂不可入", font=small, fill=(196, 190, 178, 150))
	return img


def main():
	bg = np.asarray(Image.open(BG).convert("RGB"), np.float32) / 255.0
	old_ref = np.asarray(Image.open(".scratch/位面星图/realm_select_bg_backup_with_gates.png").convert("RGB"), np.float32) / 255.0
	for did, _name, cx, cy, r, pat, depth in LAYOUT:
		g, side = ring_layer(pat, r)
		# 深处格不是「同一亮度」，它要明显更暗才读得出在景深后面；目标亮度按 0.55 折。
		k = calibrate_gain(bg, g, side, r, cx, cy, old_ref, 0.55 if depth else 1.0)
		bg = composite_gate(bg, pat, r, cx, cy, mirror=(did == "domain_04"), gain=k)
		before = lum(annulus_mean(bg, cx, cy, r))
		print("%s 半径 %d 增益 %.3f -> 环带亮度 %.3f（原画 %.3f）"
		      % (did, r, k, before, lum(annulus_mean(old_ref, cx, cy, r))))
	full = Image.fromarray((np.clip(bg, 0, 1) * 255).astype(np.uint8))
	full.save(OUT_FULL)

	font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 19)
	small = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 14)
	new = plaques(cover(full).convert("RGBA"), (font, small)).convert("RGB")

	old = cover(Image.open(".scratch/位面星图/realm_select_bg_backup_with_gates.png").convert("RGB"))
	ST = 30
	canvas = Image.new("RGB", (DW, (DH + ST) * 2), (8, 6, 14))
	d = ImageDraw.Draw(canvas)
	d.text((12, 5), "现在：四扇门画死在底图里（位置固定、不能转）", fill=(255, 214, 150), font=font)
	canvas.paste(old, (0, ST))
	y1 = DH + ST
	d.text((12, y1 + 5), "新：纯星云底图 + 四张独立门 sprite（前排三格可点，深处一格压暗）", fill=(150, 226, 255), font=font)
	canvas.paste(new, (0, y1 + ST))
	canvas.save(OUT_MOCK)
	print("预览", OUT_MOCK, canvas.size)


if __name__ == "__main__":
	main()
