#!/usr/bin/env python3
"""おじさんの盆栽: 段ごとに鉢の形を変える加工（#2388）。

同じ色の段（椿と南天・銀杏と金の松・真柏と黒松・桜と梅）が大きさでしか見分けられなかったので、
会長提供の盆栽シート（ChatGPT 生成・2026-10-17）から切り出した絵の**鉢の部分だけ**を段ごとに
別の形へ加工する。木と苔はそのまま、鉢は「鉢の縁の上端」から下を縦横に伸縮し、段によっては
木の卓（台）を描き足す。塗りは元の絵の画素を使うので、鉢の模様・色は元のまま残る。

入力は #2388 より前の `Packages/GameKit/Sources/GameFruits/Resources/Bonsai/`（git の履歴
`origin/release/v1.1.13` 時点）。出力は同じ名前で上書きする。

    /usr/bin/python3 docs/design/bonsai/make_pots.py <入力dir> <出力dir>

段ごとの形（小 → 大）:
  1 桜      丸鉢（元のまま・小さく丸い）
  2 椿      長方鉢・足付き（元のまま）
  3 藤      懸崖鉢（縦に長い）
  4 梅      水盤（横に広く平たい）
  5 みかん  深い丸鉢
  6 銀杏    長方鉢を低い卓に載せる
  7 南天    深い楕円鉢（縦に長い）
  8 紅葉    横に広い長方鉢
  9 真柏    平たい盤を広い板の卓に載せる
 10 黒松    深い長方鉢
 11 金の松  丸鉢を高い卓（高卓）に載せる
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

# 段ごとの加工。rim は「鉢の縁の上端」の y（元の絵の上から・px）。
# sx / sy は鉢の横・縦の倍率。stand は卓の種類（None / "low" / "wide" / "tall"）。
SPECS = {
    "Bonsai_01_sakura":    dict(rim=89,  sx=1.00, sy=1.00, stand=None),
    "Bonsai_02_tsubaki":   dict(rim=110, sx=1.00, sy=1.00, stand=None),
    "Bonsai_03_fuji":      dict(rim=137, sx=1.00, sy=1.90, stand=None),
    "Bonsai_04_ume":       dict(rim=157, sx=1.08, sy=0.50, stand=None),
    "Bonsai_05_mikan":     dict(rim=197, sx=1.00, sy=1.35, stand=None),
    "Bonsai_06_icho":      dict(rim=223, sx=1.00, sy=1.00, stand="low"),
    "Bonsai_07_nanten":    dict(rim=211, sx=1.00, sy=1.50, stand=None),
    "Bonsai_08_momiji":    dict(rim=246, sx=1.12, sy=0.80, stand=None),
    "Bonsai_09_shinpaku":  dict(rim=223, sx=1.15, sy=0.45, stand="wide"),
    "Bonsai_10_kuromatsu": dict(rim=234, sx=1.00, sy=1.55, stand=None),
    "Bonsai_11_kinmatsu":  dict(rim=213, sx=1.00, sy=1.00, stand="tall"),
}

# 同梱する絵の長辺の上限（`ArtTests.artIsDownscaled` と同じ）。
MAX_SIDE = 320

WOOD = (112, 72, 40, 255)
WOOD_LIGHT = (150, 102, 60, 255)
WOOD_DARK = (74, 44, 24, 255)


def opaque_bounds(im: Image.Image, y0: int, y1: int):
    """y0..y1 の行で不透明な画素の x の範囲。"""
    a = im.split()[3].crop((0, y0, im.width, y1))
    box = a.point(lambda v: 255 if v > 40 else 0).getbbox()
    return (box[0], box[2]) if box else (0, im.width)


def draw_stand(kind: str, width: int, pot_bottom_w: int) -> Image.Image:
    """卓（台）。幅 `width` の絵に対して、鉢の底の幅 `pot_bottom_w` に合う大きさで描く。"""
    cx = width / 2
    if kind == "low":
        h = max(10, int(pot_bottom_w * 0.09))
        plank_w = pot_bottom_w * 1.12
        leg_h = h * 0.9
        img = Image.new("RGBA", (width, int(h + leg_h) + 2), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        # 天板
        d.rounded_rectangle([cx - plank_w / 2, 0, cx + plank_w / 2, h], radius=h * 0.35, fill=WOOD)
        d.rounded_rectangle([cx - plank_w / 2, 0, cx + plank_w / 2, h * 0.35], radius=h * 0.3, fill=WOOD_LIGHT)
        # 脚（左右）
        leg_w = max(4, h * 0.9)
        for lx in (cx - plank_w / 2 + leg_w * 1.2, cx + plank_w / 2 - leg_w * 2.2):
            d.rectangle([lx, h, lx + leg_w, h + leg_h], fill=WOOD_DARK)
        return img
    if kind == "wide":
        h = max(10, int(pot_bottom_w * 0.07))
        plank_w = pot_bottom_w * 1.25
        leg_h = h * 1.1
        img = Image.new("RGBA", (width, int(h + leg_h) + 2), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        d.rounded_rectangle([cx - plank_w / 2, 0, cx + plank_w / 2, h], radius=h * 0.3, fill=WOOD)
        d.rounded_rectangle([cx - plank_w / 2, 0, cx + plank_w / 2, h * 0.35], radius=h * 0.3, fill=WOOD_LIGHT)
        # 脚は板状（横に広い）
        leg_w = plank_w * 0.08
        for lx in (cx - plank_w / 2 + leg_w, cx + plank_w / 2 - leg_w * 2):
            d.rectangle([lx, h, lx + leg_w, h + leg_h], fill=WOOD_DARK)
        return img
    if kind == "tall":
        top_h = max(10, int(pot_bottom_w * 0.09))
        column_h = int(pot_bottom_w * 0.42)
        base_h = top_h
        plank_w = pot_bottom_w * 1.15
        column_w = pot_bottom_w * 0.62
        base_w = pot_bottom_w * 0.95
        img = Image.new("RGBA", (width, top_h + column_h + base_h + 2), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        # 天板
        d.rounded_rectangle([cx - plank_w / 2, 0, cx + plank_w / 2, top_h], radius=top_h * 0.35, fill=WOOD)
        d.rounded_rectangle([cx - plank_w / 2, 0, cx + plank_w / 2, top_h * 0.35], radius=top_h * 0.3, fill=WOOD_LIGHT)
        # 胴（左を明るく・右を暗く）
        y0 = top_h
        y1 = top_h + column_h
        d.rectangle([cx - column_w / 2, y0, cx + column_w / 2, y1], fill=WOOD)
        d.rectangle([cx - column_w / 2, y0, cx - column_w / 2 + column_w * 0.18, y1], fill=WOOD_LIGHT)
        d.rectangle([cx + column_w / 2 - column_w * 0.22, y0, cx + column_w / 2, y1], fill=WOOD_DARK)
        # 胴の窓（透かし）
        wx = column_w * 0.22
        d.rounded_rectangle([cx - wx, y0 + column_h * 0.22, cx + wx, y1 - column_h * 0.22],
                            radius=wx * 0.5, fill=WOOD_DARK)
        # 台座
        d.rounded_rectangle([cx - base_w / 2, y1, cx + base_w / 2, y1 + base_h], radius=base_h * 0.35, fill=WOOD)
        d.rectangle([cx - base_w / 2, y1 + base_h * 0.6, cx + base_w / 2, y1 + base_h], fill=WOOD_DARK)
        return img
    raise ValueError(kind)


def process(src: Path, dst: Path) -> None:
    spec = SPECS[src.stem]
    im = Image.open(src).convert("RGBA")
    W, H = im.size
    rim = spec["rim"]
    tree = im.crop((0, 0, W, rim))
    pot = im.crop((0, rim, W, H))
    pot_w = int(round(W * spec["sx"]))
    pot_h = max(1, int(round(pot.height * spec["sy"])))
    pot = pot.resize((pot_w, pot_h), Image.LANCZOS)

    out_w = max(W, pot_w)
    stand = None
    if spec["stand"]:
        # 鉢の底の幅（足と影を除いた胴の下のほう）
        x0, x1 = opaque_bounds(pot, int(pot_h * 0.6), int(pot_h * 0.75))
        stand = draw_stand(spec["stand"], out_w, x1 - x0)
    out_h = rim + pot_h + (stand.height if stand else 0)
    out = Image.new("RGBA", (out_w, out_h), (0, 0, 0, 0))
    if stand:
        out.alpha_composite(stand, (0, rim + pot_h - 2))
    out.alpha_composite(pot, ((out_w - pot_w) // 2, rim))
    out.alpha_composite(tree, ((out_w - W) // 2, 0))

    # 長辺を上限に収める
    side = max(out.size)
    if side > MAX_SIDE:
        s = MAX_SIDE / side
        out = out.resize((max(1, int(round(out.width * s))), max(1, int(round(out.height * s)))), Image.LANCZOS)

    # 256 色に減色（元の素材と同じ作法）
    out = out.quantize(colors=256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.FLOYDSTEINBERG)
    out.save(dst, optimize=True)
    print(f"{src.name}: {W}x{H} -> {out.width}x{out.height}")


def main() -> None:
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)
    src_dir, dst_dir = Path(sys.argv[1]), Path(sys.argv[2])
    dst_dir.mkdir(parents=True, exist_ok=True)
    for name in SPECS:
        process(src_dir / f"{name}.png", dst_dir / f"{name}.png")


if __name__ == "__main__":
    main()
