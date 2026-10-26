#!/bin/bash
# compress-images.py の検証（#2838）。
#
# 出荷物（App/Assets.xcassets・Packages/**/Resources）をその場で上書きするスクリプトなので、
# AppIcon への透過混入・世代劣化の繰り返し・冪等性の崩れを止める。実リポジトリの画像には触れず、
# 一時ディレクトリに Pillow で作った画像だけを対象に `compress-images.py <一時ディレクトリ>` を実行する。
#
# Pillow が無い環境は skip する（test-generate-hub-tiles.sh と同じ流儀。終了コード 0）。
#
# 使い方: bash Scripts/tests/test-compress-images.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../compress-images.py"

if ! python3 -c "import PIL" 2>/dev/null; then
  echo "SKIP: Pillow が無いため compress-images.py のテストを飛ばします"
  exit 0
fi

TARGET="$TARGET" python3 - <<'PY'
import hashlib
import importlib.util
import os
import random
import shutil
import subprocess
import sys
import tempfile

from PIL import Image

TARGET = os.environ["TARGET"]
spec = importlib.util.spec_from_file_location("compress_images", TARGET)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

passed = failed = 0


def check(label, cond):
    global passed, failed
    if cond:
        passed += 1
        print(f"  ok   - {label}")
    else:
        failed += 1
        print(f"  NG   - {label}")


