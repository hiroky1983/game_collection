#!/usr/bin/env python3
"""「おじさんの飼い猫パズル」（#2250）のモックを HTML で組み、Chrome ヘッドレスで PNG にする。

使い方: python3 docs/design/cat-puzzle-2250/tools/build.py docs/design/cat-puzzle-2250（リポジトリの root から）
  出力: a1-house-playing.html/.png, a2-house-clear.html/.png,
        b1-meow-playing.html/.png, b2-meow-clear.html/.png,
        tile-cat.html/.png（179×215 のタイル絵）, hub-tile.html/.png（ハブに置いた見え方）
猫の絵は assets/cats/*.png（会長の ChatGPT シートからの切り抜き）、おじさんは assets/ojisan_cheer.png。
"""
import os, shutil, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(sys.argv[1])
os.makedirs(os.path.join(OUT, "assets", "cats"), exist_ok=True)
RENDER = os.path.join(HERE, "render.py")

# ---------- 問題（gen3.py seed 1。解は 1 つ） ----------
N = 7
REG = ["0000011",
       "0000011",
       "0021111",
       "0222331",
       "2252334",
       "5255634",
       "5556664"]
SOL = [1, 5, 2, 4, 6, 0, 3]  # 行 → 列
REG = [[int(ch) for ch in row] for row in REG]
SOLSET = {(r, SOL[r]) for r in range(N)}

def nb8(r, c):
    for dr in (-1, 0, 1):
        for dc in (-1, 0, 1):
            if dr or dc:
                rr, cc = r + dr, c + dc
                if 0 <= rr < N and 0 <= cc < N:
                    yield rr, cc

# 解の検証（安全のためここでも数える）
def count_solutions(limit=3):
    cnt = 0; used_c = [False]*N; used_r = [False]*N; cols = [-1]*N
    def rec(r):
        nonlocal cnt
        if cnt >= limit: return
        if r == N: cnt += 1; return
        for c in range(N):
            if used_c[c] or used_r[REG[r][c]]: continue
            if r > 0 and abs(cols[r-1]-c) <= 1: continue
            used_c[c] = used_r[REG[r][c]] = True; cols[r] = c
            rec(r+1)
            used_c[c] = used_r[REG[r][c]] = False; cols[r] = -1
    rec(0); return cnt
assert count_solutions() == 1, "解が 1 つではない"
for r in range(N):
    assert REG[r][SOL[r]] == r or True
# 行・列・区画に 1 つ、隣接なし
assert sorted(SOL) == list(range(N))
assert len({REG[r][SOL[r]] for r in range(N)}) == N
assert all(abs(SOL[r] - SOL[r-1]) > 1 for r in range(1, N))

# ---------- 画面の共通部品 ----------
CELL = 52
BOARD_LEFT = 16
BOARD_TOP = 160
INK = "#4A3B33"; SUB = "#9A8A80"; CORAL = "#FF6F61"; TEAL = "#22C3BE"; YELLOW = "#FFC24B"
FILL_CORAL = "#FF8A7E"; PURPLE = "#8C7BE0"; PINK = "#FF8FB1"

STATUS = ('<div class="status"><span>9:41</span><span class="r">'
          '<svg width="18" height="12" viewBox="0 0 18 12" fill="#4A3B33"><rect x="0" y="8" width="3" height="4" rx="1"/><rect x="5" y="5.5" width="3" height="6.5" rx="1"/><rect x="10" y="3" width="3" height="9" rx="1"/><rect x="15" y="0" width="3" height="12" rx="1"/></svg>'
          '<svg width="16" height="12" viewBox="0 0 16 12" fill="none" stroke="#4A3B33" stroke-width="1.8" stroke-linecap="round"><path d="M1 4.2a10.5 10.5 0 0 1 14 0"/><path d="M3.8 7a6.5 6.5 0 0 1 8.4 0"/><path d="M6.6 9.6a2.5 2.5 0 0 1 2.8 0"/></svg>'
          '<span class="bar"></span></span></div>')

