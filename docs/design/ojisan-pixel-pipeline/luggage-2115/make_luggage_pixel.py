#!/usr/bin/env python3
"""Codex が描いた荷物 5 種の 2D 絵（src/）を、ゲームの 1 マスに入るドット絵へ落とす（#2115）。

手法は docs/design/ojisan-pixel-pipeline/outfit-pixel/make_outfit_pixel.py と同じ:
 白背景を枠からの塗りつぶしで透過 → 5×5 メディアン → 荷物ごとの固定パレットに減色 →
 最頻色縮小（縁取り色は一定割合で優先）→ 孤立ドット除去・多数決・輪郭の縁取り。
出力: px{N}/{name}.png（N×N に中央寄せ、余白は透明）と sheet_luggage.png（元絵と各サイズの比較）。
色はゲーム（OjisanPuzzleLuggageArt.base / dark）の値をパレットに固定して、色分けが変わらないようにする。
"""
import os
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/Users/yamadahiroki/myspace/game_collection/docs/design/ojisan-pixel-pipeline/outfit-pixel")
from pxlib import label, flood_bg, comp_info  # noqa: E402

SRC = os.path.join(HERE, "src")
SIZES = (32, 24, 18)
MEDIAN = 5
OUTLINE_SHARE = 0.38
K = (0x26, 0x22, 0x2C)   # 縁取り（おじさんのドット絵と同じ）

# ゲームの色（OjisanPuzzleLuggageArt.base / dark）
GAME = {
    1: ((0xB4, 0x97, 0xF0), (0x5E, 0x45, 0x9C)),
    2: ((0x62, 0xD2, 0x66), (0x1F, 0x6B, 0x2C)),
    3: ((0x1F, 0x4F, 0xC2), (0x0B, 0x22, 0x6B)),
    4: ((0xCC, 0x2E, 0x24), (0x6B, 0x12, 0x0C)),
    5: ((0xF7, 0xC5, 0x31), (0x8A, 0x62, 0x00)),
}


def mix(a, b, t):
    return tuple(int(round(a[i] * (1 - t) + b[i] * t)) for i in range(3))


WHITE = (0xFA, 0xFA, 0xFA)
GREY = (0xD2, 0xD2, 0xD8)
BROWN = (0x6E, 0x44, 0x22)
BROWN_D = (0x46, 0x2A, 0x14)
BROWN_L = (0x9A, 0x6A, 0x3C)
YELLOW = (0xF5, 0xC5, 0x42)
YELLOW_D = (0xB8, 0x86, 0x0B)

# 荷物ごとの固定パレット。先頭は必ず縁取り K。面色・影色・明色はゲームの base/dark から作る。
ITEMS = [
    # (name, value, 日本語, palette)
    ("01_zabuton", 1, "座布団の山（重さ 1）", [
        K, GAME[1][0], mix(GAME[1][0], GAME[1][1], 0.5), GAME[1][1], mix(GAME[1][0], WHITE, 0.45), WHITE,
    ]),
    ("02_suika", 2, "スイカ（重さ 2）", [
        K, GAME[2][0], GAME[2][1], mix(GAME[2][0], WHITE, 0.45), BROWN, BROWN_D,
    ]),
    ("03_coolerbox", 3, "クーラーボックス（重さ 3）", [
        K, GAME[3][0], mix(GAME[3][0], GAME[3][1], 0.55), GAME[3][1], mix(GAME[3][0], WHITE, 0.35), WHITE, GREY,
    ]),
    ("04_polytank", 4, "灯油のポリタンク（重さ 4）", [
        K, GAME[4][0], mix(GAME[4][0], GAME[4][1], 0.5), GAME[4][1], mix(GAME[4][0], WHITE, 0.4), YELLOW, YELLOW_D, WHITE,
    ]),
    ("05_beercase", 5, "ビールケース（重さ 5）", [
        K, GAME[5][0], mix(GAME[5][0], GAME[5][1], 0.5), GAME[5][1], mix(GAME[5][0], WHITE, 0.45), BROWN, BROWN_D, BROWN_L, WHITE,
    ]),
]


# ---------------------------------------------------------------- 背景抜き
def key_out(rgb):
    H, W, _ = rgb.shape
    is_bg = (rgb[:, :, 0] >= 232) & (rgb[:, :, 1] >= 232) & (rgb[:, :, 2] >= 232)
    bg = flood_bg(is_bg)
    lab, n = label(~bg)
    infos = comp_info(lab, n)
    keep = np.zeros((H, W), dtype=bool)
    dropped = []
    main = infos[0]
    for i, d in enumerate(infos):
        if i == 0:
            keep |= lab == d["id"]
            continue
        # 本体の箱の近く（房・ヘタなどの飛び地）だけ残す。離れたゴミは落とす
        near = (d["x0"] >= main["x0"] - 40 and d["x1"] <= main["x1"] + 40
                and d["y0"] >= main["y0"] - 60 and d["y1"] <= main["y1"] + 40)
        if d["size"] >= 60 and near:
            keep |= lab == d["id"]
        else:
            dropped.append(f"{d['x1']-d['x0']+1}x{d['y1']-d['y0']+1}")
    rgba = np.dstack([rgb, np.where(keep, 255, 0).astype(np.uint8)]).astype(np.uint8)
    return rgba, dropped


