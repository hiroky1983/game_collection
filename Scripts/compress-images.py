#!/usr/bin/env python3
"""アプリに同梱する大きな PNG を、見た目をほぼ変えずに小さくする（#2390）。

使い方:
    python3 Scripts/compress-images.py [--dry-run] [パス...]
パスを省略すると App/Assets.xcassets と Packages 配下の Resources を走査する。
新しいタイル・画像を足したときも同じコマンドを回す（処理済みの画像は再実行しても変わらない）。

方針（Pillow だけで動く。pngquant 等の外部コマンドは要らない）:
- フルカラー PNG は 256 色パレット + Floyd–Steinberg ディザへ減色する。
  元画像との誤差（RMS・0〜255）が MAX_RMS を超えたら減色せず、可逆の再圧縮だけにする。
- AppIcon は App Store 要件（1024×1024・透過なし）を守り、グラデーションの縞が出やすいので可逆の再圧縮だけ。
- パレット PNG（P）は可逆の再圧縮だけ。
- 結果が 5% 以上小さくならなければ書き換えない。縮小はしない（絵柄・解像度は変えない）。
"""
import argparse
import glob
import os
import sys

from PIL import Image, ImageChops, ImageFilter, ImageStat

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_PATHS = [
    os.path.join(ROOT, "App/Assets.xcassets"),
    os.path.join(ROOT, "Packages"),
]
MIN_BYTES = 30 * 1024  # これより小さい画像は触らない
MIN_GAIN = 0.95  # 5% 以上小さくならない書き換えはしない（差分のノイズを避ける）
JPEG_MIN_BYTES = 100 * 1024
JPEG_QUALITY = 85
MAX_RMS = 3.0  # 減色を許す誤差（ぼかした元画像との RGBA 全チャンネルの RMS 平均）


def rms(a: Image.Image, b: Image.Image) -> float:
    """ぼかしてから比べる（ディザの細かい粒は見た目ではなく誤差として数えない）。"""
    a, b = (i.convert("RGBA").filter(ImageFilter.GaussianBlur(1.5)) for i in (a, b))
    diff = ImageChops.difference(a, b)
    return sum(v * v for v in ImageStat.Stat(diff).rms) ** 0.5 / 2


def jpgs(paths):
    for p in paths:
        if os.path.isfile(p):
            if p.lower().endswith((".jpg", ".jpeg")):
                yield p
        else:
            yield from glob.glob(os.path.join(p, "**", "*.jp*g"), recursive=True)


def pngs(paths):
    for p in paths:
        if os.path.isfile(p):
            yield p
        else:
            for f in glob.glob(os.path.join(p, "**", "*.png"), recursive=True):
                if "/.build/" not in f and "/node_modules/" not in f:
                    yield f


def compress(path: str, out: str):
    """out へ書く。(方式, RMS) を返す。"""
    im = Image.open(path)
    im.load()
    lossless_only = im.mode == "P" or "AppIcon" in path
    if not lossless_only:
        if "A" in im.mode:
            # 透過つきはパレット指定のディザが使えない（Pillow の制約）ので、FASTOCTREE のままで減色する
            q = im.quantize(colors=256, method=Image.Quantize.FASTOCTREE)
        else:
            # quantize(dither=) はパレットを渡したときだけ効くので、2 段にする（パレット作り → ディザ付きで塗り直し）
            palette = im.quantize(colors=256, method=Image.Quantize.MEDIANCUT)
            q = im.quantize(palette=palette, dither=Image.Dither.FLOYDSTEINBERG)
        q.save(out, optimize=True)
        err = rms(im, Image.open(out))
        if err <= MAX_RMS:
            return "palette256", err
    im.save(out, optimize=True)
    return "lossless", 0.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("paths", nargs="*")
    args = ap.parse_args()
    tmp = os.path.join(os.environ.get("DUTY_SCRATCH_DIR", "/tmp"), "compress-images.tmp.png")
    before = after = 0
    for f in sorted(pngs(args.paths or DEFAULT_PATHS)):
        size = os.path.getsize(f)
        if size < MIN_BYTES:
            continue
        mode, err = compress(f, tmp)
        new = os.path.getsize(tmp)
        before += size
        if new < size * MIN_GAIN:
            after += new
            if not args.dry_run:
                os.replace(tmp, f)
            print(f"{size // 1024:>6} -> {new // 1024:>5} KB  {mode:<10} rms={err:.2f}  {os.path.relpath(f, ROOT)}")
        else:
            after += size
    # JPEG は 100KB 以上のものだけ、品質 85 で再保存する（すでに 85 以下なら 5% 縮まず書き換えない）
    for f in sorted(jpgs(args.paths or DEFAULT_PATHS)):
        size = os.path.getsize(f)
        if size < JPEG_MIN_BYTES:
            continue
        Image.open(f).save(tmp, "JPEG", quality=JPEG_QUALITY, optimize=True, progressive=True)
        new = os.path.getsize(tmp)
        before += size
        if new < size * MIN_GAIN:
            after += new
            if not args.dry_run:
                os.replace(tmp, f)
            print(f"{size // 1024:>6} -> {new // 1024:>5} KB  jpeg q{JPEG_QUALITY}  {os.path.relpath(f, ROOT)}")
        else:
            after += size
    print(f"合計 {before / 1e6:.2f} MB -> {after / 1e6:.2f} MB")
    if os.path.exists(tmp):
        os.remove(tmp)


if __name__ == "__main__":
    sys.exit(main())
