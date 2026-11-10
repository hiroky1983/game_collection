#!/usr/bin/env python3
"""盆栽の合体パズル（スイカゲーム型・コードはまだ無い）の画面モック（着物おじさんのドット絵入り）。

実行: /usr/bin/python3 make_mock_bonsai.py  → mock_bonsai.png
画面構成（見本）:
  見出しカード（スコア・ベスト・つぎの玉）／器 = 大きな鉢（上から次の玉を落とす。上端近くに限界線）／
  下段: 着物おじさんの枠 + 吹き出し + 進化の順（9 段階）／ゲームオーバーは画面全体に重ねるカード。
盆栽の玉は仮のドット絵（draw_ball でその場で描く。1 ドット = 2pt）。
"""
import math
import os
from PIL import Image, ImageDraw

import mockkit as M
from mockkit import S, text, text_run, rrect, card, sprite, paste_center

HERE = os.path.dirname(os.path.abspath(__file__))
PX = f"{HERE}/px48"
K = 4  # ドット絵の拡大率（1 ドット = 2pt）

# ---------------------------------------------------------------- 盆栽の玉（仮のドット絵）
OUT = (0x26, 0x22, 0x2C, 255)
GREEN, GREEN_D, GREEN_L = (0x46, 0x8C, 0x3C, 255), (0x28, 0x60, 0x28, 255), (0x7C, 0xB4, 0x58, 255)
PINE, PINE_D = (0x2E, 0x6A, 0x3E, 255), (0x1C, 0x44, 0x2A, 255)
SAKURA, SAKURA_D = (0xF4, 0xA6, 0xBE, 255), (0xD8, 0x6E, 0x92, 255)
MOMIJI, MOMIJI_D = (0xD8, 0x50, 0x3A, 255), (0xA0, 0x30, 0x28, 255)
POT, POT_L = (0x76, 0x48, 0x2C, 255), (0x9A, 0x66, 0x40, 255)
POT_BLUE, POT_BLUE_L = (0x2A, 0x3E, 0x5C, 255), (0x4A, 0x64, 0x8C, 255)
GOLD, GOLD_L = (0xC8, 0x96, 0x2E, 255), (0xE8, 0xC0, 0x5A, 255)
WHITE = (0xFA, 0xFA, 0xFA, 255)
TRUNK = (0x5A, 0x3A, 0x22, 255)

# (段階, 名前, 直径ドット, 葉の色, 葉の陰, 鉢の色, 鉢の照り, 飾り)
TIERS = [
    (1, "芽", 10, GREEN_L, GREEN, POT, POT_L, None),
    (2, "苗", 14, GREEN, GREEN_D, POT, POT_L, None),
    (3, "小松", 18, PINE, PINE_D, POT, POT_L, None),
    (4, "梅", 24, GREEN, GREEN_D, POT, POT_L, "flower"),
    (5, "桜", 30, SAKURA, SAKURA_D, POT, POT_L, None),
    (6, "紅葉", 38, MOMIJI, MOMIJI_D, POT_BLUE, POT_BLUE_L, None),
    (7, "黒松", 48, PINE, PINE_D, POT_BLUE, POT_BLUE_L, "needle"),
    (8, "名木", 60, GREEN, GREEN_D, GOLD, GOLD_L, "flower"),
    (9, "大名木", 72, PINE, PINE_D, GOLD, GOLD_L, "needle"),
]
_ball_cache = {}


