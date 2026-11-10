#!/usr/bin/env python3
"""花札 光札 4 枚の描き直しモック（#2188）。

入力:
  src/*.png      Codex（画像生成）が文章の指示だけで描いた 2D 線画ベタ塗り（1024×1536・案①）
  current/*.png  現行の `HanafudaCardFace`（Canvas 描画）を ImageRenderer で書き出したもの
                 （_w400: 400×600、_w50: アプリの実寸 50pt 幅を 3x で 150×225）
出力:
  px40/ px56/        案②: 案①を固定パレットで 40×60 / 56×84 ドットに落としたもの（1 ドット = 1px・不透明）
  compare_new.png    案①と案②の比較（アプリの帯・角丸を模した枠付き）
  compare_current.png 現行の札 4 枚との比較（大きく見た図＋アプリの実寸相当）

ドット化は docs/design/ojisan-pixel-pipeline/luggage-2115/make_luggage_pixel.py の手法の流用
（メディアン → 固定パレットに減色 → 最頻色縮小・縁取り優先 → 多数決）。札は地が不透明なので
背景抜き・輪郭の補完は要らない。新規の絵は描いていない。

実行（Pillow + numpy。anaconda の python3）:
  /Users/yamadahiroki/opt/anaconda3/bin/python3 make_mock.py
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
CARDS = [
    ("01_matsu_tsuru", "松に鶴", 1),
    ("02_sakura_maku", "桜に幕", 3),
    ("03_susuki_tsuki", "芒に月", 8),
    ("04_yanagi_michikaze", "柳に小野道風", 11),
]
ASPECT = 1.5          # HanafudaCardArt.aspectRatio
BAND_RATIO = 0.15     # HanafudaCardFace.bandRatio
CORNER_RATIO = 0.12   # 角丸（幅に対する割合）
BAND_HIKARI = (0xD4, 0xA9, 0x3A)   # HanafudaCardArt.kindHex(.hikari)
INK = (0x3A, 0x2E, 0x27)           # HanafudaCardArt.inkHex
PAPER_BG = (0xFF, 0xF6, 0xEC)

# 案②の固定パレット（Codex への指示で限定した伝統色 ＋ 影用に 1 段暗い色）
K = (0x1C, 0x1A, 0x17)


def mix(a, b, t):
    return tuple(int(round(a[i] * (1 - t) + b[i] * t)) for i in range(3))


PAPER = (0xF2, 0xE6, 0xC9)
RED = (0xC8, 0x35, 0x2A)
GOLD = (0xD9, 0xA4, 0x41)
GREEN = (0x2F, 0x7A, 0x4C)
WHITE = (0xFB, 0xF8, 0xF0)
PINK = (0xE9, 0xA4, 0xB6)
PURPLE = (0x6A, 0x4C, 0x93)
INDIGO = (0x2F, 0x5A, 0x8C)
PALETTE = [
    K, PAPER, RED, GOLD, GREEN, WHITE, PINK, PURPLE, INDIGO,
    mix(RED, K, 0.35), mix(GOLD, K, 0.35), mix(GREEN, K, 0.4), mix(PINK, K, 0.3), mix(PAPER, K, 0.25),
]
SIZES = (40, 56)      # ドット幅。高さは 1.5 倍（40 = 札幅 50pt で 1 ドット ≈ 1.25pt）
OUTLINE_SHARE = 0.5   # マスの中で縁取り色がこの割合以上なら縁取りにする
THICKEN = 0.0         # 縁取りを太らせる量（1 ドットの元絵上の幅に対する割合）。太らせると鶴の首・傘が黒く潰れた


# ------------------------------------------------------------ ドット化
def quantize(rgb, pal):
    P = np.array(pal, dtype=int)
    d = ((rgb.astype(int)[:, :, None, :] - P[None, None, :, :]) ** 2).sum(-1)
    return d.argmin(-1)


def mode_down(idx, tw, th, npal):
    H, W = idx.shape
    out = np.zeros((th, tw), dtype=int)
    for oy in range(th):
        y0, y1 = int(oy * H / th), max(int(oy * H / th) + 1, int((oy + 1) * H / th))
        for ox in range(tw):
            x0, x1 = int(ox * W / tw), max(int(ox * W / tw) + 1, int((ox + 1) * W / tw))
            cell = idx[y0:y1, x0:x1].ravel()
            counts = np.bincount(cell, minlength=npal)
            if counts[0] >= cell.size * OUTLINE_SHARE:
                out[oy, ox] = 0
            else:
                counts[0] = 0
                out[oy, ox] = int(counts.argmax())
    return out


def majority_vote(idx, prot=(0,)):
    H, W = idx.shape
    src = idx.copy()
    for y in range(H):
        for x in range(W):
            c = src[y, x]
            if c in prot:
                continue
            nb = [src[y + dy, x + dx] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
                  if 0 <= x + dx < W and 0 <= y + dy < H]
            if c in nb:
                continue
            op = [v for v in nb if v not in prot]
            if op:
                idx[y, x] = max(set(op), key=op.count)
    return idx


def thicken_outline(idx, r):
    if r < 1:
        return idx
    m = Image.fromarray(np.where(idx == 0, 255, 0).astype(np.uint8), "L").filter(ImageFilter.MaxFilter(2 * int(r) + 1))
    out = idx.copy()
    out[np.array(m) > 0] = 0
    return out


def to_image(idx, pal):
    H, W = idx.shape
    out = np.zeros((H, W, 3), dtype=np.uint8)
    for i, c in enumerate(pal):
        out[idx == i] = c
    return Image.fromarray(out, "RGB")


def pixelize(src_img, w):
    h = int(round(w * ASPECT))
    rgb = np.array(src_img.convert("RGB").filter(ImageFilter.MedianFilter(5)))
    idx = quantize(rgb, PALETTE)
    scale = src_img.size[0] / float(w)       # 1 ドットあたりの元絵の px
    idx = thicken_outline(idx, scale * THICKEN)
    small = mode_down(idx, w, h, len(PALETTE))
    small = majority_vote(small)
    return to_image(small, PALETTE)


# ------------------------------------------------------------ アプリ風の枠
def font(size):
    for p in ("/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc", "/System/Library/Fonts/Hiragino Sans GB.ttc"):
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except Exception:
                pass
    return ImageFont.load_default()


def framed(art, width, month, nearest=False):
    """`HanafudaCardFace` と同じ構成（上端 15% の帯・角丸・薄い枠線）で札の見た目に組む。
    art は札全体（帯の下に入る図案）の画像。帯は上に重ねる（アプリも図案の上に帯を敷く）。"""
    height = int(round(width * ASPECT))
    resample = Image.NEAREST if nearest else Image.LANCZOS
    card = art.convert("RGB").resize((width, height), resample)
    d = ImageDraw.Draw(card)
    band_h = int(round(height * BAND_RATIO))
    d.rectangle((0, 0, width, band_h - 1), fill=BAND_HIKARI)
    f = font(max(8, int(min(width * 0.21, band_h * 0.82))))
    inset = int(width * 0.07)
    text_at(d, str(month), inset, band_h / 2, f, "l")
    text_at(d, "光", width - inset, band_h / 2, f, "r")
    # 角丸で切り抜き、枠線（anaconda の古い Pillow には rounded_rectangle が無いので自前で描く）
    r = int(width * CORNER_RATIO)
    mask = rounded_mask(width, height, r)
    out = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    out.paste(card, (0, 0), mask)
    inner = rounded_mask(width - 2, height - 2, max(1, r - 1))
    ring = Image.new("L", (width, height), 0)
    ring.paste(mask, (0, 0))
    ring.paste(0, (1, 1), inner)
    out.paste(Image.new("RGBA", (width, height), INK + (90,)), (0, 0), ring)
    return out


def text_at(d, s, x, y, f, align):
    """左端 / 右端を x、縦の中心を y に置く（anaconda の Pillow 7.2 には anchor が無い）。"""
    w, h = d.textsize(s, font=f)
    ox, oy = f.getoffset(s)
    x0 = x if align == "l" else x - w
    d.text((x0, y - (h + oy) / 2), s, fill=INK, font=f)


def rounded_mask(w, h, r):
    m = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(m)
    d.rectangle((r, 0, w - 1 - r, h - 1), fill=255)
    d.rectangle((0, r, w - 1, h - 1 - r), fill=255)
    for cx, cy in ((0, 0), (w - 1 - 2 * r, 0), (0, h - 1 - 2 * r), (w - 1 - 2 * r, h - 1 - 2 * r)):
        d.ellipse((cx, cy, cx + 2 * r, cy + 2 * r), fill=255)
    return m


def unframed_current(name, w):
    """現行の書き出しは帯・角丸込みなのでそのまま使う。"""
    return Image.open(f"{HERE}/current/{name}_w{w}.png").convert("RGBA")


# ------------------------------------------------------------ 比較図
def sheet(title, rows, big_w, small_w, out_name):
    """rows: [(行ラベル, [札画像(RGBA) ×4 大], [札画像 ×4 実寸])]"""
    f_title, f_label, f_small = font(30), font(22), font(16)
    margin, lab_w, gap = 32, 330, 16
    big_h = int(round(big_w * ASPECT))
    small_h = int(round(small_w * ASPECT))
    row_h = big_h + 40
    W = margin * 2 + lab_w + 4 * (big_w + gap) + 40 + 4 * (small_w + 8)
    H = 90 + row_h * len(rows) + 24
    canvas = Image.new("RGBA", (W, H), PAPER_BG + (255,))
    d = ImageDraw.Draw(canvas)
    d.text((margin, 24), title, fill=(74, 59, 51), font=f_title)
    xs = margin + lab_w
    x_small0 = xs + 4 * (big_w + gap) + 40
    for i, (_, name_ja, _) in enumerate(CARDS):
        d.text((xs + i * (big_w + gap), 70), name_ja, fill=(154, 138, 128), font=f_small)
    d.text((x_small0, 70), f"アプリの実寸相当（幅 {small_w // 3}pt・3x）", fill=(154, 138, 128), font=f_small)
    y = 90
    for label_ja, bigs, smalls in rows:
        lw, lh = d.multiline_textsize(label_ja, font=f_label)
        d.multiline_text((margin, y + (big_h - lh) / 2), label_ja, fill=(74, 59, 51), font=f_label)
        for i, im in enumerate(bigs):
            canvas.alpha_composite(im, (xs + i * (big_w + gap), y + 10))
        for i, im in enumerate(smalls):
            canvas.alpha_composite(im, (x_small0 + i * (small_w + 8), y + 10 + (big_h - small_h) // 2))
        y += row_h
    canvas.convert("RGB").save(f"{HERE}/{out_name}")
    print(out_name, canvas.size)


def main():
    BIG, SMALL = 300, 150   # SMALL = 50pt × 3x（iPhone の場で 6 列に並んだときの札幅）
    srcs = {n: Image.open(f"{HERE}/src/{n}.png") for n, _, _ in CARDS}
    px = {}
    for w in SIZES:
        os.makedirs(f"{HERE}/px{w}", exist_ok=True)
        for n, _, _ in CARDS:
            img = pixelize(srcs[n], w)
            img.save(f"{HERE}/px{w}/{n}.png")
            px[(w, n)] = img
            print(f"px{w}/{n}.png {img.size} {len(img.getcolors(256))} 色")

    row1 = ("案① 線画ベタ塗り\n（Codex の生成物をそのまま）",
            [framed(srcs[n], BIG, m) for n, _, m in CARDS],
            [framed(srcs[n], SMALL, m) for n, _, m in CARDS])
    rows_px = []
    for w in SIZES:
        rows_px.append((f"案② ドット化 {w}×{int(w * ASPECT)}",
                        [framed(px[(w, n)], BIG, m, nearest=True) for n, _, m in CARDS],
                        [framed(px[(w, n)], SMALL, m, nearest=True) for n, _, m in CARDS]))
    sheet("花札 光札 4 枚の描き直し案（#2188）: 案① 線画ベタ塗り / 案② ドット化",
          [row1] + rows_px, BIG, SMALL, "compare_new.png")

    row0 = ("現行\n（Canvas 描画・v1.1.12）",
            [unframed_current(n, 400).resize((BIG, int(BIG * ASPECT)), Image.LANCZOS) for n, _, _ in CARDS],
            [unframed_current(n, 50) for n, _, _ in CARDS])
    sheet("花札 光札 4 枚: 現行との比較（#2188）", [row0, row1, rows_px[0]], BIG, SMALL, "compare_current.png")


if __name__ == "__main__":
    main()
