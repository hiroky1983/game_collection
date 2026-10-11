# -*- coding: utf-8 -*-
"""#2064 v2: Codex 製 source.png からベッド 3 枚と顔 3 種を切り出し、ゲームのパレットに寄せてドット化する。
実行: env -u NODE_OPTIONS /Users/yamadahiroki/opt/anaconda3/bin/python3 make_v2_px.py
手法は docs/design/ojisan-pixel-pipeline/outfit-pixel/make_outfit_pixel.py の流用（絵は描き直さない）。
"""
import os, sys
import numpy as np
from PIL import Image, ImageFilter

REPO = "/Users/yamadahiroki/myspace/game_collection"
sys.path.insert(0, os.path.join(REPO, "docs/design/ojisan-pixel-pipeline/outfit-pixel"))
from pxlib import label, flood_bg, comp_info  # noqa: E402

SP = "/private/tmp/claude-501/-Users-yamadahiroki-myspace-game-collection/792b949b-8dc6-4021-8001-08a2ed00cbe0/scratchpad"
SRC = os.path.join(SP, "codex-pixel", "source.png")
OUT = os.path.join(SP, "ojisan-2064", "v3", "px")
WORK = os.path.join(SP, "ojisan-2064", "v3", "work")
os.makedirs(OUT, exist_ok=True)

MEDIAN = 5
MED_BED = 3
MED_FACE = 3
OUTLINE_SHARE = 0.38

# ---------------------------------------------------------------- パレット（ゲームの OjisanWork_*.png と同じ記号・値）
OUTLINE = (0x26, 0x22, 0x2C)
GAME = {
    "K": OUTLINE,
    "S": (0xF6, 0xC8, 0x8C),   # 肌
    "s": (0xE4, 0xA2, 0x6A),   # 肌の陰
    "d": (0xC0, 0x7C, 0x4E),   # 耳の内側・鼻の下
    "C": (0xF4, 0xAA, 0x96),   # 頬
    "W": (0xFA, 0xFA, 0xFA),   # 白
    "H": (0xC4, 0xC4, 0xCA),   # 髪・ひげ
    "h": (0x92, 0x92, 0x9C),   # 髪の陰
    "b": (0x5E, 0x5E, 0x68),   # 眉・ひげの陰
    "R": (0xC8, 0x3C, 0x48),   # 口（舌）
    "m": (0x5E, 0x14, 0x18),   # 口の中
    "a": (0x6E, 0xB9, 0xEB),   # 汗・涙
    "I": (0xD2, 0xD2, 0xD8),   # 白の陰
    "U": (0x46, 0x48, 0x5C),   # 作業着（紺）
    "u": (0x30, 0x32, 0x42),   # 作業着の陰
    "g": (0x5A, 0x5A, 0x60),   # 安全靴の照り
}
# ベッド用に足す色（4 色）。合計 20 色以内
BED_EXTRA = {
    "L": (0xDA, 0xE6, 0xF4),   # 布団（明）
    "l": (0xB0, 0xC6, 0xE4),   # 布団の陰
    "n": (0x8E, 0xA8, 0xD0),   # 布団の濃い陰・点滴の袋の影
    "p": (0xEE, 0xEE, 0xF2),   # 枕・シーツ（白とほぼ同じだが布団との境を出す）
}
PAL_BED = dict(GAME, **BED_EXTRA)
PAL_FACE = dict(GAME)
# 大笑い（cheer）の口の中は元絵が青みの白（歯ぐき・下唇の照り）なので、布団用の薄青 2 色を口の高さだけ許す
PAL_FACE_CHEER = dict(GAME, L=BED_EXTRA["L"], l=BED_EXTRA["l"])
PROTECTED = ("K", "R", "m", "b", "a")


