#!/usr/bin/env python3
"""花札 48 枚の原画（Codex 製・1024×1536）から、アプリ同梱用の画像と一覧シートを作る（#2188）。

入力:
  cards48/src/NN_*.png   Codex（画像生成）が prompts/mNN.txt の文章だけで描いた原画（NN = HanafudaCard.id）
出力:
  ../../../Packages/GameKit/Sources/GameHanafuda/Resources/Cards/Hanafuda_NN.png
                         アプリ同梱用。320×480・256 色のパレット PNG（札は画面で幅 40〜130pt なので 3x でも足りる）
  cards48/sheet48.png    48 枚の一覧（アプリの帯・角丸を模した枠付き。大きく見た図＋実寸相当 50pt 幅の 3x）
  cards48/sheet48_raw.png 原画そのものの一覧（上端の空きと月内の統一の確認用）

後処理は 2 つだけ（新規の絵は描いていない）:
  1. 上端の空きを詰める: 指示で「上端 20% は何も描かない」としたぶん図案が下に寄るので、図案の上端
     （和紙色でない最初の行）が札の 18% の高さに来るまで上を切り、縦横比を保つため左右も同じ比率で切って
     元の大きさへ戻す（切るのは最大で高さの 18%・左右各 6%）。図案が 18% より上にある札はそのまま。
  2. 縮小と減色: LANCZOS で 320×480 に縮め、256 色に減色して PNG で保存。

実行（Pillow + numpy。anaconda の python3）:
  /Users/yamadahiroki/opt/anaconda3/bin/python3 make_cards.py
"""
import glob
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = f"{HERE}/cards48/src"
OUT_APP = os.path.normpath(f"{HERE}/../../../Packages/GameKit/Sources/GameHanafuda/Resources/Cards")
ASPECT = 1.5          # HanafudaCardArt.aspectRatio
BAND_RATIO = 0.15     # HanafudaCardFace.bandRatio
CORNER_RATIO = 0.12
APP_W, APP_H = 320, 480
TOP_TARGET = 0.18     # 図案の上端をここまで引き上げる
TOP_MAX_CROP = 0.18   # 上を切る量の上限（高さに対する割合。左右は各 6% まで）
PAPER = (0xF2, 0xE6, 0xC9)
PAPER_TOL = 40        # 和紙色とみなす許容差（チャンネルごと）
INK = (0x3A, 0x2E, 0x27)
PAPER_BG = (0xFF, 0xF6, 0xEC)

# HanafudaCardArt.kindHex / HanafudaCard.table と同じ。帯の色と表記（日本語）。
HIKARI, TANE, AKA, AO, KASU = (0xD4, 0xA9, 0x3A), (0x2F, 0x70, 0x50), (0xC6, 0x3A, 0x3A), (0x3E, 0x6F, 0xB0), (0x6F, 0x67, 0x5E)
KINDS = {
    0: HIKARI, 1: AKA, 2: KASU, 3: KASU, 4: TANE, 5: AKA, 6: KASU, 7: KASU,
    8: HIKARI, 9: AKA, 10: KASU, 11: KASU, 12: TANE, 13: AKA, 14: KASU, 15: KASU,
    16: TANE, 17: AKA, 18: KASU, 19: KASU, 20: TANE, 21: AO, 22: KASU, 23: KASU,
    24: TANE, 25: AKA, 26: KASU, 27: KASU, 28: HIKARI, 29: TANE, 30: KASU, 31: KASU,
    32: TANE, 33: AO, 34: KASU, 35: KASU, 36: TANE, 37: AO, 38: KASU, 39: KASU,
    40: HIKARI, 41: TANE, 42: AKA, 43: KASU, 44: HIKARI, 45: KASU, 46: KASU, 47: KASU,
}
LABELS = {HIKARI: "光", TANE: "タネ", AKA: "短", AO: "短", KASU: "カス"}
NAMES = [
    "松に鶴", "松に赤短", "松のカス", "松のカス", "梅に鶯", "梅に赤短", "梅のカス", "梅のカス",
    "桜に幕", "桜に赤短", "桜のカス", "桜のカス", "藤に不如帰", "藤に短冊", "藤のカス", "藤のカス",
    "菖蒲に八橋", "菖蒲に短冊", "菖蒲のカス", "菖蒲のカス", "牡丹に蝶", "牡丹に青短", "牡丹のカス", "牡丹のカス",
    "萩に猪", "萩に短冊", "萩のカス", "萩のカス", "芒に月", "芒に雁", "芒のカス", "芒のカス",
    "菊に盃", "菊に青短", "菊のカス", "菊のカス", "紅葉に鹿", "紅葉に青短", "紅葉のカス", "紅葉のカス",
    "柳に小野道風", "柳に燕", "柳に短冊", "柳に鬼札", "桐に鳳凰", "桐のカス", "桐のカス", "桐のカス",
]