BASE_CSS = f"""
*{{box-sizing:border-box;margin:0;padding:0}}
html,body{{width:402px;height:874px;overflow:hidden}}
body{{background:#FFF6EC;color:{INK};font-family:"SF Pro Rounded",".SF NS Rounded","Hiragino Sans","Hiragino Kaku Gothic ProN",sans-serif;-webkit-font-smoothing:antialiased}}
.screen{{position:relative;width:402px;height:874px;overflow:hidden}}
.status{{height:54px;display:flex;align-items:flex-end;justify-content:space-between;padding:0 36px 6px 44px;font-weight:700;font-size:17px}}
.status .r{{display:flex;gap:6px;align-items:center;font-size:13px}}
.status .bar{{display:inline-block;width:18px;height:11px;border:1.5px solid {INK};border-radius:3px;position:relative}}
.status .bar::after{{content:"";position:absolute;left:1.5px;top:1.5px;bottom:1.5px;width:11px;background:#34C759;border-radius:1px}}
.nav{{position:relative;height:44px;display:flex;align-items:center;justify-content:center;font-size:17px;font-weight:800}}
.nav .back{{position:absolute;left:14px;top:9px;width:26px;height:26px}}
.nav .right{{position:absolute;right:14px;top:9px;display:flex;gap:14px}}
.nav .ic{{width:26px;height:26px}}
.pill{{position:absolute;left:16px;top:106px;width:370px;height:44px;background:#fff;border-radius:16px;box-shadow:0 6px 10px rgba(0,0,0,.06);display:flex;align-items:center;justify-content:space-between;padding:0 14px;font-weight:800;font-size:15px}}
.pill .s{{color:{SUB};font-size:13px}}
.board{{position:absolute;left:{BOARD_LEFT}px;top:{BOARD_TOP}px;width:{CELL*N+6}px;height:{CELL*N+6}px;border:3px solid {INK};border-radius:8px;background:#fff;overflow:hidden}}
.cell{{position:absolute;width:{CELL}px;height:{CELL}px}}
.line{{position:absolute;background:{INK}}}
.thin{{position:absolute;background:rgba(74,59,51,.16)}}
.cat{{position:absolute;pointer-events:none;filter:drop-shadow(0 2px 2px rgba(0,0,0,.18))}}
.x{{position:absolute;width:{CELL}px;height:{CELL}px;display:flex;align-items:center;justify-content:center;font-size:24px;font-weight:800;color:rgba(74,59,51,.38);line-height:1}}
.lbl{{position:absolute;font-size:9px;font-weight:800;color:{INK};background:rgba(255,255,255,.78);border-radius:6px;padding:1px 5px;line-height:1.3;white-space:nowrap}}
.row{{position:absolute;left:16px;top:556px;width:370px;height:54px;display:flex;gap:10px;align-items:center}}
.cap{{flex:1;height:54px;border-radius:27px;display:flex;align-items:center;justify-content:center;gap:8px;font-weight:800;font-size:16px;color:{INK};box-shadow:0 4px 8px rgba(0,0,0,.10)}}
.cap .two{{display:flex;flex-direction:column;align-items:flex-start;line-height:1.05}}
.cap .two small{{font-size:10px;font-weight:800;opacity:.85}}
.more{{flex:0 0 54px;width:54px;height:54px;border-radius:27px;background:{SUB};display:flex;align-items:center;justify-content:center;gap:4px}}
.more i{{display:block;width:6px;height:6px;border-radius:3px;background:#fff}}
.banner{{position:absolute;left:16px;top:782px;width:370px;height:50px;border-radius:12px;background:#D9D4CC;display:flex;align-items:center;justify-content:center;font-size:12px;font-weight:800;color:#7E746C}}
.homebar{{position:absolute;left:131px;bottom:8px;width:140px;height:5px;border-radius:3px;background:{INK};opacity:.9}}
.hintring{{position:absolute;width:{CELL}px;height:{CELL}px;border:3px dashed {YELLOW};border-radius:10px;box-shadow:0 0 0 3px rgba(255,194,75,.35) inset}}
.bubble{{position:absolute;background:#fff;border:2px solid {YELLOW};border-radius:12px;padding:5px 9px;font-size:12px;font-weight:800;color:{INK};box-shadow:0 4px 8px rgba(0,0,0,.12);white-space:nowrap}}
.bubble::after{{content:"";position:absolute;left:18px;bottom:-8px;width:12px;height:12px;background:#fff;border-right:2px solid {YELLOW};border-bottom:2px solid {YELLOW};transform:rotate(45deg)}}
.bubble.left::after{{left:-8px;bottom:auto;top:12px;border:0;border-left:2px solid {YELLOW};border-bottom:2px solid {YELLOW};transform:rotate(45deg)}}
.bubble.right::after{{left:auto;right:-8px;bottom:auto;top:12px;border:0;border-right:2px solid {YELLOW};border-top:2px solid {YELLOW};transform:rotate(45deg)}}
.card{{position:absolute;left:41px;width:320px;border-radius:20px;background:rgba(255,255,255,.86);-webkit-backdrop-filter:blur(18px);backdrop-filter:blur(18px);padding:12px 20px 14px;text-align:center;box-shadow:0 10px 24px rgba(0,0,0,.14)}}
.card .t{{font-size:22px;font-weight:800;color:{TEAL};margin-top:4px}}
.card .d{{font-size:14px;font-weight:700;margin-top:6px}}
.card .btn{{display:inline-block;margin-top:8px;height:38px;line-height:38px;padding:0 20px;border-radius:22px;background:{FILL_CORAL};font-weight:800;font-size:15px;color:{INK}}}
.meow{{position:absolute;background:#fff;border:2px solid {INK};border-radius:9px;font-size:9px;font-weight:800;color:{INK};padding:1px 4px;line-height:1.2;white-space:nowrap;box-shadow:0 2px 3px rgba(0,0,0,.12)}}
.meow::after{{content:"";position:absolute;left:8px;bottom:-7px;width:9px;height:9px;background:#fff;border-right:2px solid {INK};border-bottom:2px solid {INK};transform:rotate(45deg)}}
.oji{{position:absolute;image-rendering:pixelated;filter:drop-shadow(0 3px 3px rgba(0,0,0,.2))}}
.ojibubble{{position:absolute;background:#fff;border:2px solid {CORAL};border-radius:14px;padding:6px 10px;font-size:13px;font-weight:800;color:{INK};box-shadow:0 4px 8px rgba(0,0,0,.12);white-space:nowrap}}
.ojibubble::after{{content:"";position:absolute;left:-9px;top:14px;width:12px;height:12px;background:#fff;border-left:2px solid {CORAL};border-bottom:2px solid {CORAL};transform:rotate(45deg)}}
.prop{{position:absolute}}
"""

