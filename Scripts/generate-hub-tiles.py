#!/usr/bin/env python3
"""ハブの絵タイル（#1831）を生成する。AI 不使用。ドット絵を 96x72 の格子に描き、4 倍（384x288）に拡大して書き出す。

使い方: python3 Scripts/generate-hub-tiles.py
出力:   App/Assets.xcassets/HubTiles/hubtile-<game_id>.imageset/（1 ゲーム 1 枚。名前は絵に描き込まない＝文字はアプリが出す）
"""
import json
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "App/Assets.xcassets/HubTiles")
FACES = os.path.join(ROOT, "Packages/GameKit/Sources/Core/Resources")
PUZZLE = os.path.join(ROOT, "Packages/GameKit/Sources/GameOjisanPuzzle/Resources")
W, H, SCALE = 96, 72, 4

WHITE = (255, 255, 255)
INK = (40, 40, 52)
RED = (220, 60, 60)
GREEN = (60, 150, 90)
FELT = (46, 125, 82)
WOOD = (214, 170, 110)
YELLOW = (250, 210, 80)
GRAY = (200, 200, 208)

# 3x5 のドット数字
FONT = {
    "0": "111101101101111", "1": "010110010010111", "2": "111001111100111", "3": "111001111001111",
    "4": "101101111001001", "5": "111100111001111", "6": "111100111101111", "7": "111001001001001",
    "8": "111101111101111", "9": "111101111001111", "+": "000010111010000", "=": "000111000111000",
    "A": "010101111101101", "K": "101101110101101", "x": "000101010101000",
}


