#!/usr/bin/env python3
"""腰痛おじさんパズルの画面モック（作業服おじさんのドット絵入り）。

実行: /usr/bin/python3 make_mock_backpain.py  → mock_backpain.png
画面構成は試作 wip/ojisan-puzzle-prototype の OjisanPuzzleView.swift に合わせる:
  見出しカード（スコア・連鎖・腰痛ゲージ 128×8）／盤 6 列×12 段（spacing 1・inset 6・fillMuted 18% の丸角）／
  右の列（おじさんの枠 → 「つぎ」の荷物 2 個）／操作のヒント 1 行／入院のリザルトは画面全体に重ねるカード。
試作との違い: おじさんの枠は顔 32×30 ではなく全身 48 ドット（1 ドット = 2pt）を置くため、
  右の列を 64pt → 104pt に広げた（盤は 245pt 幅）。限界のときの -8° の傾きはドット絵が崩れるので付けていない。
"""
import os
from PIL import Image, ImageDraw

import mockkit as M
from mockkit import S, text, text_run, rrect, card, capsule, sprite, paste_center

HERE = os.path.dirname(os.path.abspath(__file__))
PX = f"{HERE}/px48"

COLUMNS, ROWS = 6, 12
SIDE_W = 104           # 試作は 64。全身のドット絵を置くため広げた
INSET = 6

LUGGAGE = {  # value: (面色, 重さ)  試作 OjisanPuzzleView.color / OjisanPuzzleLuggage.kinds
    1: (M.FILL_YELLOW, 1),   # 段ボール箱
    2: (M.FILL_TEAL, 2),     # 座布団
    3: (M.FILL_CORAL, 3),    # 米袋
    4: (M.FILL_PURPLE, 4),   # タンス
}

STAGES = {
    # name: (pain, caption, ゲージ色, スコア, 連鎖, おじさんのコマ, 面を痛い色にする)
    "easy":   (12, "まだ平気", M.FILL_TEAL, 320, 0, "carry_light_smile", False),
    "aching": (55, "腰にくる", M.FILL_YELLOW, 1480, 2, "carry_heavy_pain_sweat", False),
    "severe": (90, "こしが限界", M.FILL_CORAL, 2760, 0, "limit_back_pain", True),
    "hosp":   (100, "こしが限界", M.FILL_CORAL, 2760, 0, "limit_back_pain", True),
}

# 盤（上が 0 段目）。0 = 空き。落下中の組は top に書く
def board_for(stage):
    b = [[0] * COLUMNS for _ in range(ROWS)]
    rows_easy = [
        [0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 2],
        [1, 0, 0, 3, 0, 2],
        [1, 2, 0, 3, 1, 4],
    ]
    rows_aching = [
        [0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 1],
        [0, 2, 0, 0, 3, 1],
        [4, 2, 0, 1, 3, 2],
        [4, 1, 3, 1, 2, 2],
        [1, 1, 3, 4, 4, 3],
        [2, 3, 3, 4, 1, 3],
    ]
    rows_severe = [
        [0, 0, 0, 0, 0, 0],
        [0, 0, 3, 0, 0, 0],
        [0, 1, 3, 0, 2, 0],
        [4, 1, 2, 0, 2, 1],
        [4, 3, 2, 1, 4, 1],
        [2, 3, 1, 1, 4, 3],
        [2, 4, 1, 3, 3, 3],
        [1, 4, 2, 2, 1, 2],
        [1, 3, 2, 4, 1, 2],
        [3, 3, 4, 4, 2, 1],
    ]
    rows = {"easy": rows_easy, "aching": rows_aching, "severe": rows_severe, "hosp": rows_severe}[stage]
    for i, r in enumerate(rows):
        b[ROWS - len(rows) + i] = list(r)
    # 落下中の組（軸 + 子）を上に
    if stage != "hosp":
        b[1][2] = 2 if stage == "easy" else 4 if stage == "aching" else 1
        b[2][2] = 1 if stage == "easy" else 3 if stage == "aching" else 2
    return b


