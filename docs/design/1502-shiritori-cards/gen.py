#!/usr/bin/python3
"""絵札ドット絵（40×40）の生成器（#1502・新規 20 種）。

既存 30 種（ObjectCardArt.swift）と同じ描き方:
  図形（楕円・矩形・多角形・線）を部品ごとに Layer へ描き、Layer 単位で 4 近傍の縁取り K を付けて
  台紙に重ねる（部品の境目に 1 ドットの線が入る）。影は「暗い色の楕円を塗ってから内側を元色で戻す三日月」、
  目には 1 ドットの白い光。
出力: sprites_new.json（キー=識別子、値={"rows":[...], "palette":{文字:"RRGGBB"}}）
"""
import json, math
from PIL import Image, ImageDraw

import os
OUT = os.path.dirname(os.path.abspath(__file__))
N = 40
K = "3A2A2A"          # 縁取り（既存と同じ）

# 既存パレットから拾った共通色
INK = "2B2B33"; WHITE = "FFFFFF"; CREAM = "F7E8C8"; GRAY = "D8DDE3"; GRAY_D = "9AA3AD"; GRAY_DD = "7F8994"
RED = "E24A3C"; RED_D = "B8322A"; RED_L = "FF9C8C"
BLUE = "5FB0E0"; BLUE_D = "3596D4"; BLUE_L = "BFE3F5"; BLUE_LL = "E4F3FB"; BLUE_M = "9CD3F2"; SEA = "4AA8E0"
GREEN = "39A85B"; GREEN_D = "2C7F44"; GREEN_L = "8DD16B"; GREEN_LL = "B6E68C"
BROWN = "6B4423"; BROWN_L = "9A6A3A"; TAN = "D9B382"; TAN_L = "EBD6A8"; SAND = "E3D2AC"; SAND_L = "F6E7C8"
YELLOW = "F2C230"; YELLOW_L = "FFF2A8"; YELLOW_D = "E0B030"; GOLD = "D9A05B"; ORANGE = "F08A2E"
PINK = "F4A6B7"; PINK_D = "E06C8B"; PINK_L = "FFD1DC"; SKIN = "F3D9B1"
CHOCO = "5C3612"; CHOCO_L = "7A4B1F"; RUST = "B5651D"; RUST_L = "C98B4A"
PURPLE = "5A3187"; PURPLE_D = "3E1F63"; PURPLE_L = "8C63BE"