# ---------------------------------------------------------------- 切り出し位置（source.png、1536×1024）
# (x0, y0, x1, y1), 追加で消す長方形 [(x0,y0,x1,y1)...]（切り出し後の座標ではなく source の座標）
BEDS = {
    # v3: 頭に重なる柵・窓は消さない（会長指示）。消すのは柵の上に突き出た別コマの柱だけ
    "bed_01": dict(box=(362, 826, 592, 1004), erase=[(362, 826, 406, 848)]),
    "bed_02": dict(box=(574, 812, 733, 1004), erase=[(729, 812, 733, 1004)]),                        # 右端は隣のベッドの柵
    # v3: 壁の窓は頭の後ろの柵として残す。左端 745 で切って隣のベッドの柱だけ外す
    "bed_03": dict(box=(745, 824, 935, 1004), erase=[],
                   disallow=("C",)),                                                                 # 頬の赤みが顔全体に広がるので使わない
}
FACES = {
    "smile": dict(box=(934, 848, 1036, 952)),   # 通常（目を開けて笑う）
    "cheer": dict(box=(1030, 848, 1132, 952)),  # 笑顔（目を閉じて大笑い）
    "frown": dict(box=(1218, 848, 1322, 952), erase=[(1298, 848, 1322, 874)]),  # 痛い（しかめ面＋汗）。右上の「!」（隣の驚き顔のもの）を消す
}
FACE_DOTS = (32, 30)


# ---------------------------------------------------------------- 1. 背景抜き
def key_out(rgb, keep_rule):
    H, W, _ = rgb.shape
    is_bg = (rgb[:, :, 0] >= 225) & (rgb[:, :, 1] >= 225) & (rgb[:, :, 2] >= 225)
    # 白い布団のハイライトが細い白の通り道で外とつながって抜けるのを防ぐ:
    # 背景候補を 5×5 で痩せさせてから枠から塗りつぶし、普通の塗りつぶしで届いたのに痩せた版では届かない
    # 「太さのある白い領域」（＝閉じた布団のハイライト）を背景から外す。細い隙間はそのまま背景に残す
    loose = flood_bg(is_bg)
    m = Image.fromarray((is_bg * 255).astype(np.uint8), "L")
    eroded = np.array(m.filter(ImageFilter.MinFilter(5))) > 0
    eroded[:2, :] = is_bg[:2, :]; eroded[-2:, :] = is_bg[-2:, :]
    eroded[:, :2] = is_bg[:, :2]; eroded[:, -2:] = is_bg[:, -2:]
    strict = flood_bg(eroded)
    strict = (np.array(Image.fromarray((strict * 255).astype(np.uint8), "L").filter(ImageFilter.MaxFilter(5))) > 0) & is_bg
    bg = loose.copy()
    lab_l, n_l = label(loose & ~strict, eight=False)
    for i in range(1, n_l + 1):
        comp = lab_l == i
        if (comp & eroded).sum() >= 20:          # 太さのある白い領域 → 絵の一部
            bg[comp] = False
    lab, n = label(~bg)
    infos = comp_info(lab, n)
    keep = np.zeros((H, W), dtype=bool)
    dropped = []
    for i, d in enumerate(infos):
        w, h = d["x1"] - d["x0"] + 1, d["y1"] - d["y0"] + 1
        if keep_rule(i, d, w, h, H, W):
            keep |= lab == d["id"]
        else:
            dropped.append(f"{w}x{h}@({d['x0']},{d['y0']}) size={d['size']}")
    rgba = np.dstack([rgb, np.where(keep, 255, 0).astype(np.uint8)]).astype(np.uint8)
    return rgba, dropped


def rule_bed(i, d, w, h, H, W):
    if i == 0:
        return True
    if d["size"] < 60:
        return False
    # 端に接している塊は隣のコマの切れ端
    if d["x0"] <= 0 or d["x1"] >= W - 1 or d["y0"] <= 0 or d["y1"] >= H - 1:
        return False
    return True


def rule_face(i, d, w, h, H, W):
    if i == 0:
        return True
    # 汗粒は残す（小さくて本体の近く）。端に接する塊（隣の顔・「!」）は落とす
    if d["x0"] <= 0 or d["x1"] >= W - 1 or d["y0"] <= 0 or d["y1"] >= H - 1:
        return False
    return d["size"] >= 30


# ---------------------------------------------------------------- 2〜4（make_outfit_pixel.py と同じ）
def median_rgb(rgba, size=MEDIAN):
    if size <= 1:
        return rgba.copy()
    im = Image.fromarray(rgba[:, :, :3], "RGB").filter(ImageFilter.MedianFilter(size))
    out = rgba.copy()
    out[:, :, :3] = np.array(im)
    return out


