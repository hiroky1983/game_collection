#!/usr/bin/env python3
"""会長の猫シート（白背景）から各猫を切り抜き、背景を透過にして PNG に分ける。

外周から白を塗りつぶして背景だけ透過にする（猫の白い毛は塗りつぶしに届かないので残る）。
その後、透過マスクの行・列の投影で区画を再帰的に分割し、1 匹ずつ保存する。
"""
import os, sys
from PIL import Image, ImageDraw

SRC = sys.argv[1]
OUT = sys.argv[2]
os.makedirs(OUT, exist_ok=True)

im = Image.open(SRC).convert("RGB")
W, H = im.size
work = im.copy()
MAG = (255, 0, 255)
# 外周から塗りつぶし。閾値は白っぽい範囲を背景とみなす。
for x in range(0, W, 12):
    for y in (0, H - 1):
        if work.getpixel((x, y)) != MAG:
            ImageDraw.floodfill(work, (x, y), MAG, thresh=38)
for y in range(0, H, 12):
    for x in (0, W - 1):
        if work.getpixel((x, y)) != MAG:
            ImageDraw.floodfill(work, (x, y), MAG, thresh=38)

px = work.load()
src = im.load()
rgba = Image.new("RGBA", (W, H))
dst = rgba.load()
mask = [[0] * W for _ in range(H)]
for y in range(H):
    for x in range(W):
        if px[x, y] == MAG:
            dst[x, y] = (0, 0, 0, 0)
        else:
            r, g, b = src[x, y]
            # 背景（塗りつぶし）に接する画素だけ、白さに応じて半透明にして輪郭を滑らかにする。
            # 内側の白い毛はそのまま不透明に残す。
            edge = False
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < W and 0 <= ny < H and px[nx, ny] == MAG:
                    edge = True
                    break
            mn = min(r, g, b)
            a = 255
            if edge and mn >= 215:
                a = max(40, int((255 - mn) / 40 * 255))
            dst[x, y] = (r, g, b, a)
            mask[y][x] = 1


def components():
    """透過マスクの連結成分（8 近傍）の外接矩形を返す。"""
    seen = [[False] * W for _ in range(H)]
    boxes = []
    for y in range(H):
        row = mask[y]
        for x in range(W):
            if row[x] and not seen[y][x]:
                stack = [(x, y)]
                seen[y][x] = True
                x0 = x1 = x; y0 = y1 = y; n = 0
                while stack:
                    cx, cy = stack.pop()
                    n += 1
                    if cx < x0: x0 = cx
                    if cx > x1: x1 = cx
                    if cy < y0: y0 = cy
                    if cy > y1: y1 = cy
                    for dx in (-1, 0, 1):
                        for dy in (-1, 0, 1):
                            nx, ny = cx + dx, cy + dy
                            if 0 <= nx < W and 0 <= ny < H and mask[ny][nx] and not seen[ny][nx]:
                                seen[ny][nx] = True
                                stack.append((nx, ny))
                boxes.append([x0, y0, x1 + 1, y1 + 1, n])
    return boxes

def merge(boxes, grow=10):
    """外接矩形が（少し広げて）重なる成分を 1 つにまとめる（ひげ・鈴などの切れ端を本体へ戻す）。"""
    boxes = [b for b in boxes if b[4] >= 30]
    changed = True
    while changed:
        changed = False
        out = []
        while boxes:
            a = boxes.pop()
            merged = False
            for b in out:
                if (a[0] - grow < b[2] and a[2] + grow > b[0] and a[1] - grow < b[3] and a[3] + grow > b[1]):
                    # 小さい方を大きい方へ吸収する条件: どちらかが小さい
                    if min(a[4], b[4]) < 20000:
                        b[0] = min(a[0], b[0]); b[1] = min(a[1], b[1])
                        b[2] = max(a[2], b[2]); b[3] = max(a[3], b[3]); b[4] += a[4]
                        merged = True; changed = True
                        break
            if not merged:
                out.append(a)
        boxes = out
    return boxes


# シートの並びは目視で確定しているので、箱は手で指定する（ひげが隣とつながり自動分割できないため）。
NAMES = {
  "big_wave":   (0, 7, 487, 525),
  "face_normal":(500, 30, 724, 252),
  "face_happy": (748, 30, 964, 252),
  "face_angry": (988, 30, 1184, 252),
  "face_cry":   (1206, 30, 1405, 252),
  "face_relax": (532, 256, 790, 500),
  "face_grim":  (812, 256, 1050, 500),
  "face_wow":   (1072, 256, 1370, 500),
  "sit_front":  (8, 545, 295, 832),
  "sit_up":     (300, 545, 522, 832),
  "sit_side":   (540, 545, 882, 832),
  "sit_back":   (883, 545, 1150, 832),
  "sit_left":   (1151, 545, 1390, 832),
  "stretch":    (8, 843, 330, 1100),
  "pounce":     (340, 843, 710, 1100),
  "sleep":      (720, 880, 1045, 1100),
  "belly":      (1050, 843, 1395, 1100),
}
boxes = []
for name, (x0, y0, x1, y1) in NAMES.items():
    crop = rgba.crop((x0, y0, min(W, x1), min(H, y1)))
    # 箱の中で透過でない範囲に詰める
    bb = crop.getbbox()
    if bb:
        crop = crop.crop(bb)
    crop.save(os.path.join(OUT, f"{name}.png"))
    print(name, crop.size)
# 確認用の一覧
cols = 6
cell = 220
sheet = Image.new("RGBA", (cols * cell, ((len(NAMES) + cols - 1) // cols) * cell), (120, 200, 160, 255))
d = ImageDraw.Draw(sheet)
for i, name in enumerate(NAMES):
    c = Image.open(os.path.join(OUT, f"{name}.png"))
    c.thumbnail((cell - 20, cell - 40))
    cx, cy = (i % cols) * cell, (i // cols) * cell
    sheet.alpha_composite(c, (cx + 10, cy + 10))
    d.text((cx + 6, cy + cell - 24), f"{name} {c.size}", fill=(0, 0, 0, 255))
sheet.save(os.path.join(OUT, "_contact.png"))