def text(d, x, y, s, color=INK, k=1):
    for ch in s:
        bits = FONT[ch]
        for i, b in enumerate(bits):
            if b == "1":
                px, py = x + (i % 3) * k, y + (i // 3) * k
                d.rectangle([px, py, px + k - 1, py + k - 1], fill=color)
        x += 4 * k


def text_width(s, k=1):
    return len(s) * 4 * k - k


SUITS = {
    "h": ("0110110111111111111001100110000", RED),
    "d": ("00100001110111111111011100010000", RED),
}
HEART = ["0110110", "1111111", "1111111", "0111110", "0011100", "0001000"]
DIAMOND = ["0001000", "0011100", "0111110", "1111111", "0111110", "0011100", "0001000"]
SPADE = ["0001000", "0011100", "0111110", "1111111", "1111111", "0001000", "0011100"]
CLUB = ["0011100", "0011100", "1101011", "1111111", "1101011", "0001000", "0011100"]
SUIT_ART = {"h": (HEART, RED), "d": (DIAMOND, RED), "s": (SPADE, INK), "c": (CLUB, INK)}


def blit(d, x, y, rows, color):
    for j, row in enumerate(rows):
        for i, ch in enumerate(row):
            if ch == "1":
                d.point((x + i, y + j), fill=color)


def card(d, x, y, suit=None, label=None, back=False, w=20, h=28):
    d.rectangle([x, y, x + w - 1, y + h - 1], fill=WHITE, outline=INK)
    if back:
        d.rectangle([x + 2, y + 2, x + w - 3, y + h - 3], fill=(70, 110, 200), outline=WHITE)
        for i in range(x + 4, x + w - 4, 3):
            d.line([i, y + 4, i, y + h - 5], fill=(120, 160, 240))
        return
    if label:
        text(d, x + 2, y + 2, label, INK)
    if suit:
        art, color = SUIT_ART[suit]
        blit(d, x + (w - 7) // 2, y + h // 2 - 1, art, color)


def disc(d, cx, cy, r, color, outline=INK):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color, outline=outline)


def face(img, name, size, pos, folder=FACES):
    f = Image.open(os.path.join(folder, name)).convert("RGBA")
    f = f.resize(size, Image.LANCZOS)
    img.alpha_composite(f, pos)


def new(bg):
    img = Image.new("RGBA", (W, H), bg + (255,))
    return img, ImageDraw.Draw(img)


def grid(d, x, y, n, cell, color):
    for i in range(n + 1):
        d.line([x, y + i * cell, x + n * cell, y + i * cell], fill=color)
        d.line([x + i * cell, y, x + i * cell, y + n * cell], fill=color)


def tetro(d, x, y, cells, color, c=6):
    for (i, j) in cells:
        d.rectangle([x + i * c, y + j * c, x + i * c + c - 1, y + j * c + c - 1], fill=color, outline=INK)


# ---- 各ゲーム ----
def poker():
    img, d = new((70, 120, 90))
    for i, (s, l) in enumerate([("s", "A"), ("h", "K"), ("d", "A"), ("c", "K"), ("h", "A")]):
        card(d, 12 + i * 15, 20 + abs(i - 2) * 3, s, l)
    return img


def solitaire():
    img, d = new(FELT)
    for col in range(4):
        for k in range(col + 1):
            card(d, 8 + col * 22, 8 + k * 6, "s" if col % 2 else "c", str(col + 2), back=(k < col), w=18, h=26)
    card(d, 8 + 3 * 22, 8 + 3 * 6, "h", "7", w=18, h=26)
    return img


def runner():
    img, d = new((120, 200, 240))
    d.rectangle([0, 56, W, H], fill=(110, 170, 90))
    d.rectangle([0, 56, W, 58], fill=(70, 130, 60))
    for x in range(4, 90, 22):
        d.rectangle([x, 62, x + 8, 63], fill=(90, 150, 70))
    face(img, "OjisanFace_cheer.png", (38, 36), (26, 18))
    for i in range(3):
        d.line([8, 36 + i * 5, 20 - i * 3, 36 + i * 5], fill=WHITE)
    d.rectangle([66, 44, 74, 56], fill=(140, 90, 50), outline=INK)
    return img


def mahjong():
    img, d = new((60, 130, 110))
    for i in range(4):
        x = 8 + i * 20
        d.rectangle([x, 14, x + 17, 44], fill=(250, 240, 200), outline=INK)
        d.rectangle([x, 38, x + 17, 44], fill=GREEN)
        if i % 2 == 0:
            disc(d, x + 9, 25, 5, RED)
            disc(d, x + 9, 25, 2, WHITE)
        else:
            d.line([x + 9, 17, x + 9, 34], fill=GREEN)
            d.rectangle([x + 5, 20, x + 13, 22], fill=GREEN)
            d.rectangle([x + 5, 28, x + 13, 30], fill=GREEN)
    d.rectangle([14, 50, 82, 64], fill=(250, 240, 200), outline=INK)
    for i in range(6):
        d.rectangle([14 + i * 11, 50, 14 + i * 11 + 11, 64], outline=INK)
    return img


def sudoku():
    img, d = new((235, 240, 250))
    grid(d, 18, 6, 9, 6, GRAY)
    for i in range(0, 10, 3):
        d.line([18, 6 + i * 6, 72, 6 + i * 6], fill=INK)
        d.line([18 + i * 6, 6, 18 + i * 6, 60], fill=INK)
    for (i, j, n) in [(0, 0, "5"), (4, 1, "3"), (7, 2, "7"), (2, 4, "9"), (5, 5, "1"), (8, 7, "4"), (1, 8, "6"), (6, 8, "2")]:
        text(d, 19 + i * 6 + 1, 7 + j * 6, n, INK)
    return img


def othello():
    img, d = new(FELT)
    d.rectangle([14, 4, 82, 68], fill=(30, 105, 70))
    grid(d, 18, 6, 8, 8, (20, 80, 55))
    for (i, j, c) in [(3, 3, WHITE), (4, 3, INK), (3, 4, INK), (4, 4, WHITE), (5, 4, INK), (2, 3, INK)]:
        disc(d, 18 + i * 8 + 4, 6 + j * 8 + 4, 3, c)
    return img


def game2048():
    img, d = new((250, 235, 205))
    cols = {"2": (238, 228, 218), "4": (237, 224, 200), "8": (242, 177, 121), "16": (245, 149, 99), "32": (246, 124, 95)}
    pos = [(8, 6, "2"), (36, 6, "4"), (64, 6, "8"), (8, 36, "8"), (36, 36, "16"), (64, 36, "32")]
    for (x, y, n) in pos:
        d.rectangle([x, y, x + 24, y + 26], fill=cols[n], outline=(187, 173, 160))
        text(d, x + 12 - text_width(n, 2) // 2, y + 8, n, INK if int(n) < 8 else WHITE, 2)
    return img


def shogi():
    img, d = new(WOOD)
    grid(d, 6, 4, 8, 8, (130, 90, 50))
    # 駒（五角形）
    pts = [(48, 10), (66, 18), (72, 60), (24, 60), (30, 18)]
    d.polygon(pts, fill=(250, 235, 180), outline=INK)
    # 「王」の字
    d.line([38, 28, 58, 28], fill=INK, width=2)
    d.line([38, 38, 58, 38], fill=INK, width=2)
    d.line([38, 48, 58, 48], fill=INK, width=2)
    d.line([48, 28, 48, 50], fill=INK, width=2)
    return img


def shiritori():
    img, d = new((255, 225, 235))
    for i in range(3):
        x = 6 + i * 30
        d.rectangle([x, 22, x + 22, 52], fill=WHITE, outline=INK)
        d.rectangle([x + 3, 26, x + 19, 36], fill=(255, 190, 90))
        d.line([x + 4, 42, x + 18, 42], fill=GRAY)
        d.line([x + 4, 46, x + 14, 46], fill=GRAY)
        if i < 2:
            d.polygon([(x + 24, 34), (x + 29, 37), (x + 24, 40)], fill=RED)
    return img


def daifugo():
    img, d = new((120, 70, 150))
    d.polygon([(22, 20), (30, 8), (38, 18), (48, 6), (58, 18), (66, 8), (74, 20)], fill=YELLOW, outline=INK)
    d.rectangle([22, 20, 74, 26], fill=YELLOW, outline=INK)
    for i, l in enumerate(["K", "A", "K"]):
        card(d, 18 + i * 22, 34, ["s", "h", "c"][i], l, w=20, h=30)
    return img


def gomoku():
    img, d = new(WOOD)
    grid(d, 8, 4, 8, 8, (120, 80, 40))
    for (i, j, c) in [(2, 2, INK), (3, 3, WHITE), (4, 4, INK), (5, 5, WHITE), (3, 2, INK), (4, 3, WHITE), (2, 4, INK), (5, 4, WHITE)]:
        disc(d, 8 + i * 8, 4 + j * 8, 3, c)
    return img


def minesweeper():
    img, d = new((210, 215, 225))
    grid(d, 16, 6, 6, 10, (130, 135, 150))
    for j in range(6):
        for i in range(6):
            d.rectangle([16 + i * 10 + 1, 6 + j * 10 + 1, 16 + i * 10 + 9, 6 + j * 10 + 9], fill=(235, 238, 245))
    for (i, j, n, c) in [(1, 1, "1", (50, 90, 220)), (2, 1, "2", GREEN), (3, 2, "3", RED), (4, 4, "1", (50, 90, 220))]:
        text(d, 16 + i * 10 + 4, 6 + j * 10 + 3, n, c)
    # 旗
    d.line([16 + 20 + 4, 6 + 30 + 2, 16 + 20 + 4, 6 + 30 + 8], fill=INK)
    d.polygon([(16 + 24, 6 + 32), (16 + 29, 6 + 34), (16 + 24, 6 + 36)], fill=RED)
    disc(d, 16 + 40 + 5, 6 + 10 + 5, 3, INK)
    return img


def spider():
    img, d = new((70, 70, 90))
    cx, cy = 48, 34
    for dx, dy in [(-22, -16), (-26, -4), (-26, 8), (-20, 18), (22, -16), (26, -4), (26, 8), (20, 18)]:
        d.line([cx, cy, cx + dx // 2, cy + dy // 2 - 6, cx + dx, cy + dy], fill=INK if False else (230, 230, 240), width=2)
    disc(d, cx, cy, 10, (30, 30, 40), outline=(230, 230, 240))
    disc(d, cx, cy - 12, 5, (30, 30, 40), outline=(230, 230, 240))
    d.point((cx - 2, cy - 13), fill=RED)
    d.point((cx + 2, cy - 13), fill=RED)
    card(d, 4, 40, "s", "A", w=14, h=22)
    card(d, 78, 40, "h", "K", w=14, h=22)
    return img


def blackjack():
    img, d = new(FELT)
    card(d, 12, 14, "s", "A", w=24, h=34)
    card(d, 30, 20, "h", "K", w=24, h=34)
    disc(d, 70, 48, 14, RED, outline=WHITE)
    disc(d, 70, 48, 9, RED, outline=WHITE)
    text(d, 66, 44, "21", WHITE) if False else text(d, 64, 45, "21", WHITE)
    return img


def mahjong_solitaire():
    img, d = new((70, 90, 150))
    for (x, y) in [(10, 30), (28, 30), (46, 30), (64, 30), (19, 20), (37, 20), (55, 20), (28, 10), (46, 10)]:
        d.rectangle([x, y, x + 15, y + 22], fill=(250, 240, 200), outline=INK)
        d.rectangle([x + 2, y + 2, x + 13, y + 20], outline=GREEN)
        disc(d, x + 8, y + 11, 3, RED if (x + y) % 2 else GREEN)
    return img


def hanafuda():
    img, d = new((210, 70, 80))
    for i, (bg, mark) in enumerate([((250, 235, 210), "sun"), ((250, 235, 210), "pine"), ((40, 40, 50), "moon")]):
        x = 10 + i * 28
        d.rectangle([x, 12, x + 22, 56], fill=bg, outline=INK)
        if mark == "sun":
            disc(d, x + 11, 30, 8, RED, outline=RED)
            d.rectangle([x + 2, 44, x + 20, 50], fill=(30, 30, 40))
        elif mark == "pine":
            d.polygon([(x + 11, 16), (x + 4, 30), (x + 18, 30)], fill=GREEN)
            d.polygon([(x + 11, 26), (x + 2, 42), (x + 20, 42)], fill=GREEN)
            d.rectangle([x + 9, 42, x + 13, 50], fill=(120, 80, 40))
        else:
            disc(d, x + 11, 28, 8, YELLOW, outline=YELLOW)
            d.rectangle([x + 2, 40, x + 20, 52], fill=(90, 90, 110))
    return img


def go():
    img, d = new(WOOD)
    grid(d, 6, 4, 8, 8, (120, 80, 40))
    for (i, j, c) in [(2, 2, INK), (3, 2, WHITE), (3, 3, INK), (4, 3, WHITE), (2, 4, WHITE), (5, 5, INK), (6, 2, INK), (6, 5, WHITE), (4, 6, INK), (1, 5, INK), (3, 5, WHITE)]:
        disc(d, 6 + i * 8, 4 + j * 8, 3, c)
    return img


def blocks():
    img, d = new((30, 40, 80))
    grid(d, 30, 4, 10, 6, (50, 62, 110)) if False else None
    d.rectangle([28, 4, 68, 68], outline=(90, 110, 190))
    tetro(d, 34, 14, [(0, 0), (1, 0), (2, 0), (1, 1)], (180, 90, 220))
    tetro(d, 46, 26, [(0, 0), (0, 1), (1, 1), (1, 2)], (90, 200, 120))
    tetro(d, 28 + 2, 50, [(0, 0), (1, 0), (2, 0), (3, 0)], (80, 200, 240))
    tetro(d, 50, 50, [(0, 0), (1, 0), (0, 1), (1, 1)], YELLOW)
    tetro(d, 56, 38, [(0, 0), (0, 1), (1, 1), (2, 1)], (240, 140, 60))
    return img


def concentration():
    img, d = new((255, 230, 190))
    for j in range(2):
        for i in range(4):
            x, y = 8 + i * 20, 8 + j * 30
            if (i, j) in [(1, 0), (2, 1)]:
                card(d, x, y, "h", "7", w=16, h=24)
            else:
                card(d, x, y, back=True, w=16, h=24)
    return img


def chess():
    img, d = new((235, 225, 205))
    for j in range(8):
        for i in range(12):
            if (i + j) % 2:
                d.rectangle([i * 8, j * 9, i * 8 + 7, j * 9 + 8], fill=(120, 150, 110))
    # ポーン
    disc(d, 48, 22, 8, INK, outline=WHITE)
    d.polygon([(40, 52), (44, 32), (52, 32), (56, 52)], fill=INK, outline=WHITE)
    d.rectangle([34, 52, 62, 58], fill=INK, outline=WHITE)
    d.rectangle([40, 30, 56, 34], fill=INK, outline=WHITE)
    return img


def freecell():
    img, d = new(FELT)
    for i in range(4):
        d.rectangle([6 + i * 12, 6, 6 + i * 12 + 10, 20], outline=(150, 210, 170))
    for i in range(4):
        card(d, 54 + (i % 2) * 20 - 6, 6 + (i // 2) * 0, None, None) if False else None
    for i, (s, l) in enumerate([("s", "A"), ("h", "2"), ("c", "3"), ("d", "4")]):
        card(d, 10 + i * 20, 30 + i * 3, s, l, w=18, h=26)
    d.rectangle([60, 6, 90, 20], outline=(150, 210, 170))
    return img


def fifteen():
    img, d = new((225, 235, 250))
    n = 1
    for j in range(4):
        for i in range(4):
            if (i, j) == (3, 3):
                continue
            x, y = 16 + i * 16, 4 + j * 16
            d.rectangle([x, y, x + 14, y + 14], fill=(90, 150, 230), outline=INK)
            s = str(n)
            text(d, x + 7 - text_width(s) // 2, y + 5, s, WHITE)
            n += 1
    return img


def homerun():
    img, d = new((130, 200, 245))
    d.rectangle([0, 52, W, H], fill=(110, 170, 90))
    d.rectangle([0, 46, W, 52], fill=(40, 100, 60))
    face(img, "OjisanFace_cheer.png", (34, 32), (12, 20))
    d.line([54, 56, 80, 28], fill=(190, 140, 80), width=3)
    disc(d, 80, 14, 5, WHITE)
    d.arc([76, 10, 84, 18], 200, 340, fill=RED)
    return img


def ojisanpuzzle():
    img, d = new((235, 215, 175))
    d.rectangle([0, 56, W, H], fill=(170, 140, 100))
    face(img, "OjisanFace_smile.png", (34, 32), (10, 22))
    for i, name in enumerate(["OjisanLuggage_5_beercase.png", "OjisanLuggage_3_coolerbox.png", "OjisanLuggage_2_suika.png"]):
        box = Image.open(os.path.join(PUZZLE, name)).convert("RGBA").resize((22, 22), Image.NEAREST)
        img.alpha_composite(box, (46 + (i % 2) * 22, 34 - i * 4 + (0 if i < 2 else -12)))
        if i == 1:
            pass
    return img


def anzan():
    img, d = new((255, 240, 200))
    d.rectangle([8, 10, 88, 62], fill=(30, 40, 60), outline=INK)
    text(d, 16, 20, "7+3", (120, 255, 160), 4)
    text(d, 56, 44, "=", (120, 255, 160), 2) if False else None
    text(d, 16, 44, "=", (120, 255, 160), 2)
    return img


GAMES = {
    "poker": poker, "solitaire": solitaire, "runner": runner, "mahjong4": mahjong, "sudoku": sudoku,
    "othello": othello, "2048": game2048, "shogi": shogi, "shiritori": shiritori, "daifugo": daifugo,
    "gomoku": gomoku, "minesweeper": minesweeper, "spider": spider, "blackjack": blackjack,
    "mahjong": mahjong_solitaire, "hanafuda": hanafuda, "go": go, "blocks": blocks,
    "concentration": concentration, "chess": chess, "freecell": freecell, "fifteen": fifteen,
    "homerun": homerun, "ojisanpuzzle": ojisanpuzzle, "anzan": anzan,
}


def main():
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}, "properties": {"provides-namespace": False}}, f, indent=2)
    for gid, fn in GAMES.items():
        img = fn().resize((W * SCALE, H * SCALE), Image.NEAREST)
        folder = os.path.join(OUT, f"hubtile-{gid}.imageset")
        os.makedirs(folder, exist_ok=True)
        png = f"hubtile-{gid}.png"
        img.convert("RGB").save(os.path.join(folder, png), optimize=True)
        with open(os.path.join(folder, "Contents.json"), "w") as f:
            json.dump({"images": [{"filename": png, "idiom": "universal"}], "info": {"author": "xcode", "version": 1}}, f, indent=2)
    # 目視確認用の一覧
    sheet = Image.new("RGB", (5 * 200, 5 * 150), WHITE)
    for k, gid in enumerate(GAMES):
        t = Image.open(os.path.join(OUT, f"hubtile-{gid}.imageset", f"hubtile-{gid}.png")).resize((192, 144))
        sheet.paste(t, ((k % 5) * 200 + 4, (k // 5) * 150 + 3))
    sheet_path = os.environ.get("HUB_TILES_SHEET")
    if sheet_path:
        sheet.save(sheet_path)


if __name__ == "__main__":
    main()