class Layer:
    """部品 1 つ分の格子。(x, y) -> "RRGGBB"。"""

    def __init__(self):
        self.p = {}

    # ---- 基本図形 ----
    def _paint(self, x, y, col, clip, where):
        if not (0 <= x < N and 0 <= y < N):
            return
        if clip and (x, y) not in self.p:
            return
        if where and not where(x, y):
            return
        self.p[(x, y)] = col

    def ellipse(self, cx, cy, rx, ry, col, angle=0, clip=False, where=None):
        a = math.radians(angle); ca, sa = math.cos(a), math.sin(a)
        r = int(max(rx, ry)) + 2
        for y in range(int(cy - r), int(cy + r) + 2):
            for x in range(int(cx - r), int(cx + r) + 2):
                dx, dy = x - cx, y - cy
                u = dx * ca + dy * sa; v = -dx * sa + dy * ca
                if (u * u) / (rx * rx) + (v * v) / (ry * ry) <= 1.0:
                    self._paint(x, y, col, clip, where)
        return self

    def egg(self, cx, cy, rx, ry, col, taper=0.25, clip=False, where=None):
        """上がすぼまった卵形（y が小さいほど横幅を絞る）。"""
        for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
            t = (y - cy) / ry
            if abs(t) > 1:
                continue
            w = rx * math.sqrt(1 - t * t) * (1 - taper * max(0.0, -t))
            for x in range(int(cx - w) - 1, int(cx + w) + 2):
                if abs(x - cx) <= w:
                    self._paint(x, y, col, clip, where)
        return self

    def rect(self, x0, y0, x1, y1, col, clip=False, where=None):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self._paint(x, y, col, clip, where)
        return self

    def _pil(self, fn):
        im = Image.new("L", (N, N), 0)
        fn(ImageDraw.Draw(im))
        px = im.load()
        return [(x, y) for y in range(N) for x in range(N) if px[x, y]]

    def poly(self, pts, col, clip=False, where=None):
        for x, y in self._pil(lambda d: d.polygon(pts, fill=255, outline=255)):
            self._paint(x, y, col, clip, where)
        return self

    def line(self, x0, y0, x1, y1, col, width=1, clip=False, where=None):
        for x, y in self._pil(lambda d: d.line([(x0, y0), (x1, y1)], fill=255, width=width)):
            self._paint(x, y, col, clip, where)
        return self

    def dot(self, x, y, col):
        self._paint(x, y, col, False, None); return self

    def dots(self, pts, col):
        for x, y in pts:
            self.dot(x, y, col)
        return self

    def shade(self, cx, cy, rx, ry, dark, base, dx, dy, angle=0, where=None):
        """三日月の影: 暗色の楕円を塗り、(dx, dy) ずらした同じ楕円を元色で戻す（既に塗ってある所だけ）。"""
        self.ellipse(cx, cy, rx, ry, dark, angle=angle, clip=True, where=where)
        self.ellipse(cx + dx, cy + dy, rx, ry, base, angle=angle, clip=True, where=where)
        return self

    def erase(self, cx, cy, rx, ry, angle=0, where=None):
        a = math.radians(angle); ca, sa = math.cos(a), math.sin(a)
        for (x, y) in list(self.p):
            dx, dy = x - cx, y - cy
            u = dx * ca + dy * sa; v = -dx * sa + dy * ca
            if (u * u) / (rx * rx) + (v * v) / (ry * ry) <= 1.0 and (where is None or where(x, y)):
                del self.p[(x, y)]
        return self

    def keep(self, where):
        for (x, y) in list(self.p):
            if not where(x, y):
                del self.p[(x, y)]
        return self

    def star4(self, cx, cy, r, col):
        """4 方向のきらめき（十字）。"""
        for i in range(-r, r + 1):
            self.dot(cx + i, cy, col); self.dot(cx, cy + i, col)
        return self


def compose(parts):
    """parts: [(Layer, outline: bool)] を順に重ねる。"""
    g = [[None] * N for _ in range(N)]
    for layer, outline in parts:
        if outline:
            for (x, y) in layer.p:
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < N and 0 <= ny < N and (nx, ny) not in layer.p:
                        g[ny][nx] = K
        for (x, y), c in layer.p.items():
            g[y][x] = c
    return g


def to_sprite(g):
    pal = {"K": K}; keys = {K: "K"}
    letters = iter("abcdefghijklmnopqrstuvwxyz")
    rows = []
    for row in g:
        s = ""
        for c in row:
            if c is None:
                s += "."
            else:
                if c not in keys:
                    k = next(letters); keys[c] = k; pal[k] = c
                s += keys[c]
        rows.append(s)
    return {"rows": rows, "palette": pal}


def eye(layer_ink, layer_light, x, y):
    layer_ink.dot(x, y, INK); layer_ink.dot(x + 1, y, INK); layer_ink.dot(x, y + 1, INK); layer_ink.dot(x + 1, y + 1, INK)
    layer_light.dot(x, y, WHITE)


# ============ 20 種 ============