def median_rgb(rgba, size=MEDIAN):
    im = Image.fromarray(rgba[:, :, :3], "RGB").filter(ImageFilter.MedianFilter(size))
    out = rgba.copy()
    out[:, :, :3] = np.array(im)
    return out


def quantize(rgba, pal):
    P = np.array(pal, dtype=int)
    rgb = rgba[:, :, :3].astype(int)
    d = ((rgb[:, :, None, :] - P[None, None, :, :]) ** 2).sum(-1)
    idx = d.argmin(-1)
    idx[rgba[:, :, 3] == 0] = -1
    return idx


def mode_down(idx, scale, npal, outline_share=OUTLINE_SHARE):
    H, W = idx.shape
    tw, th = max(1, int(round(W * scale))), max(1, int(round(H * scale)))
    out = -np.ones((th, tw), dtype=int)
    for oy in range(th):
        y0, y1 = int(oy / scale), max(int(oy / scale) + 1, int((oy + 1) / scale))
        for ox in range(tw):
            x0, x1 = int(ox / scale), max(int(ox / scale) + 1, int((ox + 1) / scale))
            cell = idx[y0:min(y1, H), x0:min(x1, W)].ravel()
            total = cell.size
            op = cell[cell >= 0]
            if not total or op.size * 2 < total:
                continue
            counts = np.bincount(op, minlength=npal)
            if counts[0] >= op.size * outline_share:
                out[oy, ox] = 0
            else:
                counts[0] = 0
                out[oy, ox] = int(counts.argmax())
    return out


def drop_specks(idx, min_size=2):
    lab, n = label(idx >= 0)
    for d in comp_info(lab, n):
        if d["size"] < min_size:
            idx[lab == d["id"]] = -1
    return idx


def majority_vote(idx, prot=(0,)):
    H, W = idx.shape
    src = idx.copy()
    for y in range(H):
        for x in range(W):
            c = src[y, x]
            if c < 0 or c in prot:
                continue
            nb = [src[y + dy, x + dx] if 0 <= x + dx < W and 0 <= y + dy < H else -1
                  for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))]
            if c in nb:
                continue
            op = [v for v in nb if v >= 0 and v not in prot]
            if op:
                idx[y, x] = max(set(op), key=op.count)
    return idx


def ensure_outline(idx, min_comp=12):
    H, W = idx.shape
    lab, n = label(idx >= 0)
    big = {d["id"] for d in comp_info(lab, n) if d["size"] >= min_comp}
    src = idx.copy()
    for y in range(H):
        for x in range(W):
            c = src[y, x]
            if c <= 0 or lab[y, x] not in big:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if not (0 <= nx < W and 0 <= ny < H) or src[ny, nx] < 0:
                    idx[y, x] = 0
                    break
    return idx