def nav(title):
    return (f'<div class="nav"><svg class="back" viewBox="0 0 26 26" fill="none" stroke="{CORAL}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M16 5 L8 13 L16 21"/></svg>'
            f'<span>{title}</span><div class="right">'
            f'<svg class="ic" viewBox="0 0 26 26" fill="none" stroke="{CORAL}" stroke-width="2"><circle cx="13" cy="13" r="10.5"/><text x="13" y="18" text-anchor="middle" font-size="14" font-weight="800" fill="{CORAL}" stroke="none" font-family="SF Pro Rounded,Hiragino Sans,sans-serif">?</text></svg>'
            f'<svg class="ic" viewBox="0 0 26 26"><circle cx="13" cy="13" r="11.5" fill="{CORAL}"/><path d="M13 7v12M7 13h12" stroke="#fff" stroke-width="2.6" stroke-linecap="round"/></svg>'
            f'</div></div>')

def pill(left, right):
    return f'<div class="pill"><span>{left}</span><span class="s">{right}</span></div>'

def cellpos(r, c):
    return 3 + c * CELL, 3 + r * CELL

def board_cells(colors):
    """区画の塗りと、区画の境の太線・細線。colors[k] は区画 k の背景（CSS）。"""
    h = []
    for r in range(N):
        for c in range(N):
            x, y = cellpos(r, c)
            h.append(f'<div class="cell" style="left:{x}px;top:{y}px;background:{colors[REG[r][c]]}"></div>')
    for i in range(1, N):
        p = 3 + i * CELL
        h.append(f'<div class="thin" style="left:{p}px;top:3px;width:1px;height:{CELL*N}px"></div>')
        h.append(f'<div class="thin" style="left:3px;top:{p}px;width:{CELL*N}px;height:1px"></div>')
    for r in range(N):
        for c in range(N):
            x, y = cellpos(r, c)
            if c + 1 < N and REG[r][c] != REG[r][c+1]:
                h.append(f'<div class="line" style="left:{x+CELL-1.25}px;top:{y}px;width:2.5px;height:{CELL}px"></div>')
            if r + 1 < N and REG[r][c] != REG[r+1][c]:
                h.append(f'<div class="line" style="left:{x}px;top:{y+CELL-1.25}px;width:{CELL}px;height:2.5px"></div>')
    return "".join(h)