def draw_glyph(d, kind, cx, cy, side):
    """荷物の種類が分かる簡単な記号（試作は SF Symbol。ここでは同じ onAccent 色で線画）。"""
    s = side * 0.52
    k = M.ON_ACCENT
    w = max(1, int(round(side * 0.07 * S)))
    x0, y0, x1, y1 = (cx - s / 2) * S, (cy - s / 2) * S, (cx + s / 2) * S, (cy + s / 2) * S
    if kind == 1:    # 段ボール箱
        d.rectangle((x0, y0 + s * S * 0.15, x1, y1), outline=k, width=w)
        d.line((cx * S, y0 + s * S * 0.15, cx * S, y1), fill=k, width=w)
        d.line((x0, y0 + s * S * 0.15, x1, y0 + s * S * 0.15), fill=k, width=w)
    elif kind == 2:  # 座布団（重ねた四角）
        for i in range(3):
            yy = y0 + s * S * (0.2 + 0.3 * i)
            d.rounded_rectangle((x0, yy, x1, yy + s * S * 0.22), radius=s * S * 0.1, fill=k)
    elif kind == 3:  # 米袋
        d.ellipse((x0, y0 + s * S * 0.3, x1, y1), fill=k)
        d.rounded_rectangle((cx * S - s * S * 0.18, y0, cx * S + s * S * 0.18, y0 + s * S * 0.4), radius=s * S * 0.08, fill=k)
    elif kind == 4:  # タンス（引き出し）
        d.rounded_rectangle((x0, y0, x1, y1), radius=s * S * 0.1, fill=k)
        for i in range(2):
            yy = y0 + s * S * (0.33 + 0.33 * i)
            d.line((x0 + w, yy, x1 - w, yy), fill=M.FILL_PURPLE, width=w)
        d.ellipse((cx * S - w, y0 + s * S * 0.12, cx * S + w, y0 + s * S * 0.12 + 2 * w), fill=M.FILL_PURPLE)


def draw_board(img, box, board):
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = box
    rrect(d, box, M.CORNER, fill=M.blend(M.FILL_MUTED, M.BACKGROUND, 0.18))
    cell = (x1 - x0 - INSET * 2) / COLUMNS
    side = cell - 1
    for r in range(ROWS):
        for c in range(COLUMNS):
            v = board[r][c]
            cx = x0 + INSET + c * cell + cell / 2
            cy = y0 + INSET + r * cell + cell / 2
            if v == 0:
                fill = M.blend(M.FILL_MUTED, M.blend(M.FILL_MUTED, M.BACKGROUND, 0.18), 0.14)
            else:
                col, weight = LUGGAGE[v]
                fill = M.brightness(col, -0.045 * (weight - 1))
            rrect(d, (cx - side / 2, cy - side / 2, cx + side / 2, cy + side / 2), side * 0.24, fill=fill)
            if v:
                draw_glyph(d, v, cx, cy, side)