def prune_islands(idx, n):
    """本体から離れた小さな塊（房の切れ端など）を落とす。本体（最大の塊）と、ある程度大きい塊だけ残す。"""
    lab, cnt = label(idx >= 0)
    infos = comp_info(lab, cnt)
    keep_min = max(6, n * n // 40)
    for i, d in enumerate(infos):
        if i == 0 or d["size"] >= keep_min:
            continue
        idx[lab == d["id"]] = -1
    return idx


def crop_idx(idx):
    ys, xs = np.nonzero(idx >= 0)
    return idx[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def to_image(idx, pal):
    H, W = idx.shape
    out = np.zeros((H, W, 4), dtype=np.uint8)
    for i, c in enumerate(pal):
        out[idx == i] = tuple(c) + (255,)
    return Image.fromarray(out, "RGBA")


def center_in(idx, n):
    """切り出したドットを n×n の中央に置く（はみ出すときは落とす）。"""
    h, w = idx.shape
    out = -np.ones((n, n), dtype=int)
    y0, x0 = (n - h) // 2, (n - w) // 2
    sy, sx = max(0, -y0), max(0, -x0)
    y0, x0 = max(0, y0), max(0, x0)
    hh, ww = min(h - sy, n - y0), min(w - sx, n - x0)
    out[y0:y0 + hh, x0:x0 + ww] = idx[sy:sy + hh, sx:sx + ww]
    return out


def thicken_outline(idx, r):
    """縁取り（0）を r px 太らせる。元絵の細い区切り線（座布団の段・瓶の首）が縮小で消えないようにする。"""
    if r < 1:
        return idx
    m = Image.fromarray(np.where(idx == 0, 255, 0).astype(np.uint8), "L").filter(ImageFilter.MaxFilter(2 * int(r) + 1))
    out = idx.copy()
    out[(np.array(m) > 0) & (idx >= 0)] = 0
    return out


MARGIN = 1          # マスの中の余白（ドット）。隣のマスの同じ荷物と輪郭がくっつかないように
THICKEN = 0.30      # 縁取りを太らせる量（1 ドットの元絵上の幅に対する割合）


OPEN_ITEMS = {"01_zabuton"}   # 房の切れ端が 1 ドットの突起になって残るので、3×3 の開演算で落とす


def open_mask(idx):
    m = Image.fromarray(np.where(idx >= 0, 255, 0).astype(np.uint8), "L")
    opened = np.array(m.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(3))) > 0
    out = idx.copy()
    out[~opened] = -1
    return out


def pixelize(idx_full, n, npal, name=""):
    """不透明部分の長辺が n - 2*MARGIN ドットになる縮尺で落とし、n×n に中央寄せ。"""
    target = n - MARGIN * 2
    ys, xs = np.nonzero(idx_full >= 0)
    long_px = max(ys.max() - ys.min() + 1, xs.max() - xs.min() + 1)
    sub = idx_full[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    scale = target / float(long_px)
    min_size = max(2, int(round(n * n / 160.0)))
    for _ in range(4):
        thick = thicken_outline(sub, THICKEN / scale)
        small = mode_down(thick, scale, npal)
        small = majority_vote(drop_specks(small, min_size))
        if name in OPEN_ITEMS:
            small = open_mask(small)
        small = ensure_outline(small)
        small = prune_islands(small, n)
        small = crop_idx(small)
        got = max(small.shape)
        if got == target:
            break
        scale *= target / float(got)
    if max(small.shape) > target:
        small = small[:target, :target]
    return center_in(small, n)


def font(size):
    for p in ("/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc", "/System/Library/Fonts/Hiragino Sans GB.ttc"):
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except Exception:
                pass
    return ImageFont.load_default()


def main():
    results = {}
    keyed = {}
    for name, value, label_ja, pal in ITEMS:
        src = Image.open(f"{SRC}/{name}.png").convert("RGBA")
        rgb = np.array(Image.alpha_composite(Image.new("RGBA", src.size, "white"), src).convert("RGB"))
        rgba, dropped = key_out(rgb)
        keyed[name] = rgba
        ys, xs = np.nonzero(rgba[:, :, 3])
        print(f"{name}: 元 {src.size} 本体 {xs.max()-xs.min()+1}x{ys.max()-ys.min()+1}px"
              + (f" 落とした: {dropped}" if dropped else ""))
        idx_full = quantize(median_rgb(rgba), pal)
        for n in SIZES:
            os.makedirs(f"{HERE}/px{n}", exist_ok=True)
            small = pixelize(idx_full, n, len(pal), name)
            img = to_image(small, pal)
            img.save(f"{HERE}/px{n}/{name}.png")
            results[(n, name)] = img
            used = len({int(v) for v in small.ravel() if v >= 0})
            print(f"  px{n}: {used} 色")

    # 比較一覧: 元絵 / 32 / 24 / 18
    f_title, f_label, f_small = font(26), font(20), font(15)
    DISP = 160
    margin, col_w, lab_w = 32, 200, 230
    row_h = 36 + DISP + 16
    W = margin * 2 + lab_w + col_w * (1 + len(SIZES))
    H = 70 + row_h * len(ITEMS) + 20
    canvas = Image.new("RGBA", (W, H), (0xFF, 0xF6, 0xEC, 255))
    d = ImageDraw.Draw(canvas)
    d.text((margin, 20), "荷物 5 種 ドット化（左: Codex の 2D 元絵 / " + " / ".join(f"{n} ドット" for n in SIZES) + "）",
           fill=(74, 59, 51), font=f_title)
    y = 70
    for name, value, label_ja, pal in ITEMS:
        d.text((margin, y + DISP // 2), label_ja, fill=(74, 59, 51), font=f_label)
        x = margin + lab_w
        rgba = keyed[name]
        ys, xs = np.nonzero(rgba[:, :, 3])
        src = Image.fromarray(rgba, "RGBA").crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
        k = DISP / float(max(src.size))
        s = src.resize((max(1, round(src.size[0] * k)), max(1, round(src.size[1] * k))), Image.LANCZOS)
        canvas.alpha_composite(s, (x + (col_w - s.size[0]) // 2, y + 36 + (DISP - s.size[1]) // 2))
        x += col_w
        for n in SIZES:
            img = results[(n, name)]
            k = max(1, DISP // n)
            big = img.resize((n * k, n * k), Image.NEAREST)
            canvas.alpha_composite(big, (x + (col_w - big.size[0]) // 2, y + 36 + (DISP - big.size[1]) // 2))
            d.text((x + 8, y + 10), f"{n}×{n} ドット ×{k}", fill=(154, 138, 128), font=f_small)
            x += col_w
        y += row_h
    canvas.convert("RGB").save(f"{HERE}/sheet_luggage.png")
    print("sheet_luggage.png", canvas.size)


if __name__ == "__main__":
    main()