def sources():
    out = {}
    for p in sorted(glob.glob(f"{SRC}/*.png")):
        n = int(os.path.basename(p)[:2])
        out[n] = p
    missing = [i for i in range(48) if i not in out]
    assert not missing, f"原画が無い: {missing}"
    return out


def art_top(img):
    """図案の上端（和紙色でない画素が行の 1% を超える最初の行）。"""
    a = np.array(img.convert("RGB")).astype(int)
    non_paper = (np.abs(a - np.array(PAPER)) > PAPER_TOL).any(-1)
    rows = non_paper.mean(1)
    hit = np.nonzero(rows > 0.01)[0]
    return int(hit[0]) if len(hit) else img.size[1]


def tighten_top(img):
    """上端の空きを詰める（docstring の後処理 1）。戻り値は (画像, 切った高さ px)。"""
    W, H = img.size
    top = art_top(img)
    target = int(H * TOP_TARGET)
    if top <= target:
        return img, 0
    crop_h = min(top - target, int(H * TOP_MAX_CROP))
    # 縦横比を保つ: 高さを H - crop_h にするので、幅も同じ比率で左右を均等に切る。
    new_h = H - crop_h
    new_w = int(round(new_h / ASPECT))
    x0 = (W - new_w) // 2
    out = img.crop((x0, crop_h, x0 + new_w, crop_h + new_h)).resize((W, H), Image.LANCZOS)
    return out, crop_h


def to_app(img):
    small = img.convert("RGB").resize((APP_W, APP_H), Image.LANCZOS)
    # 生成画像の地にはわずかな濃淡があり、MEDIANCUT だと小さな金の花芯が潰れるうえ PNG が 100KB 前後になる。
    # FASTOCTREE なら見た目は原画と変わらず半分以下に縮む。
    return small.quantize(colors=256, method=Image.FASTOCTREE, dither=Image.NONE)


# ------------------------------------------------------------ アプリ風の枠（make_mock.py と同じ）
def font(size):
    for p in ("/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc", "/System/Library/Fonts/Hiragino Sans GB.ttc"):
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except Exception:
                pass
    return ImageFont.load_default()


def text_at(d, s, x, y, f, align, fill):
    w, h = d.textsize(s, font=f)
    ox, oy = f.getoffset(s)
    x0 = x if align == "l" else x - w
    d.text((x0, y - (h + oy) / 2), s, fill=fill, font=f)


def rounded_mask(w, h, r):
    m = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(m)
    d.rectangle((r, 0, w - 1 - r, h - 1), fill=255)
    d.rectangle((0, r, w - 1, h - 1 - r), fill=255)
    for cx, cy in ((0, 0), (w - 1 - 2 * r, 0), (0, h - 1 - 2 * r), (w - 1 - 2 * r, h - 1 - 2 * r)):
        d.ellipse((cx, cy, cx + 2 * r, cy + 2 * r), fill=255)
    return m


