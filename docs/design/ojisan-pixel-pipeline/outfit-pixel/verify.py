"""px48/ px64/ の各コマを数えて検証する: サイズ・色数（透明除く）・半透明の有無・パレット外の色。"""
import glob, os, sys
import numpy as np
from PIL import Image
from make_outfit_pixel import PALETTES, FRAMES
HERE = os.path.dirname(os.path.abspath(__file__))
ok = True
for size in (48, 64):
    for outfit in FRAMES:
        pal = set(PALETTES[outfit].values())
        for name, _ in FRAMES[outfit]:
            f = f"{HERE}/px{size}/{outfit}_{name}.png"
            a = np.array(Image.open(f).convert("RGBA"))
            alphas = set(np.unique(a[:, :, 3]).tolist())
            op = a[a[:, :, 3] > 0][:, :3]
            cols = {tuple(int(v) for v in c) for c in np.unique(op, axis=0)}
            outside = cols - pal
            semi = alphas - {0, 255}
            # 縁取り: 透明に接する不透明ドットのうち縁取り色でないもの（記号の小塊は除く）
            K = PALETTES[outfit]["K"]
            H, W = a.shape[:2]
            nonk = 0
            for y in range(H):
                for x in range(W):
                    if a[y, x, 3] == 0 or tuple(a[y, x, :3]) == K:
                        continue
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        nx, ny = x + dx, y + dy
                        if not (0 <= nx < W and 0 <= ny < H) or a[ny, nx, 3] == 0:
                            nonk += 1; break
            empty = len(op) == 0
            bad_size = name == "front_neutral" and H != size
            flag = "" if (not outside and not semi and not empty and not bad_size) else "  <-- NG"
            if flag: ok = False
            print(f"px{size} {outfit}/{name:28s} {W:3d}x{H:3d}  色数 {len(cols):2d}  alpha {sorted(alphas)}  縁取り以外の輪郭ドット {nonk:3d}{flag}")
        print(f"   パレット {outfit}: {len(pal)} 色")
print("ALL OK" if ok else "NG あり")
sys.exit(0 if ok else 1)
