"""画面モックの共通部品（/usr/bin/python3 の Pillow 11 で動かす。numpy 不要）。

iPhone 縦画面 393×852pt を @2x（786×1704px）で描く。色は release/v1.1.11 の
Packages/GameKit/Sources/Core/Theme.swift のライト側の値をそのまま使う。
フォントは Theme のコメント「丸ゴシックで楽しく」に合わせ、日本語はヒラギノ丸ゴ ProN W4、
数字・英字は SF Rounded（iOS の .rounded デザインと同じ系統）。ドット絵は必ずニアレストネイバーで拡大する。
"""
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
S = 2  # @2x

# ---------------------------------------------------------------- Theme.swift（ライト）
def hexc(v, a=255):
    return ((v >> 16) & 255, (v >> 8) & 255, v & 255, a)


BACKGROUND = hexc(0xFFF6EC)
SURFACE = hexc(0xFFFFFF)
INK = hexc(0x4A3B33)
INK_SUB = hexc(0x9A8A80)
FILL_STRONG = hexc(0x4A3B33)
FILL_MUTED = hexc(0x9A8A80)
CORAL = hexc(0xFF6F61)
TEAL = hexc(0x22C3BE)
PURPLE = hexc(0x8C7BE0)
YELLOW = hexc(0xFFC24B)
PINK = hexc(0xFF8FB1)
FILL_CORAL = hexc(0xFF8A7E)
FILL_TEAL = TEAL
FILL_PURPLE = hexc(0xB3A6F0)
FILL_YELLOW = YELLOW
FILL_PINK = PINK
ON_ACCENT = INK
CORNER = 20
CORNER_SMALL = 12
PAD = 16


def alpha(c, a):
    return c[:3] + (int(round(a * 255)),)


def blend(c, bg, a):
    """c を bg の上に不透明度 a で置いたときの色（.opacity() の見た目）。"""
    return tuple(int(round(c[i] * a + bg[i] * (1 - a))) for i in range(3)) + (255,)


def brightness(c, d):
    """SwiftUI の .brightness(d) の近似（各成分に d×255 を足す）。"""
    return tuple(max(0, min(255, int(round(v + d * 255)))) for v in c[:3]) + (255,)


# ---------------------------------------------------------------- フォント
_FONT_JA = "/System/Library/Fonts/ヒラギノ丸ゴ ProN W4.ttc"
_FONT_SF = "/System/Library/Fonts/SFNSRounded.ttf"
_cache = {}


def font_ja(pt):
    key = ("ja", pt)
    if key not in _cache:
        _cache[key] = ImageFont.truetype(_FONT_JA, int(round(pt * S)))
    return _cache[key]


def font_sf(pt, weight="Bold"):
    key = ("sf", pt, weight)
    if key not in _cache:
        f = ImageFont.truetype(_FONT_SF, int(round(pt * S)))
        try:
            f.set_variation_by_name(weight)
        except Exception:
            pass
        _cache[key] = f
    return _cache[key]


def is_ascii(s):
    return all(ord(ch) < 128 for ch in s)


def text(d, xy, s, pt, fill=INK, weight="Bold", anchor="la", ja_bold=True):
    """pt 単位で文字を置く。英数字だけなら SF Rounded、日本語を含むならヒラギノ丸ゴ。
    丸ゴは W4 しか無いので、太字相当は stroke で少し太らせる。"""
    x, y = xy[0] * S, xy[1] * S
    if is_ascii(s):
        d.text((x, y), s, font=font_sf(pt, weight), fill=fill, anchor=anchor)
    else:
        heavy = ja_bold and weight in ("Bold", "Heavy", "Semibold", "Black")
        d.text((x, y), s, font=font_ja(pt), fill=fill, anchor=anchor,
               stroke_width=(1 if heavy and pt >= 14 else 0), stroke_fill=fill)


def text_width(s, pt, weight="Bold"):
    f = font_sf(pt, weight) if is_ascii(s) else font_ja(pt)
    return f.getlength(s) / S


def text_run(d, xy, parts, anchor_y="t"):
    """[(文字, pt, 色, weight), ...] を左から続けて置く（数字と日本語でフォントが違うため）。戻り値: 右端 x(pt)"""
    x, y = xy
    for s, pt, fill, weight in parts:
        text(d, (x, y), s, pt, fill, weight, anchor="l" + anchor_y)
        x += text_width(s, pt, weight)
    return x


# ---------------------------------------------------------------- 図形
def rrect(d, box, r, fill=None, outline=None, width=1):
    x0, y0, x1, y1 = [v * S for v in box]
    d.rounded_rectangle((x0, y0, x1, y1), radius=r * S, fill=fill, outline=outline, width=width * S)


def card(img, box, r=CORNER, fill=SURFACE, shadow=True):
    """popCard: 白い面・丸角・やわらかい影（shadow: 黒 8%・ぼかし 10・y+6）。"""
    if shadow:
        W, H = img.size
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        ld = ImageDraw.Draw(layer)
        x0, y0, x1, y1 = box
        rrect(ld, (x0, y0 + 6, x1, y1 + 6), r, fill=(0, 0, 0, int(255 * 0.08)))
        layer = layer.filter(ImageFilter.GaussianBlur(10 * S / 2))
        img.alpha_composite(layer)
    d = ImageDraw.Draw(img)
    rrect(d, box, r, fill=fill)


