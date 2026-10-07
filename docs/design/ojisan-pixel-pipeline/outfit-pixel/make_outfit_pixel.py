#!/usr/bin/env python3
"""Codex が描いた衣装別 2D 絵（codex-outfits/）を 48 / 64 ドットのドット絵に落とす。

実行: env -u NODE_OPTIONS /Users/yamadahiroki/opt/anaconda3/bin/python3 make_outfit_pixel.py
依存: Pillow + numpy（anaconda の scipy は numpy と不整合なので使わない。連結成分は pxlib.py の BFS）

手順（pixel-mock-puzzle/make_puzzle_pixel_mock.py の手法を流用）
 1. 白背景を枠からの塗りつぶしで透過にする。連結成分のうち
    - 最大のもの（本体）と、本体の近くにある記号（汗・涙・痛みマーク・転がる段ボール）は残す
    - 下端に接している塊（切り出しが甘くて写り込んだ隣のコマの頭）は落とす
    - 細長い塊（効果線）は落とす
 2. 5×5 のメディアンで画像生成のざらつきを均し、衣装ごとの固定パレット（20 色以内）に減色
 3. 立ち絵（前）の不透明部分の高さが 48（64）ドットになる共通の縮尺で最頻色縮小
    （平均すると線が灰色に溶けるので、マスの中で一番多い色を採る。縁取り色は一定の割合以上で優先）
 4. 孤立ドット除去 → 孤立 1 ドットの多数決（特徴色は触らない）→ 輪郭を 1 ドットの縁取り色でそろえる
 5. FIXUPS に書いた手直し（顔のドット単位の修正。場所と理由を記録）
 6. px48/ px64/ に各コマ PNG、sheet_px.png に比較一覧を出力
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

from pxlib import label, flood_bg, comp_info

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "codex-outfits")
OUT = HERE
SIZES = (48, 64)
MEDIAN = 5
OUTLINE_SHARE = 0.38

# ---------------------------------------------------------------- コマ
FRAMES = {
    "a_work": [
        ("front_neutral", "前・真顔"),
        ("right_neutral", "画面右向き・真顔"),
        ("left_neutral", "画面左向き・真顔"),
        ("back_neutral", "後ろ"),
        ("carry_light_smile", "軽い荷物・笑顔"),
        ("carry_heavy_pain_sweat", "重い荷物・痛い"),
        ("limit_back_pain", "限界・腰を押さえる"),
        ("fallen_face_down_crying", "倒れる・泣いてる"),
    ],
    "b_kimono": [
        ("front_neutral", "前・真顔"),
        ("right_neutral", "画面右向き・真顔"),
        ("left_neutral", "画面左向き・真顔"),
        ("back_neutral", "後ろ"),
        ("bonsai_smile", "盆栽を眺める・笑顔"),
        ("prune_right_neutral", "剪定・画面右向き"),
        ("celebrate_front_smile", "大喜び・笑顔"),
        ("disappointed_front_crying", "がっかり・泣いてる"),
    ],
}
OUTFIT_LABELS = {"a_work": "作業服（腰痛おじさんパズル）", "b_kimono": "和の着物（盆栽の合体パズル）"}

# ---------------------------------------------------------------- パレット（衣装ごとに固定・20 色以内）
OUTLINE = (0x26, 0x22, 0x2C)  # 縁取り・目。現行 OjisanPixel の K (0x2B2634) より少し黒寄り
                              # （瞳の黒 (30,30,30) が羽織の陰 g に吸われないようにするため）
COMMON = {
    "K": OUTLINE,
    "S": (0xF6, 0xC8, 0x8C),   # 肌（元絵は黄みの肌）
    "s": (0xE4, 0xA2, 0x6A),   # 肌の陰
    "d": (0xC0, 0x7C, 0x4E),   # 耳の内側・鼻の下の濃い陰
    "C": (0xF4, 0xAA, 0x96),   # 頬
    "W": (0xFA, 0xFA, 0xFA),   # 白（目・歯・タオル・軍手・足袋）
    "H": (0xC4, 0xC4, 0xCA),   # 髪・ひげ
    "h": (0x92, 0x92, 0x9C),   # 髪の陰
    "b": (0x5E, 0x5E, 0x68),   # 眉・ひげの陰
    "R": (0xC8, 0x3C, 0x48),   # 口（舌）
    "m": (0x5E, 0x14, 0x18),   # 口の中
    "a": (0x6E, 0xB9, 0xEB),   # 汗・涙
}
PALETTES = {
    "a_work": dict(COMMON, **{
        "I": (0xD2, 0xD2, 0xD8),   # タオル・軍手の陰
        "U": (0x46, 0x48, 0x5C),   # 作業着（紺）
        "u": (0x30, 0x32, 0x42),   # 作業着の陰
        "g": (0x5A, 0x5A, 0x60),   # 安全靴の照り
        "N": (0xD6, 0xAC, 0x70),   # 段ボール（明）
        "n": (0xB2, 0x86, 0x52),   # 段ボール（中）
        "X": (0x82, 0x5C, 0x34),   # 段ボール（暗）
        "F": (0xE2, 0x3E, 0x32),   # 痛みマーク（赤い稲妻）
    }),
    "b_kimono": dict(COMMON, **{
        "G": (0x36, 0x4E, 0x42),   # 羽織（深緑）
        "g": (0x22, 0x34, 0x2C),   # 羽織の陰
        "B": (0x2A, 0x3E, 0x5C),   # 着物（藍）
        "v": (0x1A, 0x2A, 0x42),   # 着物の陰
        "O": (0xB4, 0xA8, 0x96),   # 帯
        "L": (0x46, 0x8C, 0x3C),   # 盆栽の葉
        "l": (0x28, 0x60, 0x28),   # 盆栽の葉の陰
        "P": (0x76, 0x48, 0x2C),   # 鉢・幹・草履
    }),
}
# 多数決・縁取り補正で触らない特徴色
PROTECTED = ("K", "R", "m", "b", "a", "F")

# コマごとに使える色を絞る（耳の赤みが口の赤に、タオルの照りが段ボール色に化けるのを防ぐ）。
# 記号 -> 使ってよいコマ。書いていない記号は全コマで使える。
NEUTRAL = {"front_neutral", "right_neutral", "left_neutral", "back_neutral"}
ALLOW = {
    "a_work": {
        "F": {"limit_back_pain"},
        "N": {"carry_light_smile", "carry_heavy_pain_sweat", "fallen_face_down_crying"},
        "n": {"carry_light_smile", "carry_heavy_pain_sweat", "fallen_face_down_crying"},
        "X": {"carry_light_smile", "carry_heavy_pain_sweat", "fallen_face_down_crying"},
        "a": {"carry_heavy_pain_sweat", "limit_back_pain", "fallen_face_down_crying"},
        "R": {"carry_light_smile", "carry_heavy_pain_sweat", "limit_back_pain", "fallen_face_down_crying"},
        "m": {"carry_light_smile", "carry_heavy_pain_sweat", "limit_back_pain", "fallen_face_down_crying"},
    },
    "b_kimono": {
        "L": {"bonsai_smile", "prune_right_neutral"},
        "l": {"bonsai_smile", "prune_right_neutral"},
        "a": {"disappointed_front_crying"},
        "R": {"bonsai_smile", "celebrate_front_smile", "disappointed_front_crying"},
        "m": {"bonsai_smile", "celebrate_front_smile", "disappointed_front_crying"},
    },
}
# 本体の上から この割合 より下でだけ使える色（帯の色が髪の照りに化けるのを防ぐ）
BELOW = {"b_kimono": {"O": 0.45}}


# ---------------------------------------------------------------- 1. 背景抜き
def key_out(rgb):
    """白背景を透明にし、本体 + 近接記号だけ残す。戻り値: (RGBA 配列, 残した/全成分数, 落とした理由)"""
    H, W, _ = rgb.shape
    is_bg = (rgb[:, :, 0] >= 230) & (rgb[:, :, 1] >= 230) & (rgb[:, :, 2] >= 230)
    bg = flood_bg(is_bg)
    lab, n = label(~bg)
    infos = comp_info(lab, n)
    keep = np.zeros((H, W), dtype=bool)
    dropped = []
    main = infos[0]
    for i, d in enumerate(infos):
        w, h = d["x1"] - d["x0"] + 1, d["y1"] - d["y0"] + 1
        fill = d["size"] / float(w * h)
        if i == 0:
            keep |= lab == d["id"]
            continue
        if d["y1"] >= H - 1:
            dropped.append(f"下端に接する塊 {w}x{h}（隣のコマの頭）")
            continue
        if d["size"] < 40:
            dropped.append(f"小さな塊 {w}x{h}")
            continue
        if fill < 0.2:
            dropped.append(f"細長い塊 {w}x{h} fill={fill:.2f}（効果線）")
            continue
        m = lab == d["id"]
        keep |= m
        r, g, b = rgb[m].mean(0)
        if b > r + 40:                       # 汗・涙 → 水色で塗りつぶす（白い照りと暗い縁が灰色に化けるのを防ぐ）
            rgb = rgb.copy(); rgb[m] = COMMON["a"]
        elif r > g + 80 and r > b + 80:      # 痛みマーク → 赤
            rgb = rgb.copy(); rgb[m] = PALETTES["a_work"]["F"]
    rgba = np.dstack([rgb, np.where(keep, 255, 0).astype(np.uint8)]).astype(np.uint8)
    return rgba, n, dropped


# ---------------------------------------------------------------- 2. 減色
def median_rgb(rgba, size=MEDIAN):
    im = Image.fromarray(rgba[:, :, :3], "RGB").filter(ImageFilter.MedianFilter(size))
    out = rgba.copy()
    out[:, :, :3] = np.array(im)
    return out


def quantize(rgba, pal, disallow=(), below=()):
    """各画素をパレットの最も近い色の番号に（透明は -1）。
    disallow: このコマで使わない色の番号。below: [(番号, y しきい値)] その行より上では使わない色。"""
    P = np.array(pal, dtype=int)
    rgb = rgba[:, :, :3].astype(int)
    d = ((rgb[:, :, None, :] - P[None, None, :, :]) ** 2).sum(-1)
    for i in disallow:
        d[:, :, i] = 10 ** 9
    for i, ythr in below:
        d[:ythr, :, i] = 10 ** 9
    idx = d.argmin(-1)
    idx[rgba[:, :, 3] == 0] = -1
    return idx


# ---------------------------------------------------------------- 3. 最頻色縮小
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


# ---------------------------------------------------------------- 4. 掃除
def drop_specks(idx, min_size=2):
    lab, n = label(idx >= 0)
    for d in comp_info(lab, n):
        if d["size"] < min_size:
            idx[lab == d["id"]] = -1
    return idx


def majority_vote(idx, prot):
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


def ensure_outline(idx, prot, min_comp=30):
    """透明に接している不透明ドットを縁取り色にする（本体など大きな塊だけ。汗粒は潰れるので対象外）。"""
    H, W = idx.shape
    lab, n = label(idx >= 0)
    big = {d["id"] for d in comp_info(lab, n) if d["size"] >= min_comp}
    src = idx.copy()
    for y in range(H):
        for x in range(W):
            c = src[y, x]
            if c <= 0 or c in prot or lab[y, x] not in big:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if not (0 <= nx < W and 0 <= ny < H) or src[ny, nx] < 0:
                    idx[y, x] = 0
                    break
    return idx


# ---------------------------------------------------------------- 5. 手直し（ドット単位。x, y は切り出し後の左上基準）
# (衣装, コマ, サイズ) -> [(x, y, パレット記号 or None=透明), ...]
def _row(y, xs, k):
    return [(x, y, k) for x in xs]


FIXUPS = {
    # 48 の正面顔: 眉が髪の陰 h と眉 b に割れて薄い → 目の真上に 4 ドットの眉（b）を引き直し、周りの灰色を肌に戻す
    ("a_work", "front_neutral", 48):
        _row(7, range(8, 12), "b") + _row(7, range(17, 21), "b") + [(21, 7, "S")]
        + _row(6, range(9, 12), "S") + _row(6, range(18, 21), "S") + [(7, 8, "S"), (8, 8, "S"), (21, 8, "S")]
        # タオルの縁に残った眉色 b の点を縁取りに（左上 2 点・結び目 2 点）
        + [(6, 2, None), (5, 3, "K"), (26, 4, "K"), (28, 12, "W")],
    ("b_kimono", "front_neutral", 48):
        _row(6, range(8, 12), "b") + _row(6, range(18, 22), "b")
        + _row(5, range(9, 12), "S") + _row(5, range(17, 21), "S") + [(10, 4, "S"), (19, 4, "S"), (6, 4, "K"), (3, 11, "h")]
        # 真顔の口が消えていた → ひげの下に 4 ドットの口（d）
        + _row(18, range(13, 17), "d"),
}


def apply_fixups(idx, keys, outfit, name, size):
    for x, y, k in FIXUPS.get((outfit, name, size), []):
        idx[y, x] = -1 if k is None else keys.index(k)
    return idx


# ---------------------------------------------------------------- 出力
def to_image(idx, pal):
    H, W = idx.shape
    out = np.zeros((H, W, 4), dtype=np.uint8)
    for i, c in enumerate(pal):
        out[idx == i] = c + (255,)
    return Image.fromarray(out, "RGBA")


def crop_idx(idx):
    ys, xs = np.nonzero(idx >= 0)
    return idx[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def nn(img, k):
    return img.resize((img.size[0] * k, img.size[1] * k), Image.NEAREST)


def font(size):
    for p in ("/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc",
              "/System/Library/Fonts/Hiragino Sans GB.ttc",
              "/System/Library/Fonts/Supplemental/Arial Unicode.ttf"):
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except Exception:
                pass
    return ImageFont.load_default()


def process_outfit(outfit):
    pal_map = PALETTES[outfit]
    keys = list(pal_map.keys())
    pal = [pal_map[k] for k in keys]
    prot = {keys.index(k) for k in PROTECTED if k in keys}
    assert keys[0] == "K"
    assert len(pal) <= 20, len(pal)

    keyed = {}
    for name, _ in FRAMES[outfit]:
        rgb = np.array(Image.open(f"{SRC}/{outfit}/{name}.png").convert("RGB"))
        rgba, _, dropped = key_out(rgb)
        keyed[name] = rgba
        ys = np.nonzero(rgba[:, :, 3])[0]
        print(f"  {outfit}/{name}: 本体の高さ {ys.max() - ys.min() + 1}px" + (f"  落とした: {dropped}" if dropped else ""))

    # 共通の縮尺: 立ち絵（前）の高さ → 48 / 64 ドット
    ys = np.nonzero(keyed["front_neutral"][:, :, 3])[0]
    ref_h = ys.max() - ys.min() + 1
    results = {}
    def limits(name):
        dis = [keys.index(k) for k, frames in ALLOW.get(outfit, {}).items() if name not in frames]
        ys = np.nonzero(keyed[name][:, :, 3])[0]
        bel = [(keys.index(k), int(ys.min() + (ys.max() - ys.min()) * f)) for k, f in BELOW.get(outfit, {}).items()]
        return dis, bel

    for size in SIZES:
        scale = size / float(ref_h)
        for _ in range(3):                   # 丸めで 1 ドットずれることがあるので、基準コマの高さが合うまで補正
            got = crop_idx(ensure_outline(majority_vote(drop_specks(mode_down(quantize(median_rgb(keyed["front_neutral"]), pal, *limits("front_neutral")), scale, len(pal))), prot), prot)).shape[0]
            if got == size:
                break
            scale *= size / float(got)
        print(f"  {outfit} px{size}: scale {scale:.4f} (1 dot = {1/scale:.2f} px)")
        os.makedirs(f"{OUT}/px{size}", exist_ok=True)
        for name, _ in FRAMES[outfit]:
            idx = quantize(median_rgb(keyed[name]), pal, *limits(name))
            small = mode_down(idx, scale, len(pal))
            small = drop_specks(small)
            small = majority_vote(small, prot)
            small = ensure_outline(small, prot)
            small = crop_idx(small)
            small = apply_fixups(small, keys, outfit, name, size)
            img = to_image(small, pal)
            img.save(f"{OUT}/px{size}/{outfit}_{name}.png")
            results[(size, name)] = img
    return keyed, results


def make_sheet(all_keyed, all_results):
    f_title, f_label, f_small = font(30), font(22), font(16)
    DISP = 192                 # 表示の高さ（元絵は LANCZOS 縮小、48 は ×4、64 は ×3）
    margin, gap = 40, 24
    col_w = 240
    bg = (0xFF, 0xF6, 0xEC)
    blocks = []
    for outfit in FRAMES:
        keyed, results = all_keyed[outfit], all_results[outfit]
        rows = []
        for name, label_ja in FRAMES[outfit]:
            rgba = keyed[name]
            ys, xs = np.nonzero(rgba[:, :, 3])
            src = Image.fromarray(rgba, "RGBA").crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
            rows.append((label_ja, src, results[(48, name)], results[(64, name)]))
        blocks.append((outfit, rows))
    row_h = 36 + DISP + 16
    W = margin * 2 + col_w * 3 + 200
    H = 80 + sum(56 + row_h * len(rows) for _, rows in blocks) + 40
    canvas = Image.new("RGBA", (W, H), bg + (255,))
    d = ImageDraw.Draw(canvas)
    d.text((margin, 22), "衣装別おじさん ドット絵化（左: Codex の 2D 元絵 / 中: 48 ドット ×4 / 右: 64 ドット ×3）  2026-10-07", fill=(74, 59, 51), font=f_title)
    y = 80
    for outfit, rows in blocks:
        d.text((margin, y), OUTFIT_LABELS[outfit], fill=(74, 59, 51), font=f_label)
        y += 56
        for label_ja, src, p48, p64 in rows:
            d.text((margin, y + DISP // 2 - 12), label_ja, fill=(74, 59, 51), font=f_small)
            x = margin + 200
            # 元絵
            h = DISP
            w = max(1, round(src.size[0] * h / float(src.size[1])))
            if w > col_w - 16:
                w = col_w - 16
                h = round(src.size[1] * w / float(src.size[0]))
            s = src.resize((w, h), Image.LANCZOS)
            canvas.alpha_composite(s, (x + (col_w - w) // 2, y + 36 + DISP - h))
            x += col_w
            for img, k in ((p48, 4), (p64, 3)):
                big = nn(img, k)
                bw, bh = big.size
                if bw > col_w - 16:
                    big = nn(img, max(1, (col_w - 16) // img.size[0]))
                    bw, bh = big.size
                canvas.alpha_composite(big, (x + (col_w - bw) // 2, y + 36 + DISP - bh))
                d.text((x + 8, y + 12), f"{img.size[0]}×{img.size[1]} ドット", fill=(154, 138, 128), font=f_small)
                x += col_w
            y += row_h
    canvas.convert("RGB").save(f"{OUT}/sheet_px.png")
    print("sheet_px.png", canvas.size)


def main():
    all_keyed, all_results = {}, {}
    for outfit in FRAMES:
        print(outfit)
        all_keyed[outfit], all_results[outfit] = process_outfit(outfit)
    make_sheet(all_keyed, all_results)


if __name__ == "__main__":
    main()