def cat_in_cell(r, c, name, size=44, dx=0, dy=0, flip=False):
    x, y = cellpos(r, c)
    tf = "transform:scaleX(-1);" if flip else ""
    return (f'<img class="cat" src="assets/cats/{name}.png" style="left:{x + (CELL-size)/2 + dx}px;top:{y + (CELL-size)/2 + dy}px;'
            f'width:{size}px;height:{size}px;object-fit:contain;{tf}">')

def xmark(r, c):
    x, y = cellpos(r, c)
    return f'<div class="x" style="left:{x}px;top:{y}px">×</div>'

def label(r, c, text, dy=0):
    x, y = cellpos(r, c)
    return f'<div class="lbl" style="left:{x+3}px;top:{y+3+dy}px">{text}</div>'

def action_row(items):
    h = ['<div class="row">']
    for bg, icon, title, sub in items:
        inner = f'{icon}<span class="two"><span>{title}</span>' + (f'<small>{sub}</small>' if sub else '') + '</span>'
        h.append(f'<div class="cap" style="background:{bg}">{inner}</div>')
    h.append('<div class="more"><i></i><i></i><i></i></div></div>')
    return "".join(h)

ICON_UNDO = f'<svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="{INK}" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M7 5 3 9l4 4"/><path d="M3 9h8a5 5 0 0 1 0 10h-1"/></svg>'
ICON_BULB = f'<svg width="20" height="20" viewBox="0 0 20 20" fill="{INK}"><path d="M10 1.5a6 6 0 0 0-3.5 10.9c.6.5 1 1.2 1 2V15h5v-.6c0-.8.4-1.5 1-2A6 6 0 0 0 10 1.5z"/><rect x="7.5" y="16" width="5" height="2.2" rx="1"/></svg>'

def banner():
    return '<div class="banner">広告バナー（仮・高さ 50pt）</div><div class="homebar"></div>'

def clear_card(top, details):
    d = "".join(f'<div class="d">{x}</div>' for x in details)
    return (f'<div class="card" style="top:{top}px">'
            f'<svg width="34" height="34" viewBox="0 0 40 40" fill="{YELLOW}"><path d="M10 4h20v8a10 10 0 0 1-20 0V4z"/><path d="M6 6h4v6a4 4 0 0 1-4-4V6zm24 0h4v2a4 4 0 0 1-4 4V6z"/><rect x="17" y="21" width="6" height="7"/><rect x="11" y="28" width="18" height="5" rx="1.5"/></svg>'
            f'<div class="t">クリア！</div>{d}<div class="btn">盤を見る</div></div>')

def ojisan(x, y, text):
    return (f'<img class="oji" src="assets/ojisan_cheer.png" style="left:{x}px;top:{y}px;width:56px">'
            f'<div class="ojibubble" style="left:{x+62}px;top:{y+4}px">{text}</div>')

def page(title_tag, body):
    return f'<!doctype html><html lang="ja"><head><meta charset="utf-8"><title>{title_tag}</title><style>{BASE_CSS}</style></head><body><div class="screen">{body}</div></body></html>'

TITLE = "おじさんの飼い猫"

# ---------- 案A「おじさんの家」 ----------
# 区画 → 部屋・家具。塗りは床の質感（畳・板・タイル・段ボール）。
ROOM = {
    0: ("こたつ",   "repeating-linear-gradient(90deg,#F4E6B9 0 6px,#EEDDA6 6px 7px)"),      # 畳
    1: ("押し入れ", "repeating-linear-gradient(180deg,#F7F1E6 0 11px,#E6DAC6 11px 12px)"),   # ふすま
    2: ("段ボール", "repeating-linear-gradient(0deg,#D9B98E 0 3px,#D2AF80 3px 4px)"),       # 段ボール
    3: ("本棚",     "repeating-linear-gradient(90deg,#D8CBEF 0 9px,#C6B6E6 9px 10px)"),      # 本の背
    4: ("お風呂",   "linear-gradient(#CFEFF2,#CFEFF2) padding-box, repeating-linear-gradient(90deg,#C2E7EB 0 12px,#AADCE2 12px 13px)"),  # タイル
    5: ("台所",     "repeating-linear-gradient(45deg,#FBE4DA 0 8px,#F6D3C6 8px 9px)"),        # 台所のタイル
    6: ("玄関",     "repeating-linear-gradient(180deg,#DDD6CC 0 12px,#CFC6BA 12px 13px)"),    # 玄関のたたき
}
ROOM_LABEL_CELL = {0: (0, 2), 1: (0, 5), 2: (3, 1), 3: (3, 4), 4: (4, 6), 5: (6, 0), 6: (6, 4)}