def framed(art, width, card_id):
    """`HanafudaCardFace` と同じ構成（上端 15% の帯・角丸・薄い枠線）で札の見た目に組む。"""
    height = int(round(width * ASPECT))
    card = art.convert("RGB").resize((width, height), Image.LANCZOS)
    d = ImageDraw.Draw(card)
    band_h = int(round(height * BAND_RATIO))
    kind = KINDS[card_id]
    d.rectangle((0, 0, width, band_h - 1), fill=kind)
    label = (255, 255, 255) if kind in (TANE, AKA, AO, KASU) else INK
    f = font(max(8, int(min(width * 0.21, band_h * 0.82))))
    inset = int(width * 0.07)
    text_at(d, str(card_id // 4 + 1), inset, band_h / 2, f, "l", label)
    text_at(d, LABELS[kind], width - inset, band_h / 2, f, "r", label)
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


def sheet(title, images, big_w, small_w, out_path, framed_fn):
    """12 行（月）× 4 列。各行の右に実寸相当（50pt 幅の 3x）を並べる。"""
    f_title, f_label, f_small = font(30), font(20), font(15)
    margin, lab_w, gap = 32, 120, 14
    big_h = int(round(big_w * ASPECT))
    small_h = int(round(small_w * ASPECT))
    row_h = big_h + 36
    W = margin * 2 + lab_w + 4 * (big_w + gap) + 30 + 4 * (small_w + 6)
    H = 80 + row_h * 12 + 20
    canvas = Image.new("RGBA", (W, H), PAPER_BG + (255,))
    d = ImageDraw.Draw(canvas)
    d.text((margin, 22), title, fill=(74, 59, 51), font=f_title)
    xs = margin + lab_w
    x_small0 = xs + 4 * (big_w + gap) + 30
    d.text((x_small0, 56), f"アプリの実寸相当（幅 {small_w // 3}pt・3x）", fill=(154, 138, 128), font=f_small)
    y = 80
    for month in range(1, 13):
        d.text((margin, y + big_h // 2 - 12), f"{month} 月", fill=(74, 59, 51), font=f_label)
        for i in range(4):
            cid = (month - 1) * 4 + i
            big = framed_fn(images[cid], big_w, cid)
            small = framed_fn(images[cid], small_w, cid)
            x = xs + i * (big_w + gap)
            canvas.alpha_composite(big, (x, y + 2))
            d.text((x, y + big_h + 6), f"{cid:02d} {NAMES[cid]}", fill=(154, 138, 128), font=f_small)
            canvas.alpha_composite(small, (x_small0 + i * (small_w + 6), y + 2 + (big_h - small_h) // 2))
        y += row_h
    canvas.convert("RGB").save(out_path)
    print(out_path, canvas.size)


def plain(art, width, card_id):
    height = int(round(width * ASPECT))
    return art.convert("RGBA").resize((width, height), Image.LANCZOS)


def main():
    os.makedirs(OUT_APP, exist_ok=True)
    srcs = sources()
    raw, tight, app = {}, {}, {}
    total = 0
    for cid in range(48):
        img = Image.open(srcs[cid]).convert("RGB")
        assert img.size == (1024, 1536), f"{srcs[cid]} の大きさが {img.size}"
        raw[cid] = img
        t, crop = tighten_top(img)
        tight[cid] = t
        a = to_app(t)
        path = f"{OUT_APP}/Hanafuda_{cid:02d}.png"
        a.save(path, optimize=True)
        size = os.path.getsize(path)
        total += size
        app[cid] = a
        top_after = art_top(t)
        print(f"{cid:02d} {NAMES[cid]:8s} 図案の上端 {art_top(img) / 15.36:5.1f}% → {top_after / 15.36:5.1f}%  上を切った量 {crop:3d}px  {size // 1024:3d} KB")
    print(f"アプリ同梱 48 枚の合計 {total / 1024:.0f} KB")
    sheet("花札 48 枚（#2188）: アプリ同梱の画像を札の見た目に組んだもの", app, 180, 150, f"{HERE}/cards48/sheet48.png", framed)
    sheet("花札 48 枚（#2188）: 原画（後処理前）", raw, 180, 150, f"{HERE}/cards48/sheet48_raw.png", plain)


if __name__ == "__main__":
    main()
