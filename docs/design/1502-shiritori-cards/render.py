#!/usr/bin/python3
"""スプライト JSON を PNG に描く共通ユーティリティ（一覧・単体拡大）。"""
import json, sys
from PIL import Image, ImageDraw, ImageFont

import os
OUT = os.path.dirname(os.path.abspath(__file__))
FONT = "/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc"
BG = (0xFF, 0xF6, 0xE8)


def sprite_image(sp, scale):
    rows, pal = sp["rows"], sp["palette"]
    h, w = len(rows), len(rows[0])
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == ".":
                continue
            c = pal[ch]
            px[x, y] = (int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16), 255)
    return img.resize((w * scale, h * scale), Image.NEAREST)


def sheet(items, cols, scale, path, label_size=20, cell_pad=12):
    """items: list of (sprite, label)。"""
    font = ImageFont.truetype(FONT, label_size)
    cell_w = 40 * scale + cell_pad * 2
    cell_h = 40 * scale + label_size + cell_pad * 2 + 6
    rows_n = (len(items) + cols - 1) // cols
    img = Image.new("RGB", (cell_w * cols, cell_h * rows_n), BG)
    d = ImageDraw.Draw(img)
    for i, (sp, label) in enumerate(items):
        cx, cy = (i % cols) * cell_w, (i // cols) * cell_h
        tile = sprite_image(sp, scale)
        img.paste(tile, (cx + cell_pad, cy + cell_pad), tile)
        tw = d.textlength(label, font=font)
        d.text((cx + (cell_w - tw) / 2, cy + cell_pad + 40 * scale + 4), label, fill=(0x3A, 0x2A, 0x2A), font=font)
    img.save(path)
    return path


if __name__ == "__main__":
    # 使い方: render.py <json> <name>... で 6 倍単体 PNG を出す
    data = json.load(open(sys.argv[1], encoding="utf-8"))
    sprites = data.get("sprites", data)
    names = sys.argv[2:] or list(sprites)
    items = [(sprites[n], n) for n in names]
    out = f"{OUT}/preview-{'-'.join(names)[:60]}.png"
    sheet(items, min(len(items), 4), 6, out)
    print(out)