def house_props():
    """部屋らしさを足す小物（CSS だけ）。こたつ・ふすまの取っ手・段ボールのテープ・本棚の棚板・浴槽・流し・靴。"""
    h = []
    # こたつ: (0,3)-(1,4) に、みかん色の布団と木の天板
    x, y = cellpos(0, 3)
    h.append(f'<div class="prop" style="left:{x+6}px;top:{y+10}px;width:84px;height:76px;border-radius:16px;background:#F28C52;box-shadow:0 3px 4px rgba(0,0,0,.15)"></div>')
    h.append(f'<div class="prop" style="left:{x+21}px;top:{y+22}px;width:54px;height:50px;border-radius:8px;background:#8B5A2B;border:3px solid #6E4621"></div>')
    h.append(f'<div class="prop" style="left:{x+36}px;top:{y+36}px;width:24px;height:20px;border-radius:50%;background:#F7A823;border:2px solid #E08A14"></div>')  # みかん
    # ふすまの取っ手（押し入れ）
    for (r, c) in ((1, 5), (1, 6)):
        x, y = cellpos(r, c)
        h.append(f'<div class="prop" style="left:{x+20}px;top:{y+22}px;width:8px;height:14px;border-radius:4px;border:2px solid #8B7355;background:#E6DAC6"></div>')
    # 段ボールのテープ（区画 2 の中央）
    x, y = cellpos(3, 2)
    h.append(f'<div class="prop" style="left:{x+4}px;top:{y+22}px;width:44px;height:8px;background:#C9A27A;opacity:.9"></div>')
    # 本棚の棚板
    for (r, c) in ((3, 4), (3, 5), (4, 4), (4, 5), (5, 4)):
        x, y = cellpos(r, c)
        h.append(f'<div class="prop" style="left:{x}px;top:{y+CELL-6}px;width:{CELL}px;height:4px;background:#8B6B4A;opacity:.8"></div>')
    # 浴槽
    x, y = cellpos(5, 6)
    h.append(f'<div class="prop" style="left:{x+5}px;top:{y+16}px;width:42px;height:60px;border-radius:12px 12px 16px 16px;background:#fff;border:3px solid #6FB7C2"></div>')
    h.append(f'<div class="prop" style="left:{x+9}px;top:{y+24}px;width:34px;height:40px;border-radius:8px;background:#9ED8E2"></div>')
    # 台所の流し
    x, y = cellpos(6, 1)
    h.append(f'<div class="prop" style="left:{x+4}px;top:{y+10}px;width:44px;height:32px;border-radius:6px;background:#D7D9DC;border:2px solid #AEB2B8"></div>')
    h.append(f'<div class="prop" style="left:{x+20}px;top:{y+2}px;width:4px;height:14px;border-radius:2px;background:#8E949B"></div>')
    # 玄関の靴
    x, y = cellpos(6, 5)
    h.append(f'<div class="prop" style="left:{x+8}px;top:{y+18}px;width:16px;height:26px;border-radius:8px 8px 4px 4px;background:#5B4636"></div>')
    h.append(f'<div class="prop" style="left:{x+28}px;top:{y+18}px;width:16px;height:26px;border-radius:8px 8px 4px 4px;background:#5B4636"></div>')
    return "".join(h)

def house_board(extra):
    colors = {k: v[1] for k, v in ROOM.items()}
    h = ['<div class="board">', board_cells(colors), house_props()]
    for k, (r, c) in ROOM_LABEL_CELL.items():
        h.append(label(r, c, ROOM[k][0]))
    h.append(extra)
    h.append('</div>')
    return "".join(h)