def draw_ball(tier):
    """直径 d ドットの円に収まる盆栽（丸い樹冠 + 幹 + 鉢）を描く。"""
    if tier in _ball_cache:
        return _ball_cache[tier]
    _, _, d, leaf, leaf_d, pot, pot_l, deco = TIERS[tier - 1]
    im = Image.new("RGBA", (d, d), (0, 0, 0, 0))
    px = im.load()
    cx, cy, r = d / 2.0, d * 0.44, d * 0.42
    inside = [[((x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2) <= r * r for x in range(d)] for y in range(d)]
    # 鉢（下）と幹
    pw, ph = max(3, int(round(d * 0.42))), max(1, int(round(d * 0.14)))
    py0 = int(round(d * 0.94)) - ph
    px0 = int(round(cx - pw / 2.0))
    for y in range(py0, py0 + ph):
        for x in range(px0, px0 + pw):
            if 0 <= x < d and 0 <= y < d:
                edge = y == py0 or y == py0 + ph - 1 or x == px0 or x == px0 + pw - 1
                px[x, y] = OUT if edge else (pot_l if y == py0 + 1 else pot)
    tw = 1 if d < 14 else 2
    for y in range(int(cy + r * 0.6), py0):
        for x in range(int(round(cx - tw / 2.0)), int(round(cx - tw / 2.0)) + tw):
            if 0 <= x < d and 0 <= y < d:
                px[x, y] = TRUNK
    # 樹冠
    for y in range(d):
        for x in range(d):
            if not inside[y][x]:
                continue
            nb_out = any(not (0 <= x + dx < d and 0 <= y + dy < d) or not inside[y + dy][x + dx]
                         for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            if nb_out:
                px[x, y] = OUT
                continue
            # 右下を陰に
            shade = (x + 0.5 - cx) + (y + 0.5 - cy) > r * 0.55
            px[x, y] = leaf_d if shade else leaf
            if deco == "needle" and (x * 7 + y * 3) % 11 == 0 and not shade:
                px[x, y] = GREEN_L
    # 照り（左上）
    for x, y in ((int(cx - r * 0.45), int(cy - r * 0.45)), (int(cx - r * 0.55), int(cy - r * 0.3))):
        if 0 <= x < d and 0 <= y < d and inside[y][x] and px[x, y] != OUT:
            px[x, y] = GREEN_L if leaf not in (SAKURA, MOMIJI) else WHITE
    # 花
    if deco == "flower":
        n = 0
        for y in range(d):
            for x in range(d):
                if inside[y][x] and px[x, y] in (leaf, leaf_d) and (x * 5 + y * 9) % 17 == 0:
                    px[x, y] = WHITE if leaf != SAKURA else SAKURA_D
                    n += 1
    _ball_cache[tier] = im
    return im


def ball_sprite(tier, k=K):
    im = draw_ball(tier)
    return im.resize((im.size[0] * k, im.size[1] * k), Image.NEAREST)


def radius_pt(tier):
    return TIERS[tier - 1][2] * K / S / 2.0


# ---------------------------------------------------------------- 器（鉢）
BOX = (16, 190, 377, 652)     # 器の外側（pt）
WALL = 9
LIMIT_Y = BOX[1] + 58          # 限界線


def inner():
    return (BOX[0] + WALL, BOX[1] + WALL, BOX[2] - WALL, BOX[3] - WALL)


def rest_y(placed, tier, x):
    ix0, iy0, ix1, iy1 = inner()
    r = radius_pt(tier)
    y = iy1 - r
    for t2, x2, y2 in placed:
        r2 = radius_pt(t2)
        dx = abs(x - x2)
        if dx < r + r2:
            y = min(y, y2 - math.sqrt((r + r2) ** 2 - dx * dx))
    return y


def stack(drops):
    """(段階, 中心 x) を順に落として積む簡易版: 真下に落としたあと、左右 ±36pt の範囲で一番低く収まる所へ転がす。
    戻り値: [(段階, cx, cy)]"""
    ix0, iy0, ix1, iy1 = inner()
    placed = []
    for tier, x in drops:
        r = radius_pt(tier)
        x = min(max(x, ix0 + r), ix1 - r)
        best = None
        for dx in range(-36, 37, 2):
            xx = x + dx
            if xx < ix0 + r or xx > ix1 - r:
                continue
            y = rest_y(placed, tier, xx)
            key = (round(y, 1), -abs(dx))
            if best is None or key > best[0]:
                best = (key, xx, y)
        placed.append((tier, best[1], best[2]))
    return placed


def draw_container(img):
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = BOX
    rrect(d, BOX, 18, fill=POT)
    rrect(d, (x0, y0, x1, y0 + 12), 6, fill=POT_L)       # 縁
    ix = inner()
    rrect(d, ix, 12, fill=(0xF7, 0xEA, 0xD2, 255))         # 中（砂）
    # 限界線（破線）
    for x in range(int(ix[0]) + 6, int(ix[2]) - 6, 14):
        d.line(((x) * S, LIMIT_Y * S, (x + 7) * S, LIMIT_Y * S), fill=M.CORAL, width=int(1.5 * S))
    text(d, (ix[2] - 8, LIMIT_Y - 9), "ここまで", 10, M.CORAL, anchor="rm")


def draw_balls(img, balls):
    """玉は器の内側で切る（あふれた玉が見出しカードに重ならないように）。"""
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    for tier, cx, cy in balls:
        paste_center(layer, ball_sprite(tier), cx, cy)
    mask = Image.new("L", img.size, 0)
    ix0, iy0, ix1, iy1 = inner()
    ImageDraw.Draw(mask).rounded_rectangle((ix0 * S, iy0 * S, ix1 * S, iy1 * S), radius=12 * S, fill=255)
    layer.putalpha(Image.composite(layer.split()[3], mask, mask))
    img.alpha_composite(layer)


def draw_burst(img, cx, cy, r, label):
    d = ImageDraw.Draw(img)
    for i in range(12):
        a = math.radians(i * 30)
        x0, y0 = cx + math.cos(a) * r * 1.05, cy + math.sin(a) * r * 1.05
        x1, y1 = cx + math.cos(a) * r * (1.45 if i % 2 else 1.3), cy + math.sin(a) * r * (1.45 if i % 2 else 1.3)
        d.line((x0 * S, y0 * S, x1 * S, y1 * S), fill=M.YELLOW, width=int(3 * S))
    text(d, (cx, cy - r * 1.5 - 14), label, 20, M.CORAL, "Heavy", anchor="mm")


# ---------------------------------------------------------------- 画面
STATES = {
    # name: (スコア, つぎ, 落とす玉, おじさんのコマ, 吹き出し)
    "normal": (1240, 2, 3, "bonsai_smile", "いい枝ぶりだ"),
    "merge": (1420, 2, 3, "celebrate_front_smile", "見事！　桜になった"),
    "over": (2180, 4, None, "disappointed_front_crying", "ああ…伸びすぎた"),
}
DROPS_NORMAL = [(8, 90), (7, 300), (6, 200), (5, 40), (4, 350), (4, 130), (3, 250), (3, 60), (2, 320), (2, 180), (1, 100), (3, 220)]
DROPS_MERGE = [(8, 90), (7, 300), (6, 200), (5, 40), (4, 350), (3, 250), (3, 60), (2, 320), (2, 180), (1, 100), (3, 220)]
# ゲームオーバー: 大きい玉が積み上がって限界線をこえた終盤
DROPS_OVER = [(8, 90), (7, 300), (8, 250), (7, 80), (6, 200), (6, 330), (7, 180), (6, 60), (6, 300), (5, 120), (5, 230),
              (5, 340), (6, 160), (5, 60), (5, 280), (4, 200), (4, 100), (4, 330), (5, 150)]


def draw_screen(state):
    score, nxt, cur, frame, bubble = STATES[state]
    img = M.new_screen()
    M.chrome(img, "盆栽おじさん（仮）")
    d = ImageDraw.Draw(img)

    # ---- 見出し（スコア・ベスト・つぎ）
    top = M.SAFE_TOP + M.NAV_H + M.PAD
    hx0, hx1 = M.PAD, M.SCREEN_W - M.PAD
    hh = 66
    card(img, (hx0, top, hx1, top + hh), M.CORNER_SMALL)
    d = ImageDraw.Draw(img)
    text(d, (hx0 + 16, top + 10), "スコア", 12, M.INK_SUB, anchor="la")
    text(d, (hx0 + 16, top + 26), f"{score}", 26, M.INK, "Heavy", anchor="la")
    text(d, (hx0 + 150, top + 10), "ベスト", 12, M.INK_SUB, anchor="la")
    text(d, (hx0 + 150, top + 30), "4860", 18, M.INK, "Bold", anchor="la")
    text(d, (hx1 - 40, top + 10 + 6), "つぎ", 12, M.INK_SUB, anchor="mm")
    paste_center(img, ball_sprite(nxt, 2), hx1 - 40, top + 44)
    d = ImageDraw.Draw(img)

    # ---- 器と玉
    draw_container(img)
    balls = stack({"normal": DROPS_NORMAL, "merge": DROPS_MERGE, "over": DROPS_OVER}[state])
    top = min(cy - radius_pt(t) for t, cx, cy in balls)
    print(f"  {state}: 玉 {len(balls)} 個・山の上端 y={top:.0f}pt（限界線 y={LIMIT_Y}pt）" + ("  ← 限界線をこえている" if top < LIMIT_Y else ""))
    draw_balls(img, balls)
    d = ImageDraw.Draw(img)
    ix = inner()
    if cur:
        cx = (ix[0] + ix[2]) / 2
        cy = ix[1] + 22
        # 落下の案内線（点線）
        for y in range(int(cy + radius_pt(cur) + 4), int(ix[3]) - 4, 10):
            d.line((cx * S, y * S, cx * S, (y + 4) * S), fill=M.blend(M.INK_SUB, (0xF7, 0xEA, 0xD2, 255), 0.5), width=S)
        paste_center(img, ball_sprite(cur), cx, cy)
        d = ImageDraw.Draw(img)
    if state == "merge":
        # 2 つの梅が合体して桜になった瞬間（新しい玉 + 光の筋）
        m = stack(DROPS_MERGE + [(5, 150)])[-1]
        draw_burst(img, m[1], m[2], radius_pt(5), "合体！ +180")
        paste_center(img, ball_sprite(5), m[1], m[2])
        d = ImageDraw.Draw(img)
    if state == "over":
        w = M.text_width("限界線をこえた！", 14) + 28
        cx = (ix[0] + ix[2]) / 2
        rrect(d, (cx - w / 2, ix[1] + 8, cx + w / 2, ix[1] + 34), 13, fill=M.FILL_CORAL)
        text(d, (cx, ix[1] + 21), "限界線をこえた！", 14, M.ON_ACCENT, "Heavy", anchor="mm")

    # ---- 下段: おじさん + 吹き出し + 進化の順
    by0 = BOX[3] + 12
    by1 = M.SCREEN_H - M.SAFE_BOTTOM - 10
    ox0, ox1 = M.PAD, M.PAD + 118
    card(img, (ox0, by0, ox1, by1), M.CORNER_SMALL)
    sp = sprite(f"{PX}/b_kimono_{frame}.png", K)
    paste_center(img, sp, (ox0 + ox1) / 2, by0 + 8 + 48 * K / S / 2)
    d = ImageDraw.Draw(img)
    text(d, ((ox0 + ox1) / 2, by1 - 14), {"normal": "ごきげん", "merge": "大喜び", "over": "がっかり"}[state], 10,
         M.INK_SUB if state == "normal" else M.CORAL, anchor="mm")

    rx0, rx1 = ox1 + 10, M.SCREEN_W - M.PAD
    # 吹き出し
    bh = 40
    card(img, (rx0, by0, rx1, by0 + bh), M.CORNER_SMALL, shadow=False)
    d = ImageDraw.Draw(img)
    d.polygon([((rx0) * S, (by0 + 14) * S), ((rx0) * S, (by0 + 28) * S), ((rx0 - 8) * S, (by0 + 21) * S)], fill=M.SURFACE)
    text(d, (rx0 + 14, by0 + bh / 2), bubble, 14, M.INK, "Bold", anchor="lm")
    # 進化の順
    ey0 = by0 + bh + 10
    card(img, (rx0, ey0, rx1, by1), M.CORNER_SMALL)
    d = ImageDraw.Draw(img)
    text(d, (rx0 + 12, ey0 + 10), "進化の順", 11, M.INK_SUB, anchor="la")
    x = rx0 + 10
    cy = (ey0 + 26 + by1) / 2
    for tier in range(1, 10):
        b = ball_sprite(tier, 1)        # 1 ドット = 0.5pt（一覧は小さく）
        w = b.size[0] / S
        paste_center(img, b, x + w / 2, cy)
        x += w + 4
    d = ImageDraw.Draw(img)

    # ---- ゲームオーバー（画面全体に重ねるカード）
    if state == "over":
        sad = sprite(f"{PX}/b_kimono_disappointed_front_crying.png", K)
        cw = M.SCREEN_W - 12 * 2
        ch = 22 + sad.size[1] / S + 10 + 30 + 10 + 20 + 10 + 24 + 10 + 44 + 22
        cx0, cy0 = 12, M.SCREEN_H / 2 - ch / 2
        card(img, (cx0, cy0, cx0 + cw, cy0 + ch), M.CORNER)
        y = cy0 + 22
        paste_center(img, sad, M.SCREEN_W / 2, y + sad.size[1] / S / 2)
        d = ImageDraw.Draw(img)
        y += sad.size[1] / S + 10
        text(d, (M.SCREEN_W / 2, y + 15), "枝が伸びすぎた！", 24, M.INK, "Heavy", anchor="mm")
        y += 30 + 10
        text(d, (M.SCREEN_W / 2, y + 10), "鉢からあふれました。また育てましょう。", 14, M.INK_SUB, "Semibold", anchor="mm")
        y += 20 + 10
        w = M.text_width("スコア ", 18) + M.text_width(f"{score}", 18)
        text_run(d, (M.SCREEN_W / 2 - w / 2, y), [("スコア ", 18, M.INK, "Bold"), (f"{score}", 18, M.INK, "Bold")])
        y += 24 + 10
        bw = M.text_width("もう一度", 17) + 28 * 2
        rrect(d, (M.SCREEN_W / 2 - bw / 2, y, M.SCREEN_W / 2 + bw / 2, y + 44), M.CORNER_SMALL, fill=M.FILL_CORAL)
        text(d, (M.SCREEN_W / 2, y + 22), "もう一度", 17, M.ON_ACCENT, anchor="mm")

    M.home_indicator(img)
    return img


def main():
    states = ["normal", "merge", "over"]
    labels = ["通常（盆栽を眺めてごきげん）", "合体で大喜び（梅 + 梅 → 桜）", "ゲームオーバーでがっかり"]
    screens = [draw_screen(s) for s in states]
    M.compose(screens, labels,
              "盆栽の合体パズル 画面モック（着物おじさん 48 ドット・盆栽の玉は仮のドット絵・1 ドット = 2pt）  iPhone 393×852pt @2x  2026-10-07",
              f"{HERE}/mock_bonsai.png")


if __name__ == "__main__":
    main()
