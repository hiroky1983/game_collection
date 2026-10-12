#!/usr/bin/env python3
"""px24/ の荷物ドット絵から、本体から突き出した孤立した縁取りの点を機械的に落とす（#2115）。

会長指摘（2026-10-12）: 座布団の右下に 1 ドットの孤立した黒い点がある。手で描き足さず、規則で消す。

規則（5 枚すべてに同じ規則をかける。手直しの座標は持たない）:
  縁取り色 K のドットのうち
    - 周り 8 近傍に K 以外の色（荷物の面）が 1 つも無い（＝何の輪郭にもなっていない）
    - 周り 8 近傍の不透明ドットが 3 つ以下（＝本体から突き出した先端）
  を透明にする。消すと隣が新たに先端になることがあるので、変化が無くなるまで繰り返す。
縁取りの太い部分（8 近傍が 4 つ以上埋まっている）や、面に接している輪郭は消えない。

使い方: python3 remove_isolated.py <入力ディレクトリ> <出力ディレクトリ>
Pillow のみ使用（/usr/bin/python3 で動く）。
"""
import glob
import os
import sys

from PIL import Image

K = (0x26, 0x22, 0x2C)  # 縁取り（make_luggage_pixel.py の K）


def clean(im):
    im = im.convert("RGBA")
    W, H = im.size
    p = im.load()

    def opaque(x, y):
        return 0 <= x < W and 0 <= y < H and p[x, y][3] > 0

    def is_k(x, y):
        return opaque(x, y) and p[x, y][:3] == K

    removed = []
    while True:
        drop = []
        for y in range(H):
            for x in range(W):
                if not is_k(x, y):
                    continue
                nb = [(x + dx, y + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy]
                touches_face = any(opaque(a, b) and not is_k(a, b) for a, b in nb)
                n_opaque = sum(opaque(a, b) for a, b in nb)
                if not touches_face and n_opaque <= 3:
                    drop.append((x, y))
        if not drop:
            return im, removed
        for x, y in drop:
            p[x, y] = (0, 0, 0, 0)
        removed += drop


def main():
    src, dst = sys.argv[1], sys.argv[2]
    os.makedirs(dst, exist_ok=True)
    for f in sorted(glob.glob(os.path.join(src, "*.png"))):
        im, removed = clean(Image.open(f))
        im.save(os.path.join(dst, os.path.basename(f)))
        print(os.path.basename(f), "消したドット:", removed)


if __name__ == "__main__":
    main()