def swim_ring():
    # 赤白の縞の浮き輪。輪の外径 34・穴径 15。縞は別レイヤにして境目に線を入れる
    cx = cy = 19.5
    white = Layer().ellipse(cx, cy, 17, 17, WHITE)
    white.shade(cx, cy, 17, 17, GRAY, WHITE, -2, -2)
    red = Layer()
    for (x, y) in list(white.p):
        ang = math.degrees(math.atan2(y - cy, x - cx)) % 360
        if int(ang // 45) % 2 == 0:
            red.dot(x, y, RED)
    red.shade(cx, cy, 17, 17, RED_D, RED, -2, -2)
    white.erase(cx, cy, 7.5, 7.5); red.erase(cx, cy, 7.5, 7.5)
    for (x, y) in list(red.p):
        del white.p[(x, y)]
    hi = Layer().dots([(8, 10), (9, 9), (10, 8), (7, 12)], RED_L)     # 左上の赤い区画に光
    return [(white, True), (red, True), (hi, False)]


def umbrella():
    apex = (19.5, 6); base_y = 22
    bounds = [10.5, 19.5, 28.5]
    angs = [math.pi] + [math.atan2(base_y - apex[1], bx - apex[0]) for bx in bounds] + [0.0]
    canopy = {}
    tmp = Layer().ellipse(19.5, base_y, 18, 16, RED, where=lambda x, y: y <= base_y)
    for cxs, i in zip([6, 15, 24, 33], range(4)):
        tmp.ellipse(cxs, base_y, 4.5, 3.2, RED)                         # 裾の波（スカラップ）
    red, cream = Layer(), Layer()
    for (x, y) in tmp.p:
        a = math.atan2(y - apex[1], x - apex[0])
        # 裾の波は角度でなく x で区画を決める
        if y > base_y:
            i = min(3, max(0, int((x - 1.5) // 9)))
        else:
            i = 3
            for j in range(4):
                if angs[j + 1] >= a >= angs[j] or angs[j] >= a >= angs[j + 1]:
                    i = j; break
        (red if i % 2 == 0 else cream).dot(x, y, RED if i % 2 == 0 else CREAM)
    red.shade(19.5, base_y, 18, 16, RED_D, RED, -3, -3)
    cream.shade(19.5, base_y, 18, 16, TAN, CREAM, -3, -3)
    tip = Layer().rect(19, 2, 20, 5, GRAY_D)
    shaft = Layer().rect(19, 23, 20, 33, BROWN)
    hook = Layer().ellipse(15.5, 32.5, 5, 4.5, BROWN).erase(15.5, 32.5, 3, 2.5).keep(lambda x, y: y >= 33)
    hi = Layer().dots([(11, 12), (12, 11), (13, 10), (10, 14)], RED_L)
    return [(tip, True), (shaft, True), (hook, True), (cream, True), (red, True), (hi, False)]


def fish():
    tail = Layer().poly([(8, 20), (1, 11), (4, 20), (1, 29)], BLUE_D)
    dorsal = Layer().poly([(12, 14), (20, 5), (27, 12)], BLUE_D)
    anal = Layer().poly([(14, 27), (18, 34), (24, 28)], BLUE_D)
    body = Layer().ellipse(19, 20.5, 14.5, 8.5, BLUE)
    body.ellipse(20, 26, 12, 5, BLUE_L, clip=True)                     # 腹
    body.shade(19, 20.5, 14.5, 8.5, BLUE_D, BLUE, -1, -2, where=lambda x, y: y < 22)
    scales = Layer().dots([(13, 18), (16, 16), (19, 18), (22, 16), (16, 21), (19, 23), (22, 21), (25, 20), (13, 22)], BLUE_D)
    gill = Layer().line(28, 15, 26, 24, BLUE_D, width=1)
    fin = Layer().ellipse(20, 23.5, 4.5, 2.5, BLUE_D, angle=25)
    eyeW = Layer().ellipse(29, 18, 2.5, 2.5, WHITE)
    ink = Layer(); light = Layer()
    ink.rect(29, 17, 30, 18, INK); light.dot(29, 17, WHITE)
    mouth = Layer().line(32, 22, 34, 22, INK)
    hi = Layer().dots([(10, 15), (11, 14), (12, 13)], BLUE_L)
    return [(tail, True), (dorsal, True), (anal, True), (body, True), (scales, False), (gill, False), (fin, True),
            (eyeW, True), (ink, False), (light, False), (mouth, False), (hi, False)]


def eggplant():
    body = Layer().ellipse(22, 23, 9, 15.5, PURPLE, angle=-38)
    body.ellipse(26.5, 28.5, 9.5, 8.5, PURPLE)
    body.shade(22, 23, 9, 15.5, PURPLE_D, PURPLE, -3, -3, angle=-38)
    body.ellipse(26.5, 28.5, 9.5, 8.5, PURPLE_D, clip=True, where=lambda x, y: (x - 29) + (y - 31) > 4)
    stem = Layer().line(13, 9, 7, 3, GREEN_D, width=3)
    calyx = Layer().poly([(6, 8), (13, 5), (20, 9), (22, 15), (18, 16), (16, 21), (12, 17), (8, 18), (7, 12)], GREEN)
    calyx.shade(13, 12, 8, 7, GREEN_D, GREEN, -2, -2)
    hi = Layer().dots([(24, 13), (25, 15), (26, 17), (26, 19), (23, 12)], PURPLE_L)
    return [(stem, True), (body, True), (calyx, True), (hi, False)]


def fox():
    earL = Layer().poly([(3, 22), (5, 3), (17, 13)], ORANGE)
    earR = Layer().poly([(36, 22), (34, 3), (22, 13)], ORANGE)
    innerL = Layer().poly([(6, 18), (7, 8), (14, 14)], PINK)
    innerR = Layer().poly([(33, 18), (32, 8), (25, 14)], PINK)
    head = Layer().ellipse(19.5, 23, 16, 12, ORANGE)
    head.shade(19.5, 23, 16, 12, RUST, ORANGE, -2, -3)
    cheeks = Layer().ellipse(10.5, 28, 7, 5.5, WHITE).ellipse(28.5, 28, 7, 5.5, WHITE).ellipse(19.5, 29.5, 9, 5.5, WHITE)
    cheeks.shade(19.5, 29, 16, 6, GRAY, WHITE, -1, -2)
    ink = Layer(); light = Layer()
    ink.line(11, 17, 15, 21, INK, width=2); ink.line(28, 17, 24, 21, INK, width=2)   # つり目
    light.dot(14, 20, WHITE); light.dot(25, 20, WHITE)
    nose = Layer().ellipse(19.5, 31, 2, 1.5, INK)
    hi = Layer().dots([(8, 17), (9, 16), (10, 15), (7, 19)], "FFB56B")
    return [(earL, True), (earR, True), (innerL, False), (innerR, False), (head, True), (cheeks, True),
            (hi, False), (ink, False), (light, False), (nose, True)]


def whale():
    tail = Layer().poly([(29, 21), (35, 12), (38, 14), (35, 21), (38, 29), (35, 31), (29, 26)], SEA)
    body = Layer().ellipse(17, 24, 15.5, 10.5, SEA)
    body.ellipse(14, 30, 13, 5.5, BLUE_L, clip=True)
    body.shade(17, 24, 15.5, 10.5, BLUE_D, SEA, -2, -3, where=lambda x, y: y < 27)
    spout = Layer().line(9, 12, 5, 4, BLUE_L, width=2).line(10, 12, 13, 4, BLUE_L, width=2)
    spout.ellipse(4.5, 3, 2, 1.5, BLUE_L).ellipse(13.5, 3, 2, 1.5, BLUE_L)
    eyeW = Layer().ellipse(7.5, 21, 2.5, 2.5, WHITE)
    ink = Layer().rect(7, 20, 8, 21, INK); light = Layer().dot(7, 20, WHITE)
    mouth = Layer().line(2, 27, 12, 28, INK)
    fin = Layer().ellipse(16, 30, 5, 2.5, BLUE_D, angle=20)
    hi = Layer().dots([(9, 16), (10, 15), (11, 14), (8, 18)], BLUE_M)
    return [(spout, True), (tail, True), (body, True), (fin, True), (eyeW, True), (ink, False), (light, False),
            (mouth, False), (hi, False)]


def ice():
    puddle = Layer().ellipse(19.5, 34, 15, 3, BLUE_L)
    block = Layer().poly([(8, 13), (19, 5), (31, 8), (35, 19), (31, 32), (16, 34), (5, 26)], BLUE_LL)
    facetR = Layer().poly([(19, 5), (31, 8), (35, 19), (31, 32), (24, 22), (22, 12)], BLUE_M)
    facetB = Layer().poly([(5, 26), (12, 20), (24, 22), (31, 32), (16, 34)], BLUE_L)
    edges = Layer().line(19, 5, 22, 12, BLUE).line(22, 12, 24, 22, BLUE).line(24, 22, 31, 32, BLUE)
    edges.line(8, 13, 12, 20, BLUE).line(12, 20, 24, 22, BLUE).line(5, 26, 12, 20, BLUE)
    shine = Layer().line(12, 11, 16, 8, WHITE, width=2).line(9, 16, 11, 14, WHITE, width=2)
    sparkA = Layer().star4(34, 5, 3, WHITE).dot(33, 4, WHITE).dot(35, 4, WHITE).dot(33, 6, WHITE).dot(35, 6, WHITE)
    sparkB = Layer().star4(4, 8, 2, WHITE)
    sparkC = Layer().star4(36, 28, 2, WHITE)
    return [(puddle, True), (block, True), (facetR, False), (facetB, False), (edges, False), (shine, False),
            (sparkA, True), (sparkB, True), (sparkC, True)]


def zebra():
    neck = Layer().poly([(18, 11), (33, 9), (37, 37), (16, 37)], WHITE)
    mane = Layer().poly([(17, 9), (21, 5), (25, 7), (29, 5), (33, 7), (36, 10), (37, 22), (33, 20), (31, 12), (27, 10), (23, 11), (19, 13)], INK)
    head = Layer().ellipse(15, 18, 11, 10, WHITE)
    muzzle = Layer().ellipse(8.5, 27, 7.5, 5.5, GRAY)
    earL = Layer().poly([(11, 9), (9, 2), (16, 7)], WHITE)
    earR = Layer().poly([(19, 8), (21, 2), (24, 8)], WHITE)
    stripes = Layer()
    for (x0, y0, x1, y1) in [(24, 13, 21, 37), (30, 13, 27, 37), (35, 23, 33, 37), (12, 9, 8, 15), (17, 8, 14, 14),
                             (8, 17, 5, 22), (13, 21, 10, 25), (20, 15, 18, 22), (23, 21, 20, 26)]:
        stripes.line(x0, y0, x1, y1, INK, width=2)
    stripes.keep(lambda x, y: (x, y) in neck.p or (x, y) in head.p)
    for (x, y) in list(stripes.p):                                                 # 顔の縞は目の周りを空ける
        if (x - 11) ** 2 + (y - 17) ** 2 <= 9:
            del stripes.p[(x, y)]
    ink = Layer().rect(10, 16, 11, 17, INK); light = Layer().dot(10, 16, WHITE)
    nostril = Layer().dot(4, 26, INK).dot(5, 26, INK)
    return [(neck, True), (mane, True), (head, True), (muzzle, True), (earL, True), (earR, True), (stripes, False),
            (ink, False), (light, False), (nostril, False)]


def sushi():
    rice = Layer().ellipse(19.5, 28, 15, 7.5, WHITE)
    rice.shade(19.5, 28, 15, 7.5, GRAY, WHITE, -1, -3)
    grains = Layer().dots([(9, 27), (13, 30), (18, 33), (24, 32), (29, 29), (15, 26), (26, 26), (21, 29)], GRAY)
    grains.keep(lambda x, y: (x, y) in rice.p)
    neta = Layer().ellipse(19.5, 17.5, 18, 7, ORANGE, angle=-7)
    neta.shade(19.5, 17.5, 18, 7, RUST, ORANGE, -2, -3, angle=-7)
    fat = Layer()
    for x0 in (6, 13, 20, 27):
        fat.line(x0, 11, x0 - 2, 25, "FFD9BF", width=2)
    fat.keep(lambda x, y: (x, y) in neta.p)
    hi = Layer().dots([(5, 15), (6, 14), (7, 13)], "FFD9BF")
    return [(rice, True), (grains, False), (neta, True), (fat, False), (hi, False)]


def egg():
    body = Layer().egg(19.5, 21, 14, 17.5, "F5E6C8", taper=0.28)
    body.shade(19.5, 21, 14, 17.5, "DCC49A", "F5E6C8", -3, -3)
    body.ellipse(19.5, 21, 14, 17.5, "F5E6C8", clip=True, where=lambda x, y: False)
    speck = Layer().dots([(12, 24), (24, 15), (20, 30), (27, 25), (15, 13), (9, 30), (23, 9), (16, 33)], "C9AD7C")
    hi = Layer().line(11, 16, 12, 11, "FFFAF0", width=2).dots([(14, 8)], "FFFAF0")
    return [(body, True), (speck, False), (hi, False)]


def dango():
    skewer = Layer().line(8, 37, 32, 3, TAN, width=2)
    balls = []
    for (cx, cy, col, dark) in [(12, 30, GREEN_L, GREEN), (19.5, 20, WHITE, GRAY), (27, 10, PINK, PINK_D)]:
        b = Layer().ellipse(cx, cy, 7.5, 7.5, col)
        b.shade(cx, cy, 7.5, 7.5, dark, col, -2, -2)
        balls.append((b, True))
    hi = Layer()
    for (cx, cy) in [(12, 30), (19.5, 20), (27, 10)]:
        hi.dot(int(cx) - 3, cy - 3, WHITE).dot(int(cx) - 4, cy - 2, WHITE)
    return [(skewer, True)] + balls + [(hi, False)]


def chicken():
    tail = Layer().poly([(28, 22), (35, 8), (37, 10), (34, 20), (38, 15), (38, 22), (34, 26), (29, 28)], GREEN_D)
    tail.ellipse(33, 16, 4, 3, GREEN, clip=True)
    comb = Layer().ellipse(7, 7, 2.5, 3, RED).ellipse(10.5, 4.5, 2.5, 3, RED).ellipse(14, 7, 2.5, 3, RED)
    wattle = Layer().ellipse(9, 21, 2, 3.5, RED)
    beak = Layer().poly([(5, 13), (1, 16), (5, 17)], YELLOW)
    legs = Layer().rect(16, 33, 17, 36, ORANGE).rect(24, 33, 25, 36, ORANGE)
    legs.rect(13, 37, 19, 37, ORANGE).rect(22, 37, 28, 37, ORANGE)
    neck = Layer().poly([(7, 15), (16, 12), (22, 26), (9, 26)], WHITE)
    body = Layer().ellipse(20.5, 25, 13.5, 9.5, WHITE)
    body.shade(20.5, 25, 13.5, 9.5, GRAY, WHITE, -2, -3)
    head = Layer().ellipse(10.5, 14, 6.5, 6.5, WHITE)
    wing = Layer().ellipse(24, 26, 7.5, 4.5, WHITE, angle=-15)
    wing.shade(24, 26, 7.5, 4.5, GRAY, WHITE, -2, -2, angle=-15)
    ink = Layer().rect(9, 12, 10, 13, INK); light = Layer().dot(9, 12, WHITE)
    return [(tail, True), (legs, True), (comb, True), (wattle, True), (beak, True), (neck, True), (body, True),
            (head, True), (wing, True), (ink, False), (light, False)]


def taiyaki():
    tail = Layer().poly([(31, 21), (38, 11), (36, 21), (38, 31)], GOLD)
    dorsal = Layer().poly([(13, 13), (20, 5), (27, 13)], GOLD)
    body = Layer().ellipse(19, 21, 15, 9.5, GOLD)
    body.shade(19, 21, 15, 9.5, RUST, GOLD, -2, -3)
    grid = Layer()
    for i in range(6):
        grid.line(14 + i * 4, 12, 26 + i * 4, 32, BROWN_L, width=1)
        grid.line(20 + i * 4, 10, 8 + i * 4, 32, BROWN_L, width=1)
    grid.keep(lambda x, y: (x, y) in body.p and x >= 14)
    fin = Layer().ellipse(15.5, 25, 5, 2.5, RUST_L, angle=20)
    ink = Layer().rect(9, 18, 10, 19, INK); light = Layer().dot(9, 18, WHITE)
    mouth = Layer().line(4, 22, 7, 22, RUST)
    hi = Layer().dots([(9, 14), (10, 13), (11, 12)], "F0C98A")
    return [(tail, True), (dorsal, True), (body, True), (grid, False), (fin, True), (ink, False), (light, False),
            (mouth, False), (hi, False)]


def manju():
    plate = Layer().ellipse(19.5, 34, 17, 3, GRAY)
    skin = Layer().ellipse(19.5, 23, 16, 12, CREAM, where=lambda x, y: y <= 32)
    crust = Layer().ellipse(19.5, 23, 16, 12, GOLD, where=lambda x, y: y <= 32).erase(19.5, 25, 15, 11)
    anko = Layer().ellipse(19.5, 25, 10.5, 7.5, CHOCO, where=lambda x, y: y <= 32)
    anko.shade(19.5, 25, 10.5, 7.5, "4A2A0E", CHOCO, -2, -2)
    beans = Layer().dots([(14, 24), (18, 28), (23, 23), (25, 28), (20, 21), (12, 28)], CHOCO_L)
    hi = Layer().dots([(8, 17), (9, 16), (10, 15)], SAND_L)
    return [(plate, True), (skin, True), (crust, False), (anko, True), (beans, False), (hi, False)]


def fried_egg():
    white = Layer().ellipse(19, 22, 17, 12.5, WHITE).ellipse(10, 15, 8, 7.5, WHITE).ellipse(30, 26, 8, 6.5, WHITE)
    white.ellipse(29, 12, 7.5, 6.5, WHITE).ellipse(8, 28, 6, 5, WHITE)
    white.shade(19, 22, 19, 14, GRAY, WHITE, -1, -3)
    yolk = Layer().ellipse(17.5, 20.5, 8.5, 7.5, YELLOW)
    yolk.shade(17.5, 20.5, 8.5, 7.5, YELLOW_D, YELLOW, -2, -2)
    hi = Layer().dots([(13, 17), (14, 16), (15, 15), (12, 19)], YELLOW_L)
    return [(white, True), (yolk, True), (hi, False)]


def cake():
    top = Layer().poly([(5, 19), (34, 19), (30, 11), (9, 11)], WHITE)
    front = Layer().rect(5, 19, 34, 36, "F5D98B")
    front.rect(5, 24, 34, 27, WHITE).rect(5, 32, 34, 34, WHITE)
    front.shade(19.5, 28, 22, 14, "E0BE6A", "F5D98B", -3, 0)
    front.rect(5, 24, 34, 27, WHITE).rect(5, 32, 34, 34, WHITE)
    berrySlices = Layer()
    for x0 in (8, 16, 24, 32):
        berrySlices.ellipse(x0, 25.5, 2, 1.5, RED)
    berrySlices.keep(lambda x, y: 5 <= x <= 34)
    pipes = Layer()
    for x0 in (7, 12, 17, 22, 27, 32):
        pipes.ellipse(x0, 19.5, 2.5, 2, WHITE)
    berry = Layer().egg(19.5, 8, 4.5, 5, RED, taper=-0.3)
    berry.shade(19.5, 8, 4.5, 5, RED_D, RED, -1, -1)
    seeds = Layer().dots([(18, 8), (21, 9), (19, 11)], YELLOW_L)
    leaf = Layer().ellipse(19.5, 3.5, 4, 1.5, GREEN)
    return [(top, True), (front, True), (berrySlices, True), (pipes, True), (leaf, True), (berry, True), (seeds, False)]


def cotton_candy():
    stick = Layer().rect(19, 24, 20, 38, WHITE)
    cloud = Layer().ellipse(19.5, 16, 15.5, 12, PINK).ellipse(8.5, 20, 7.5, 7, PINK).ellipse(30.5, 19, 7.5, 7, PINK)
    cloud.ellipse(12.5, 8, 7, 6, PINK).ellipse(26.5, 7, 7, 6, PINK).ellipse(20, 25, 11, 5, PINK)
    cloud.shade(19.5, 17, 19, 14, PINK_D, PINK, -2, -3)
    fluff = Layer().ellipse(11, 12, 3, 2.5, PINK_L).ellipse(22, 8, 3, 2.5, PINK_L).ellipse(27, 18, 2.5, 2, PINK_L)
    fluff.ellipse(9, 22, 2, 1.5, PINK_L).ellipse(16, 20, 2, 1.5, PINK_L)
    return [(stick, True), (cloud, True), (fluff, False)]


def sneaker():
    sole = Layer().poly([(2, 29), (37, 29), (38, 32), (36, 35), (4, 35), (2, 32)], WHITE)
    sole.rect(2, 33, 38, 35, GRAY, clip=True)
    upper = Layer().poly([(3, 29), (4, 22), (12, 18), (18, 10), (29, 8), (35, 11), (37, 20), (37, 29)], BLUE_D)
    upper.shade(20, 20, 19, 12, "2A78B0", BLUE_D, -2, -3)
    toe = Layer().ellipse(7.5, 26, 8.5, 5.5, WHITE)
    toe.keep(lambda x, y: (x, y) in upper.p)
    opening = Layer().ellipse(30.5, 12, 5, 2.5, GRAY_DD)
    opening.keep(lambda x, y: (x, y) in upper.p)
    laces = Layer()                                                                    # 靴紐（白い横棒 3 本）
    for i in range(3):
        laces.line(15, 16 + i * 5, 29, 13 + i * 5, WHITE, width=2)
    laces.keep(lambda x, y: (x, y) in upper.p)
    hi = Layer().dots([(8, 21), (9, 20), (10, 19), (12, 18)], BLUE)
    return [(sole, True), (upper, True), (toe, True), (opening, True), (laces, True), (hi, False)]


def bamboo():
    parts = []
    leaves = Layer()
    for (cx, cy, ang) in [(31, 8, -35), (33, 14, -10), (5, 24, 200), (7, 30, 170), (30, 30, -30)]:
        leaves.ellipse(cx, cy, 7, 2.2, GREEN_L, angle=ang)
    leaves.keep(lambda x, y: 1 <= x <= 38)
    parts.append((leaves, True))
    for (x0, off) in [(8, 0), (22, 5)]:
        stalk = Layer().rect(x0, 2, x0 + 6, 37, GREEN)
        stalk.rect(x0 + 1, 2, x0 + 1, 37, GREEN_LL)                           # 左の光
        stalk.rect(x0 + 5, 2, x0 + 6, 37, GREEN_D)                            # 右の影
        for ny in range(4 + off, 36, 10):
            stalk.rect(x0 - 1, ny, x0 + 7, ny + 1, GREEN)
            stalk.rect(x0 - 1, ny + 1, x0 + 7, ny + 1, GREEN_D)
        parts.append((stalk, True))
    return parts


def water_bottle():
    strap = Layer().ellipse(10, 21, 8, 11, BROWN).erase(10, 21, 6, 9).keep(lambda x, y: x <= 12)
    body = Layer().rect(12, 14, 27, 36, BLUE_D)
    body.ellipse(19.5, 36, 8, 2, BLUE_D)
    body.ellipse(19.5, 14, 8, 2, BLUE_D)
    body.rect(13, 14, 14, 37, "2A78B0", clip=True)
    body.rect(25, 14, 26, 37, "2A78B0", clip=True)
    body.rect(15, 14, 16, 37, BLUE, clip=True)
    shoulder = Layer().poly([(12, 14), (27, 14), (25, 10), (14, 10)], BLUE_D)
    cap = Layer().rect(14, 3, 25, 9, GRAY_D)
    cap.rect(15, 3, 24, 4, GRAY, clip=True)
    cap.rect(14, 8, 25, 9, GRAY_DD, clip=True)
    label = Layer().rect(12, 22, 27, 29, WHITE)
    label.ellipse(19.5, 25.5, 3, 3, BLUE)                                     # ラベルの水滴マーク
    hi = Layer().rect(15, 4, 16, 8, WHITE)
    return [(strap, True), (body, True), (shoulder, True), (cap, True), (label, True), (hi, False)]


SPRITES = [
    ("swimRing", "うきわ", swim_ring), ("umbrella", "かさ", umbrella), ("fish", "さかな", fish), ("eggplant", "なす", eggplant),
    ("fox", "きつね", fox), ("whale", "くじら", whale), ("ice", "こおり", ice), ("zebra", "しまうま", zebra),
    ("sushi", "すし", sushi), ("egg", "たまご", egg), ("dango", "だんご", dango), ("chicken", "にわとり", chicken),
    ("taiyaki", "たいやき", taiyaki), ("manju", "まんじゅう", manju), ("friedEgg", "めだまやき", fried_egg),
    ("cake", "けーき", cake), ("cottonCandy", "わたあめ", cotton_candy), ("sneaker", "くつ", sneaker),
    ("bamboo", "たけ", bamboo), ("waterBottle", "すいとう", water_bottle),
]

if __name__ == "__main__":
    out = {}
    for key, reading, fn in SPRITES:
        sp = to_sprite(compose(fn()))
        sp["reading"] = reading
        out[key] = sp
    json.dump(out, open(f"{OUT}/sprites_new.json", "w", encoding="utf-8"), ensure_ascii=False, indent=0)
    print("wrote", len(out), "sprites")