def digest(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def run(root, *extra):
    r = subprocess.run([sys.executable, TARGET, *extra, root], capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout, r.stderr)
    return r


def gradient(size, alpha=False):
    """滑らかなグラデーション（減色しても誤差が小さい・フルカラー）。"""
    im = Image.new("RGBA" if alpha else "RGB", (size, size))
    px = im.load()
    for y in range(size):
        for x in range(size):
            c = (x * 255 // size, y * 255 // size, (x + y) * 255 // (2 * size))
            px[x, y] = c + (255,) if alpha else c
    return im


def noise(size, seed):
    rnd = random.Random(seed)
    im = Image.new("RGB", (size, size))
    im.putdata([(rnd.randrange(256), rnd.randrange(256), rnd.randrange(256)) for _ in range(size * size)])
    return im


root = tempfile.mkdtemp(prefix="compress-images-test-")
try:
    icon_dir = os.path.join(root, "Assets.xcassets", "AppIcon.appiconset")
    os.makedirs(icon_dir)
    small = os.path.join(root, "small.png")
    big = os.path.join(root, "big.png")
    icon = os.path.join(icon_dir, "icon.png")
    high_jpg = os.path.join(root, "high.jpg")
    low_jpg = os.path.join(root, "low.jpg")

    # ① 30KB 未満（圧縮の余地は十分あるが触らない）
    gradient(64).save(small, compress_level=0)
    # ② 大きいフルカラー PNG（無圧縮で保存 = 減色・再圧縮で確実に縮む）
    big_src = gradient(400)
    big_src.save(big, compress_level=0)
    # ③ AppIcon 相当（透過なし・無圧縮）
    icon_src = gradient(400)
    icon_src.save(icon, compress_level=0)
    # ⑥ JPEG: 高品質（品質 95・100KB 以上）は再保存して縮む / 品質 50（100KB 以上）は触らない
    noise(500, 1).save(high_jpg, "JPEG", quality=95)
    noise(900, 2).save(low_jpg, "JPEG", quality=50)

    sizes = {p: os.path.getsize(p) for p in (small, big, icon, high_jpg, low_jpg)}
    hashes = {p: digest(p) for p in sizes}
    check("前提: small.png は 30KB 未満", sizes[small] < m.MIN_BYTES)
    check("前提: big.png・icon.png は 30KB 以上", sizes[big] >= m.MIN_BYTES and sizes[icon] >= m.MIN_BYTES)
    check("前提: JPEG はどちらも 100KB 以上", sizes[high_jpg] >= m.JPEG_MIN_BYTES and sizes[low_jpg] >= m.JPEG_MIN_BYTES)
    check("前提: 品質 95 は判定の基準より高品質、品質 50 は低品質",
          m.jpeg_quality_sum(Image.open(high_jpg)) < m.jpeg_reference_sum()
          and m.jpeg_quality_sum(Image.open(low_jpg)) >= m.jpeg_reference_sum())

    # ⑤ --dry-run はファイルを変えない（一時ファイルも残さない）
    before_tree = sorted(os.path.join(d, f) for d, _, fs in os.walk(root) for f in fs)
    r = run(root, "--dry-run")
    check("--dry-run は正常終了する", r.returncode == 0)
    check("--dry-run は書き換えるはずの画像を報告する", "big.png" in r.stdout)
    check("--dry-run は全ファイルの中身を変えない", all(digest(p) == hashes[p] for p in sizes))
    check("--dry-run は一時ファイルを残さない",
          sorted(os.path.join(d, f) for d, _, fs in os.walk(root) for f in fs) == before_tree)

    # 本番実行
    r = run(root)
    check("実行は正常終了する", r.returncode == 0)

    # ① 30KB 未満は触らない
    check("30KB 未満の PNG は触らない", digest(small) == hashes[small])

    # ② フルカラーの大きい PNG は小さくなり、見た目の誤差が MAX_RMS 以内
    check("フルカラーの大きい PNG は 5% 以上小さくなる", os.path.getsize(big) < sizes[big] * m.MIN_GAIN)
    out = Image.open(big)
    check("フルカラー PNG は 256 色パレットになる", out.mode == "P")
    check("減色後の誤差が MAX_RMS 以内", m.rms(big_src, out) <= m.MAX_RMS)
    check("減色しても解像度は変えない", out.size == big_src.size)

    # ③ AppIcon（.appiconset 配下）は減色せず、透過も入らない
    ic = Image.open(icon)
    check("AppIcon は小さくなる（可逆の再圧縮）", os.path.getsize(icon) < sizes[icon] * m.MIN_GAIN)
    check("AppIcon はパレット化されない", ic.mode == "RGB")
    check("AppIcon に透過チャンネルが入らない", "A" not in ic.mode and "transparency" not in ic.info)
    check("AppIcon の画素は 1 つも変わらない", ic.tobytes() == icon_src.tobytes())

    # ⑥ JPEG: 品質 85 以下は再保存しない、高品質は再保存する
    check("品質 50 の JPEG（100KB 以上）は再保存しない", digest(low_jpg) == hashes[low_jpg])
    check("品質 95 の JPEG は再保存されて小さくなる", os.path.getsize(high_jpg) < sizes[high_jpg] * m.MIN_GAIN)

    # ④ 2 回目の実行は何も書き換えない（冪等）
    after_first = {p: digest(p) for p in sizes}
    r = run(root)
    check("2 回目の実行も正常終了する", r.returncode == 0)
    check("2 回目の実行は全ファイルの中身を変えない", all(digest(p) == after_first[p] for p in sizes))
    check("2 回目の実行は書き換え行を 1 つも出さない", " KB " not in r.stdout.split("合計")[0])

    # 透過つきフルカラー PNG: 減色されても半透明の画素が残る（透過が潰れない）
    alpha_png = os.path.join(root, "alpha.png")
    alpha_src = gradient(400, alpha=True)
    alpha_src.putalpha(Image.linear_gradient("L").resize((400, 400)))
    alpha_src.save(alpha_png, compress_level=0)
    size_a = os.path.getsize(alpha_png)
    run(root)
    check("透過つきフルカラー PNG は小さくなる", os.path.getsize(alpha_png) < size_a * m.MIN_GAIN)
    lo, hi = Image.open(alpha_png).convert("RGBA").getchannel("A").getextrema()
    check("透過つきフルカラー PNG は減色後も透過を保つ", lo < 64 and hi > 192)
finally:
    shutil.rmtree(root, ignore_errors=True)

print(f"\n{passed} 件成功 / {failed} 件失敗")
sys.exit(1 if failed else 0)
PY
