"""ドット絵化の共通ヘルパー（Pillow + numpy のみ。anaconda の scipy は numpy と不整合で使えない）。"""
from collections import deque
import numpy as np
from PIL import Image

N8 = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]
N4 = [(1, 0), (-1, 0), (0, 1), (0, -1)]


def label(mask, eight=True):
    """bool 2D 配列の連結成分。(ラベル配列(int32, 0=背景), 成分数) を返す。"""
    H, W = mask.shape
    lab = np.zeros((H, W), dtype=np.int32)
    nb = N8 if eight else N4
    n = 0
    ys, xs = np.nonzero(mask)
    for sy, sx in zip(ys.tolist(), xs.tolist()):
        if lab[sy, sx]:
            continue
        n += 1
        lab[sy, sx] = n
        dq = deque([(sx, sy)])
        while dq:
            x, y = dq.popleft()
            for dx, dy in nb:
                nx, ny = x + dx, y + dy
                if 0 <= nx < W and 0 <= ny < H and mask[ny, nx] and not lab[ny, nx]:
                    lab[ny, nx] = n
                    dq.append((nx, ny))
    return lab, n


def flood_bg(is_bg):
    """枠から繋がっている背景だけ True。"""
    H, W = is_bg.shape
    out = np.zeros((H, W), dtype=bool)
    dq = deque()
    for x in range(W):
        dq.append((x, 0)); dq.append((x, H - 1))
    for y in range(H):
        dq.append((0, y)); dq.append((W - 1, y))
    while dq:
        x, y = dq.popleft()
        if x < 0 or y < 0 or x >= W or y >= H or out[y, x] or not is_bg[y, x]:
            continue
        out[y, x] = True
        dq.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
    return out


def comp_info(lab, n, rgb=None):
    infos = []
    for i in range(1, n + 1):
        ys, xs = np.nonzero(lab == i)
        d = dict(id=i, size=len(ys), x0=int(xs.min()), x1=int(xs.max()), y0=int(ys.min()), y1=int(ys.max()))
        if rgb is not None:
            d["mean"] = tuple(int(v) for v in rgb[lab == i].mean(0))
        infos.append(d)
    infos.sort(key=lambda d: -d["size"])
    return infos
