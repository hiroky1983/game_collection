#!/usr/bin/env python3
"""HTML を Chrome のヘッドレスで 3 倍解像度の PNG にする。
使い方: render.py <in.html> <out.png> [幅 CSS px] [高さ CSS px]
"""
import os, subprocess, sys, tempfile, shutil

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
src, out = sys.argv[1], sys.argv[2]
w = sys.argv[3] if len(sys.argv) > 3 else "402"
h = sys.argv[4] if len(sys.argv) > 4 else "874"
profile = tempfile.mkdtemp(prefix="catmock-chrome-")
try:
    subprocess.run([
        CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--no-first-run",
        "--user-data-dir=" + profile,
        "--force-device-scale-factor=3", f"--window-size={w},{h}",
        "--screenshot=" + os.path.abspath(out), "file://" + os.path.abspath(src),
    ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
finally:
    shutil.rmtree(profile, ignore_errors=True)
from PIL import Image
print(out, Image.open(out).size)