def playing_marks(placed):
    """置いた猫から機械的に導ける × を並べる（同じ行・列・区画と周囲 8 マス）。"""
    xs = set()
    for (r, c) in placed:
        for i in range(N):
            xs.add((r, i)); xs.add((i, c))
        for rr in range(N):
            for cc in range(N):
                if REG[rr][cc] == REG[r][c]:
                    xs.add((rr, cc))
        for p in nb8(r, c):
            xs.add(p)
    return xs - set(placed)

def build_a1():
    placed = [(0, 1), (1, 5), (5, 0)]
    xs = playing_marks(placed)
    extra = "".join(xmark(r, c) for (r, c) in sorted(xs))
    extra += "".join(cat_in_cell(r, c, "face_normal") for (r, c) in placed)
    # ヒント: 段ボールの区画で残る唯一のマスにしるし
    hx, hy = cellpos(2, 2)
    extra += f'<div class="hintring" style="left:{hx}px;top:{hy}px"></div>'
    body = STATUS + nav(TITLE) + pill("残り 4匹", "ミス 0 ・ ふつう ・ 01:23") + house_board(extra)
    # 吹き出しは盤の外に重ねる（盤は overflow hidden）
    body += f'<div class="bubble left" style="left:{BOARD_LEFT + hx + CELL + 12}px;top:{BOARD_TOP + hy + 8}px">ヒント: 段ボールの中にいるよ</div>'
    body += action_row([(TEAL, ICON_UNDO, "戻す", None), (YELLOW, ICON_BULB, "ヒント", "あと2回")])
    body += banner()
    return page("案A 遊んでいる途中", body)

def build_a2():
    h = []
    # それぞれの場所でくつろぐ猫（マスより大きく描く）
    h.append(cat_in_cell(0, 1, "sleep", size=70, dx=4, dy=8))          # こたつで寝る
    h.append(cat_in_cell(1, 5, "face_relax", size=50, dy=-2))           # 押し入れからのぞく
    h.append(cat_in_cell(2, 2, "sit_front", size=60, dy=-6))            # 段ボール
    x, y = cellpos(2, 2)
    h.append(f'<div class="prop" style="left:{x-2}px;top:{y+26}px;width:56px;height:26px;background:#C9A27A;border:2px solid #A8865F;border-radius:3px"></div>')  # 箱の手前
    h.append(cat_in_cell(3, 4, "sit_side", size=58, dy=-4))             # 本棚の棚に座る
    h.append(cat_in_cell(4, 6, "face_wow", size=50, dy=-4))             # お風呂で驚く
    h.append(cat_in_cell(5, 0, "pounce", size=66, dx=6, dy=0))          # 台所でねずみを追う
    h.append(cat_in_cell(6, 3, "stretch", size=64, dx=0, dy=-6))        # 玄関で伸び
    body = STATUS + nav(TITLE) + pill("全員みつけた！", "ミス 0 ・ ふつう ・ 01:48") + house_board("".join(h))
    body += ojisan(24, 534, "7匹ともくつろいでおる")
    body += clear_card(588, ["タイム 01:48 ・ ふつう ・ 自己ベスト"])
    body += '<div class="homebar"></div>'
    body += '<div class="banner">広告バナー（仮・高さ 50pt）</div>'
    return page("案A クリア", body)

# ---------- 案B「鳴き声さがし」 ----------
PASTEL = {0: "#FFE1DC", 1: "#D4F3F1", 2: "#E4DEF9", 3: "#FFF0C7", 4: "#FFDDE8", 5: "#DCF2D8", 6: "#E6E0D6"}
HINTS = [(0, 3), (2, 4), (4, 5), (5, 2)]  # にゃーの聞こえるマス（答えのマスではない）
for p in HINTS:
    assert p not in SOLSET
def meow_count(r, c):
    return sum(1 for p in nb8(r, c) if p in SOLSET)

def meow_marker(r, c):
    n = meow_count(r, c)
    x, y = cellpos(r, c)
    text = "しーん" if n == 0 else f"にゃー×{n}"
    ear = f'<svg width="14" height="14" viewBox="0 0 14 14" style="position:absolute;left:{x+3}px;top:{y+3}px"><path d="M2 12V5l3-3 2 3h0l2-3 3 3v7z" fill="#B9ABA2"/></svg>'
    return (f'<div class="cell" style="left:{x}px;top:{y}px;background:rgba(255,255,255,.45)"></div>'
            + ear + f'<div class="meow" style="left:{x+5}px;top:{y+22}px">{text}</div>')