def capsule(d, box, fill):
    x0, y0, x1, y1 = box
    r = (y1 - y0) / 2
    rrect(d, box, r, fill=fill)


def sprite(path, k=4):
    """ドット絵を読み、ニアレストネイバーで k 倍（k=4 で 1 ドット = 2pt）。"""
    im = Image.open(path).convert("RGBA")
    return im.resize((im.size[0] * k, im.size[1] * k), Image.NEAREST)


def paste_center(img, sp, cx, cy):
    """中心 (pt) にドット絵を置く。ドットの格子が @2x の整数ピクセルに乗るよう座標を丸める。"""
    x = int(round(cx * S - sp.size[0] / 2))
    y = int(round(cy * S - sp.size[1] / 2))
    img.alpha_composite(sp, (x, y))


# ---------------------------------------------------------------- 画面の枠
SCREEN_W, SCREEN_H = 393, 852
SAFE_TOP, NAV_H, SAFE_BOTTOM = 59, 44, 34


def new_screen():
    return Image.new("RGBA", (SCREEN_W * S, SCREEN_H * S), BACKGROUND)


def rotate_icon(d, cx, cy, r, color, width=2):
    """arrow.clockwise 相当（フォントに ↻ が無いので線で描く）。"""
    x0, y0, x1, y1 = (cx - r) * S, (cy - r) * S, (cx + r) * S, (cy + r) * S
    d.arc((x0, y0, x1, y1), start=-60, end=230, fill=color, width=int(width * S))
    # 矢じり（弧の終点 230° の少し先）
    import math
    a = math.radians(-60)
    tx, ty = cx + r * math.cos(a), cy + r * math.sin(a)
    h = r * 0.9
    pts = [(tx + h * 0.55, ty - h * 0.05), (tx - h * 0.15, ty - h * 0.55), (tx - h * 0.1, ty + h * 0.45)]
    d.polygon([(px * S, py * S) for px, py in pts], fill=color)


def chrome(img, title, tint=CORAL, right_glyph="rotate"):
    """ステータスバー・Dynamic Island・ナビゲーションバー（gameChrome 相当: 戻る・タイトル・右上アクション）。"""
    d = ImageDraw.Draw(img)
    # ステータスバー
    text(d, (52, 24), "9:41", 17, INK, "Semibold", anchor="lm")
    # 右: 電波・Wi-Fi・電池を簡略に
    x = 300
    for i, h in enumerate((4, 6, 8, 10)):
        rrect(d, (x + i * 5, 29 - h, x + i * 5 + 3, 29), 1, fill=INK)
    rrect(d, (326, 20, 336, 29), 1, fill=INK)  # Wi-Fi の代わり
    rrect(d, (344, 19, 368, 30), 3, fill=None, outline=INK, width=1)
    rrect(d, (346, 21, 362, 28), 2, fill=INK)
    rrect(d, (369, 22, 371, 27), 1, fill=INK)
    # Dynamic Island
    rrect(d, (SCREEN_W / 2 - 63, 11, SCREEN_W / 2 + 63, 48), 18.5, fill=(0, 0, 0, 255))
    # ナビゲーションバー
    y = SAFE_TOP + NAV_H / 2
    # 戻る山形
    d.line([(27 * S, (y - 9) * S), (18 * S, y * S), (27 * S, (y + 9) * S)], fill=tint, width=int(2.5 * S), joint="curve")
    text(d, (SCREEN_W / 2, y), title, 17, INK, "Semibold", anchor="mm")
    if right_glyph == "rotate":
        rotate_icon(d, SCREEN_W - 28, y, 8.5, tint, 2.2)
    elif right_glyph:
        text(d, (SCREEN_W - 20, y), right_glyph, 22, tint, "Semibold", anchor="rm")


def home_indicator(img):
    d = ImageDraw.Draw(img)
    rrect(d, (SCREEN_W / 2 - 67, SCREEN_H - 13, SCREEN_W / 2 + 67, SCREEN_H - 8), 2.5, fill=INK)


def round_screen(img, r=55):
    """端末の角に合わせて画面の四隅を丸く切る。"""
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, img.size[0] - 1, img.size[1] - 1), radius=r * S, fill=255)
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def compose(screens, labels, title, out_path, gap=48, bg=(0xEC, 0xE4, 0xD8, 255)):
    """複数の画面を横に並べ、上にラベルを付けた 1 枚にする。"""
    n = len(screens)
    W = gap * (n + 1) + SCREEN_W * S * n
    top = 150
    H = top + SCREEN_H * S + gap + 24
    canvas = Image.new("RGBA", (W, H), bg)
    d = ImageDraw.Draw(canvas)
    d.text((gap, 28), title, font=font_ja(14), fill=INK)
    for i, (sc, lab) in enumerate(zip(screens, labels)):
        x = gap + i * (SCREEN_W * S + gap)
        d.text((x + SCREEN_W * S / 2, top - 30), lab, font=font_ja(18), fill=INK, anchor="mm",
               stroke_width=1, stroke_fill=INK)
        # 端末の縁
        d.rounded_rectangle((x - 6, top - 6, x + SCREEN_W * S + 6, top + SCREEN_H * S + 6), radius=(55 + 3) * S,
                            fill=(40, 36, 44, 255))
        canvas.alpha_composite(round_screen(sc), (x, top))
    canvas.convert("RGB").save(out_path)
    print(out_path, canvas.size)
