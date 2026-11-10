"""test-compress-images.sh 用のテスト画像を作る（#2913）。

使い方: python3 make-compress-images-fixtures.py <出力先ディレクトリ>
"""
import os
import random
import sys

from PIL import Image

root = sys.argv[1]
os.makedirs(root, exist_ok=True)

# 多色のノイズ画像（300x300・MIN_BYTES を超え、256 色パレット化で 5% 以上縮む）。
random.seed(42)
im = Image.new("RGB", (300, 300))
px = im.load()
for y in range(300):
    for x in range(300):
        px[x, y] = (random.randint(0, 255), random.randint(0, 255), random.randint(0, 255))
im.save(os.path.join(root, "big.png"))

# MIN_BYTES（30KB）未満の小さい画像。圧縮の余地があっても対象外になることを確かめる用。
Image.new("RGB", (4, 4), (10, 20, 30)).save(os.path.join(root, "tiny.png"))