def draw_screen(stage):
    pain, caption, gauge_col, score, chain, frame, hurt = STAGES[stage]
    img = M.new_screen()
    M.chrome(img, "腰痛おじさんパズル")
    d = ImageDraw.Draw(img)
    cap_col = M.INK_SUB if stage == "easy" else M.CORAL

    # ---- 見出し（スコア・連鎖・腰痛ゲージ）
    top = M.SAFE_TOP + M.NAV_H + M.PAD
    hx0, hx1 = M.PAD, M.SCREEN_W - M.PAD
    hh = 10 + 14 + 2 + 30 + 10
    card(img, (hx0, top, hx1, top + hh), M.CORNER_SMALL)
    d = ImageDraw.Draw(img)
    text(d, (hx0 + 16, top + 10), "スコア", 12, M.INK_SUB, anchor="la")
    text(d, (hx0 + 16, top + 10 + 14 + 2), f"{score}", 26, M.INK, "Heavy", anchor="la")
    if chain > 1:
        x = hx0 + 16 + text_width_num(score) + 12
        text_run(d, (x, top + 10 + 14 + 2 + 7), [(f"{chain}", 16, M.CORAL, "Bold"), ("連鎖", 16, M.CORAL, "Bold")])
    gx1 = hx1 - 16
    gx0 = gx1 - 128
    gy = top + hh / 2 - (12 + 3 + 8) / 2
    text_run(d, (gx0, gy), [("腰痛 ", 12, cap_col, "Bold"), (f"{pain}", 12, cap_col, "Bold"), ("　" + caption, 12, cap_col, "Bold")])
    gy2 = gy + 12 + 5
    capsule(d, (gx0, gy2, gx1, gy2 + 8), M.blend(M.FILL_MUTED, M.SURFACE, 0.22))
    capsule(d, (gx0, gy2, gx0 + 128 * pain / 100, gy2 + 8), gauge_col)

    # ---- 盤と右の列
    by0 = top + hh + 12
    bx0, bx1 = M.PAD, M.SCREEN_W - M.PAD - 12 - SIDE_W
    cell = (bx1 - bx0 - INSET * 2) / COLUMNS
    by1 = by0 + INSET * 2 + cell * ROWS
    draw_board(img, (bx0, by0, bx1, by1), board_for(stage))

    sx0, sx1 = bx1 + 12, M.SCREEN_W - M.PAD
    sp = sprite(f"{PX}/a_work_{frame}.png", 4)          # 1 ドット = 2pt
    sp_h = 48 * 4 / S                                     # 枠は 48 ドットぶんで固定（コマの高さで揺れない）
    c1h = 10 + sp_h + 4 + 12 + 10
    fill = M.blend(M.FILL_CORAL, M.BACKGROUND, 0.28) if hurt else M.SURFACE
    card(img, (sx0, by0, sx1, by0 + c1h), M.CORNER_SMALL, fill=fill)
    paste_center(img, sp, (sx0 + sx1) / 2, by0 + 10 + sp_h / 2)
    d = ImageDraw.Draw(img)
    text(d, ((sx0 + sx1) / 2, by0 + 10 + sp_h + 4 + 6), caption, 10, cap_col, anchor="mm")

    ny0 = by0 + c1h + 10
    c2h = 12 + 12 + 6 + 26 + 2 + 26 + 12
    card(img, (sx0, ny0, sx1, ny0 + c2h), M.CORNER_SMALL)
    d = ImageDraw.Draw(img)
    text(d, ((sx0 + sx1) / 2, ny0 + 12 + 6), "つぎ", 12, M.INK_SUB, anchor="mm")
    nxt = {"easy": (3, 1), "aching": (2, 4), "severe": (4, 4), "hosp": (4, 4)}[stage]
    for i, v in enumerate(nxt):
        cx = (sx0 + sx1) / 2
        cy = ny0 + 12 + 12 + 6 + 13 + i * 28
        col, weight = LUGGAGE[v]
        rrect(d, (cx - 13, cy - 13, cx + 13, cy + 13), 26 * 0.24, fill=M.brightness(col, -0.045 * (weight - 1)))
        draw_glyph(d, v, cx, cy, 26)

    # ---- 操作のヒント
    hy = by1 + 12 + 8
    parts = [("⇆ よこにスワイプ", 11), ("   タップで回す", 11), ("↓ 下スワイプ", 11)]
    total = sum(text_width(s, pt) for s, pt in parts) + 14 * 2
    x = M.SCREEN_W / 2 - total / 2
    for s, pt in parts:
        if s.startswith("   "):
            M.rotate_icon(d, x + 6, hy, 5, M.INK_SUB, 1.5)
        text(d, (x, hy), s, pt, M.INK_SUB, anchor="lm")
        x += text_width(s, pt) + 14

    # ---- 入院のリザルト（画面全体に重ねるカード）
    if stage == "hosp":
        fallen = sprite(f"{PX}/a_work_fallen_face_down_crying.png", 4)
        cw = M.SCREEN_W - 12 * 2
        ch = 22 + fallen.size[1] / S + 10 + 30 + 10 + 20 + 10 + 24 + 10 + 44 + 22
        cx0, cy0 = 12, M.SCREEN_H / 2 - ch / 2
        card(img, (cx0, cy0, cx0 + cw, cy0 + ch), M.CORNER)
        d = ImageDraw.Draw(img)
        y = cy0 + 22
        paste_center(img, fallen, M.SCREEN_W / 2, y + fallen.size[1] / S / 2)
        y += fallen.size[1] / S + 10
        text(d, (M.SCREEN_W / 2, y + 15), "入院！", 24, M.INK, "Heavy", anchor="mm")
        y += 30 + 10
        text(d, (M.SCREEN_W / 2, y + 10), "腰が限界です。おだいじに。", 14, M.INK_SUB, "Semibold", anchor="mm")
        y += 20 + 10
        w = text_width("スコア ", 18) + text_width(f"{score}", 18)
        text_run(d, (M.SCREEN_W / 2 - w / 2, y), [("スコア ", 18, M.INK, "Bold"), (f"{score}", 18, M.INK, "Bold")])
        y += 24 + 10
        bw = text_width("もう一度", 17) + 28 * 2
        rrect(d, (M.SCREEN_W / 2 - bw / 2, y, M.SCREEN_W / 2 + bw / 2, y + 44), M.CORNER_SMALL, fill=M.FILL_CORAL)
        text(d, (M.SCREEN_W / 2, y + 22), "もう一度", 17, M.ON_ACCENT, anchor="mm")

    M.home_indicator(img)
    return img


def text_width(s, pt, weight="Bold"):
    return M.text_width(s, pt, weight)


def text_width_num(n):
    return M.text_width(f"{n}", 26, "Heavy")


def main():
    stages = ["easy", "aching", "severe", "hosp"]
    labels = ["余裕（まだ平気・腰痛 12）", "痛い（腰にくる・腰痛 55）", "限界（こしが限界・腰痛 90）", "入院（倒れる・リザルト）"]
    screens = [draw_screen(s) for s in stages]
    M.compose(screens, labels,
              "腰痛おじさんパズル 画面モック（作業服おじさん 48 ドット・1 ドット = 2pt）  iPhone 393×852pt @2x  2026-10-07",
              f"{HERE}/mock_backpain.png")


if __name__ == "__main__":
    main()