def meow_board(extra, with_hints=True):
    h = ['<div class="board">', board_cells(PASTEL)]
    if with_hints:
        for (r, c) in HINTS:
            h.append(meow_marker(r, c))
    h.append(extra); h.append('</div>')
    return "".join(h)

def build_b1():
    placed = [(1, 5), (3, 4)]
    xs = playing_marks(placed) - set(HINTS)
    extra = "".join(xmark(r, c) for (r, c) in sorted(xs))
    extra += "".join(cat_in_cell(r, c, "face_normal") for (r, c) in placed)
    # 「にゃー×2」のマスの周囲 8 マスを囲んで、2 匹とも見つかったことを示す
    x, y = cellpos(1, 3)
    extra += f'<div style="position:absolute;left:{x}px;top:{y}px;width:{CELL*3}px;height:{CELL*3}px;border:3px solid {YELLOW};border-radius:12px;box-shadow:0 0 0 2px rgba(255,194,75,.25) inset"></div>'
    body = STATUS + nav(TITLE) + pill("残り 5匹", "ミス 0 ・ むずかしい ・ 02:05") + meow_board(extra)
    bx, by = cellpos(2, 4)
    tx, ty = cellpos(2, 0)
    body += f'<div class="bubble right" style="left:{BOARD_LEFT + tx + 22}px;top:{BOARD_TOP + ty + 10}px">この2匹で決まり</div>'
    body += action_row([(TEAL, ICON_UNDO, "戻す", None), (YELLOW, ICON_BULB, "ヒント", "あと3回")])
    body += banner()
    return page("案B 遊んでいる途中", body)

def build_b2():
    faces = ["face_happy", "face_relax", "face_normal", "face_wow", "face_happy", "face_relax", "face_normal"]
    extra = "".join(cat_in_cell(r, SOL[r], faces[r], size=46) for r in range(N))
    body = STATUS + nav(TITLE) + pill("全員みつけた！", "ミス 0 ・ むずかしい ・ 02:40") + meow_board(extra)
    body += ojisan(24, 534, "鳴き声で分かるもんじゃな")
    body += clear_card(588, ["タイム 02:40 ・ むずかしい"])
    body += '<div class="homebar"></div>'
    body += '<div class="banner">広告バナー（仮・高さ 50pt）</div>'
    return page("案B クリア", body)

# ---------- ハブのタイル（179×215。他のタイルと同じ作り） ----------
def build_tile():
    cells = []
    cols = ["#FFE1DC", "#D4F3F1", "#E4DEF9", "#FFF0C7", "#FFDDE8", "#DCF2D8", "#D4F3F1", "#FFE1DC", "#E4DEF9"]
    for i in range(9):
        r, c = divmod(i, 3)
        inner = ""
        if i == 4:
            inner = '<img src="assets/cats/face_happy.png" style="width:30px;height:30px;object-fit:contain;display:block;margin:2px auto 0">'
        elif i in (0, 2, 6):
            inner = '<div style="font-size:20px;font-weight:800;color:rgba(74,59,51,.4);text-align:center;line-height:34px">×</div>'
        cells.append(f'<div style="position:absolute;left:{c*35}px;top:{r*35}px;width:34px;height:34px;background:{cols[i]};border:1.5px solid rgba(74,59,51,.5)">{inner}</div>')
    return f'''<!doctype html><html><head><meta charset="utf-8"><style>
*{{box-sizing:border-box;margin:0;padding:0}}
html,body{{width:179px;height:215px;overflow:hidden}}
body{{font-family:"SF Pro Rounded",".SF NS Rounded","Hiragino Sans",sans-serif;-webkit-font-smoothing:antialiased}}
.bg{{position:absolute;inset:0;background:linear-gradient(160deg,#FFD98A 0%,#F7A94B 55%,#E88A2E 100%)}}
.o{{position:absolute;filter:drop-shadow(0 6px 6px rgba(0,0,0,.28))}}
</style></head><body><div class="bg"></div><div style="position:absolute;inset:0;transform:translateY(24px)">
<div class="o" style="left:12px;top:78px;width:106px;height:106px;background:#fff;border-radius:10px;border:3px solid #4A3B33;transform:rotate(-8deg);overflow:hidden"><div style="position:relative;left:0;top:0">{"".join(cells)}</div></div>
<img class="o" src="assets/cats/big_wave.png" style="left:72px;top:40px;width:120px;transform:rotate(6deg)">
</div></body></html>'''