def quantize(rgba, pal, disallow=(), zones=()):
    """zones: [(番号, x0f, y0f, x1f, y1f)] 不透明部分の外接枠に対する割合で、その範囲ではその色を使わない。"""
    P = np.array(pal, dtype=int)
    rgb = rgba[:, :, :3].astype(int)
    d = ((rgb[:, :, None, :] - P[None, None, :, :]) ** 2).sum(-1)
    for i in disallow:
        d[:, :, i] = 10 ** 9
    if zones:
        ys, xs = np.nonzero(rgba[:, :, 3])
        bx0, bx1, by0, by1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
        for i, x0f, y0f, x1f, y1f in zones:
            X0, X1 = int(bx0 + (bx1 - bx0) * x0f), int(bx0 + (bx1 - bx0) * x1f)
            Y0, Y1 = int(by0 + (by1 - by0) * y0f), int(by0 + (by1 - by0) * y1f)
            d[Y0:Y1, X0:X1, i] = 10 ** 9
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


def cleanup_specks_of(idx, keys, names, min_size, fallback):
    """口の赤・汗の青が輪郭のにじみから 1〜2 ドット湧くのを消す。min_size 未満の塊を fallback（隣の多数色）にする。"""
    targets = {keys.index(k) for k in names if k in keys}
    H, W = idx.shape
    mask = np.isin(idx, list(targets))
    lab, n = label(mask)
    for d in comp_info(lab, n):
        if d["size"] >= min_size:
            continue
        for y, x in zip(*np.nonzero(lab == d["id"])):
            nb = [idx[y + dy, x + dx] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
                  if 0 <= x + dx < W and 0 <= y + dy < H]
            op = [v for v in nb if v >= 0 and v not in targets]
            idx[y, x] = (max(set(op), key=op.count) if op else fallback)
    return idx


def to_image(idx, pal):
    H, W = idx.shape
    out = np.zeros((H, W, 4), dtype=np.uint8)
    for i, c in enumerate(pal):
        out[idx == i] = c + (255,)
    return Image.fromarray(out, "RGBA")


