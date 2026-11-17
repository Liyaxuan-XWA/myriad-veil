"""晏无咎卡面 / 战场地面落盘（2026-10-29）。"""
from PIL import Image, ImageEnhance

CARD_SRC = "vibe_images/card_boss_wujiu_1793234123765_4f19d571.png"
GROUND_SRC = "vibe_images/calamity_arena_ground_1793234151570_484273a4.png"


def crop_to(im, w, h):
    ar = w / h
    iw, ih = im.size
    if iw / ih > ar:
        nw = int(ih * ar)
        x = (iw - nw) // 2
        im = im.crop((x, 0, x + nw, ih))
    else:
        nh = int(iw / ar)
        y = (ih - nh) // 2
        im = im.crop((0, y, iw, y + nh))
    return im.resize((w, h), Image.LANCZOS)


card = Image.open(CARD_SRC).convert("RGB")
card = crop_to(card, 640, 960)
card = ImageEnhance.Contrast(card).enhance(1.04)
card.save("assets/ui/codex/card_boss_wujiu.png")
print("card", card.size)

ground = Image.open(GROUND_SRC).convert("RGB")
ground = crop_to(ground, 1200, 676)
ground = ImageEnhance.Brightness(ground).enhance(0.94)
ground.save("assets/scenes/calamity_arena_ground.png")
print("ground", ground.size)