def build_hub():
    src = os.path.join(OUT, "..", "hub-redesign-1831", "hub-redesign", "04b-category-chips.html")
    html = open(src, encoding="utf-8").read()
    # タイルの絵は刷新モックの素材を相対パスで参照する
    html = html.replace('src="assets/', 'src="../hub-redesign-1831/hub-redesign/assets/')
    html = html.replace('<div class="c">おじさんシリーズ</div>', '<div class="c on">おじさんシリーズ</div>')
    html = html.replace('<div class="c on">トランプ</div>', '<div class="c">トランプ</div>')
    html = html.replace('トランプ　<span class="sub" style="font-size:12px">7本</span>', 'おじさんシリーズ　<span class="sub" style="font-size:12px">4本</span>')
    start = html.index('<div class="grid2">')
    end = html.index('</div>', html.rindex('<div class="tile">'))  # 最後のタイルの終わり
    end = html.index('</div>', end + 6) + 6  # grid2 の閉じ
    T = '../hub-redesign-1831/hub-redesign/assets/tiles/'
    tiles = (
        f'<div class="tile"><img src="{T}runner.png"><div class="fade"></div><div class="name">チャリンコおじさん</div><div class="ul" style="background:{CORAL}"></div></div>'
        f'<div class="tile"><img src="{T}ojisanpuzzle.png"><div class="fade"></div><div class="name small">腰痛おじさんパズル</div><div class="ul" style="background:{TEAL}"></div></div>'
        f'<div class="tile"><img src="{T}homerun.png"><div class="fade"></div><div class="name">柵越えおじさん</div><div class="ul" style="background:{PURPLE}"></div></div>'
        f'<div class="tile"><img src="tile-cat.png"><div class="fade"></div><div class="name">おじさんの飼い猫</div><div class="ul" style="background:{YELLOW}"></div><div class="badge" style="color:{CORAL}">NEW</div></div>'
    )
    html = html[:start] + '<div class="grid2">' + tiles + '</div>' + html[end:]
    html = html.replace('<title>案4b カテゴリーチップ</title>', '<title>ハブに置いた「おじさんの飼い猫」のタイル</title>')
    return html

# ---------- 出力 ----------
# 猫の切り抜き（crop_cats.py の出力）が隣にあればコピーする。無ければ出力先の assets/cats をそのまま使う。
if os.path.isdir(os.path.join(HERE, "cats")):
    for n in os.listdir(os.path.join(HERE, "cats")):
        if n.endswith(".png") and not n.startswith("_"):
            shutil.copy(os.path.join(HERE, "cats", n), os.path.join(OUT, "assets", "cats", n))
shutil.copy(os.path.join(OUT, "..", "hub-redesign-1831", "hub-redesign", "assets", "sprites", "ojisan_cheer.png"),
            os.path.join(OUT, "assets", "ojisan_cheer.png"))

files = {
    "a1-house-playing.html": build_a1(),
    "a2-house-clear.html": build_a2(),
    "b1-meow-playing.html": build_b1(),
    "b2-meow-clear.html": build_b2(),
    "tile-cat.html": build_tile(),
}
for name, html in files.items():
    open(os.path.join(OUT, name), "w", encoding="utf-8").write(html)
for name in files:
    size = ("179", "215") if name.startswith("tile") else ("402", "874")
    subprocess.run([sys.executable, RENDER, os.path.join(OUT, name), os.path.join(OUT, name.replace(".html", ".png")), *size], check=True)
# ハブはタイル PNG ができてから
open(os.path.join(OUT, "hub-tile.html"), "w", encoding="utf-8").write(build_hub())
subprocess.run([sys.executable, RENDER, os.path.join(OUT, "hub-tile.html"), os.path.join(OUT, "hub-tile.png")], check=True)
print("solution:", SOL, "meow hints:", [(p, meow_count(*p)) for p in HINTS])