def crop_idx(idx):
    ys, xs = np.nonzero(idx >= 0)
    return idx[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def pipeline(rgba, pal_map, target_h, prot_keys=PROTECTED, disallow_keys=(), median=MEDIAN, outline_share=OUTLINE_SHARE, zone_keys=()):
    keys = list(pal_map.keys()); pal = [pal_map[k] for k in keys]
    assert keys[0] == "K" and len(pal) <= 20
    prot = {keys.index(k) for k in prot_keys if k in keys}
    dis = [keys.index(k) for k in disallow_keys if k in keys]
    ys = np.nonzero(rgba[:, :, 3])[0]
    ref_h = ys.max() - ys.min() + 1
    scale = target_h / float(ref_h)
    zones = [(keys.index(z[0]),) + tuple(z[1:]) for z in zone_keys if z[0] in keys]
    q = quantize(median_rgb(rgba, median), pal, dis, zones)
    for _ in range(4):
        small = mode_down(q, scale, len(pal), outline_share)
        small = drop_specks(small)
        small = cleanup_specks_of(small, keys, ("R", "m"), 4, 0)
        small = cleanup_specks_of(small, keys, ("a",), 3, 0)
        small = crop_idx(ensure_outline(majority_vote(small, prot), prot))
        if small.shape[0] == target_h:
            break
        scale *= target_h / float(small.shape[0])
    return small, keys, pal, scale


def main():
    src = Image.open(SRC).convert("RGB")
    full = np.array(src)
    report = []
    # ---- ベッド
    for name, spec in BEDS.items():
        x0, y0, x1, y1 = spec["box"]
        rgb = full[y0:y1, x0:x1].copy()
        for ex0, ey0, ex1, ey1 in spec["erase"]:
            rgb[ey0 - y0:ey1 - y0, ex0 - x0:ex1 - x0] = (255, 255, 255)
        for ex0, ey0, ex1, ey1 in spec.get("erase_light", []):   # 暗い輪郭線だけ残して消す
            sub = rgb[ey0 - y0:ey1 - y0, ex0 - x0:ex1 - x0]
            sub[sub.sum(-1) > 260] = (255, 255, 255)
        rgba, dropped = key_out(rgb, rule_bed)
        Image.fromarray(rgba, "RGBA").save(os.path.join(WORK, f"keyed_{name}.png"))
        for size in (48, 64):
            small, keys, pal, scale = pipeline(rgba, PAL_BED, size, median=MED_BED, disallow_keys=("m", "R") + spec.get("disallow", ()))
            img = to_image(small, pal)
            img.save(os.path.join(OUT, f"{name}_{size}.png"))
            report.append(f"{name}_{size}: {img.size[0]}×{img.size[1]} 1dot={1/scale:.2f}px 落とした={dropped}")
    # ---- 顔（30 ドット高に合わせ、32×30 の枠に中央寄せ）
    for name, spec in FACES.items():
        x0, y0, x1, y1 = spec["box"]
        rgb = full[y0:y1, x0:x1].copy()
        for ex0, ey0, ex1, ey1 in spec.get("erase", []):
            rgb[ey0 - y0:ey1 - y0, ex0 - x0:ex1 - x0] = (255, 255, 255)
        rgba, dropped = key_out(rgb, rule_face)
        Image.fromarray(rgba, "RGBA").save(os.path.join(WORK, f"keyed_face_{name}.png"))
        # 顔は作業着の紺・陰を使わない（髪の陰が紺に化けるのを防ぐ）
        for res in (1, 2):
            W, H = FACE_DOTS[0] * res, FACE_DOTS[1] * res
            dis = ("U", "u", "I") + (("a",) if name != "frown" else ())
            # 口の下の陰が濃い茶 d の塊になる／耳の内側が口の赤 R になるのを防ぐ（外接枠に対する割合で範囲を切る）
            zones = [("d", 0.0, 0.68, 1.0, 1.0),                     # d は耳の高さ（上 68%）だけ
                     ("R", 0.0, 0.0, 0.18, 1.0), ("R", 0.82, 0.0, 1.0, 1.0),   # 耳の列に赤を出さない
                     ("m", 0.0, 0.0, 0.18, 1.0), ("m", 0.82, 0.0, 1.0, 1.0),
                     ("R", 0.0, 0.90, 1.0, 1.0), ("m", 0.0, 0.90, 1.0, 1.0),   # あごの下端に赤を出さない
                     ("C", 0.0, 0.0, 1.0, 0.45), ("C", 0.0, 0.80, 1.0, 1.0)]   # 頬の色は頬の高さだけ
            if name == "frown":
                # 汗粒（青）は顔に接しているので塊の判定で拾えない → 青みの強い画素を汗の色に寄せておく
                r_, g_, b_ = rgba[:, :, 0].astype(int), rgba[:, :, 1].astype(int), rgba[:, :, 2].astype(int)
                wet = (b_ > r_ + 40) & (rgba[:, :, 3] > 0)
                rgba = rgba.copy(); rgba[wet, :3] = GAME["a"]
            # 32×30 は閉じた目の細い線が消えるので縁取り色の優先を強める（0.20）。64×60 は 0.30
            pal_map = PAL_FACE
            if name == "cheer":
                pal_map = PAL_FACE_CHEER
                zones += [("L", 0.0, 0.0, 1.0, 0.62), ("l", 0.0, 0.0, 1.0, 0.62), ("L", 0.0, 0.0, 0.2, 1.0), ("L", 0.8, 0.0, 1.0, 1.0),
                          ("l", 0.0, 0.0, 0.2, 1.0), ("l", 0.8, 0.0, 1.0, 1.0)]
            small, keys, pal, scale = pipeline(rgba, pal_map, H, disallow_keys=dis, median=MED_FACE, outline_share=(0.20 if res == 1 else 0.30), zone_keys=zones)
            img = to_image(small, pal)
            canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            if img.size[0] > W:
                # 幅が枠を超えるときは左右を切る（耳の外側）
                cut = (img.size[0] - W) // 2
                img = img.crop((cut, 0, cut + W, img.size[1]))
            canvas.alpha_composite(img, ((W - img.size[0]) // 2, (H - img.size[1]) // 2))
            canvas.save(os.path.join(OUT, f"face_{name}_{W}x{H}.png"))
            report.append(f"face_{name}_{W}x{H}: raw {small.shape[1]}×{small.shape[0]} 1dot={1/scale:.2f}px 落とした={dropped}")
    print("\n".join(report))


if __name__ == "__main__":
    main()
