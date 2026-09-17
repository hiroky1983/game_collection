"""チャリンコおじさんの正面顔 32×30 の設計スクリプト（使い捨て）。

土台（輪郭・髪・耳・鼻・頬・ヒゲ）を 1 枚描き、表情ごとに眉・目・口だけを上書きして 3 面を作る。
出力:
  - faces.png     : 3 表情を 1 ドット = 10px で横並び（目視用）
  - faces-small.png: 44pt 枠相当（1 ドット ≒ 2px）と 4px の縮小版（ハブのアイコンでの見え方）
  - rows.txt      : Swift に貼る行文字列
"""
import sys, os
from PIL import Image

OUT = os.path.dirname(os.path.abspath(__file__))
W, H = 32, 30

# 既存パレット（OjisanPixel.palette）
PAL = {
    "K": 0x2B2634, "S": 0xF2C8A0, "s": 0xD69E76, "W": 0xFAF6EC, "Y": 0xF0C030, "y": 0xC4901C,
    "B": 0x3E4E80, "b": 0x28345C, "H": 0x9696A2, "h": 0x626270, "E": 0x221E28, "R": 0xD43C2C,
    "r": 0x96241C, "T": 0x34343C, "t": 0x787882, "C": 0xE87860, "N": 0xAA763E, "G": 0x60586E,
    "M": 0x96282C, "Q": 0xFAF6EC, "X": 0x3C2828,
}
# 追加（末尾に追記する分）
NEW = {
    "L": 0xFBE0BE,  # 肌のハイライト（額・鼻すじ・あご先）
    "p": 0xE8B88E,  # 肌の中間影（頬の丸み・目の下）
    "d": 0xB57A52,  # 肌の深い影（あご下・鼻の穴・輪郭の内側の暗い側）
    "I": 0xC8C8D2,  # 白髪のハイライト（房の上面）
    "m": 0x5E1418,  # 口の中（大笑いのとき）
    "a": 0x6CB8E8,  # 汗の雫（しかめ面）
}
PAL.update(NEW)


class Grid:
    def __init__(self):
        self.g = [["."] * W for _ in range(H)]

    def put(self, x, y, ch):
        if 0 <= x < W and 0 <= y < H:
            self.g[y][x] = ch

    def hl(self, y, x0, x1, ch):
        for x in range(x0, x1 + 1):
            self.put(x, y, ch)

    def row(self, y, x0, s):
        for i, ch in enumerate(s):
            if ch != " ":
                self.put(x0 + i, y, ch)

    def rows(self):
        return ["".join(r) for r in self.g]

    def copy(self):
        g = Grid()
        g.g = [r[:] for r in self.g]
        return g


def mirror_x(x):
    return 31 - x


HW_A = {1: 4, 2: 6, 3: 7, 4: 8, 5: 9, 6: 10, 7: 11, 8: 11, 9: 12, 10: 12, 11: 13, 12: 13, 13: 13,
        14: 13, 15: 13, 16: 13, 17: 12, 18: 12, 19: 12, 20: 11, 21: 11, 22: 10, 23: 9, 24: 8,
        25: 6, 26: 4}
# 頭頂を丸く（旧 16×15 の比率に近い）
HW_B = {1: 5, 2: 7, 3: 8, 4: 9, 5: 10, 6: 11, 7: 11, 8: 12, 9: 12, 10: 12, 11: 13, 12: 13, 13: 13,
        14: 13, 15: 13, 16: 13, 17: 12, 18: 12, 19: 12, 20: 11, 21: 11, 22: 10, 23: 9, 24: 8,
        25: 6, 26: 4}
HW = HW_B


def base():
    g = Grid()
    # --- 顔の内側（肌）を行ごとの半幅で決める。卵型: 目の高さが最も広く、あごへ細る ---
    hw = HW
    inside = [[False] * W for _ in range(H)]
    for y, w in hw.items():
        for x in range(16 - w, 16 + w):
            inside[y][x] = True
    # 耳（13〜17 行で 1 ドット張り出す）と首（あごの下に 1 行）
    for y in range(13, 18):
        inside[y][2] = inside[y][29] = True
    for x in range(13, 19):
        inside[27][x] = True
    # 輪郭 = 内側の 4 近傍で内側でない所
    for y in range(H):
        for x in range(W):
            if inside[y][x]:
                g.put(x, y, "S")
    for y in range(H):
        for x in range(W):
            if inside[y][x]:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < W and 0 <= ny < H and not inside[ny][nx]:
                        g.put(nx, ny, "K")
    # 内側の一段明るい輪郭: 下に K があれば d、右に K があれば s、それ以外（左・上）は p
    for y in range(H):
        for x in range(W):
            if not inside[y][x]:
                continue
            below = y + 1 < H and not inside[y + 1][x]
            right = x + 1 < W and not inside[y][x + 1]
            left = x - 1 >= 0 and not inside[y][x - 1]
            above = y - 1 >= 0 and not inside[y - 1][x]
            if below:
                g.put(x, y, "d")
            elif right:
                g.put(x, y, "s")
            elif left or above:
                g.put(x, y, "p")
    # 右側（影側）はリングの内側にもう 1 列 p を置く（頬から下だけ・縦縞に見えない程度）
    for y in range(12, 24):
        w = hw[y]
        g.put(15 + w - 1, y, "p")
    # あご: 外側 2 列を p、下 2 行を影にして丸みを出す
    for y in range(20, 25):
        w = hw[y]
        g.put(16 - w + 1, y, "p"); g.put(15 + w - 1, y, "p")
        g.put(16 - w + 2, y, "p") if y >= 22 else None
        g.put(15 + w - 2, y, "p") if y >= 22 else None
    g.hl(25, 11, 20, "p"); g.hl(26, 13, 18, "p")
    g.hl(25, 10, 10, "s"); g.hl(25, 21, 21, "s")
    g.hl(26, 12, 12, "s"); g.hl(26, 19, 19, "s")
    g.hl(27, 13, 18, "s")
    # あご先のつや
    g.hl(23, 14, 17, "L"); g.hl(24, 15, 16, "L")

    # --- 額のハイライト（薄い頭のつや） ---
    g.hl(2, 14, 17, "L")
    g.hl(3, 12, 19, "L")
    g.hl(4, 12, 20, "L")
    g.hl(5, 13, 19, "L")
    g.hl(6, 14, 18, "L")
    g.hl(7, 15, 17, "L")

    # --- 白髪（輪郭に沿った帯。こめかみで厚く、頭頂は薄く、耳の上で終わる） ---
    hair_left = {
        3: "IH", 4: "IHh", 5: "IHHh", 6: "IIHh", 7: "IHHh", 8: "HHh", 9: "IHh",
        10: "HHh", 11: "IHh", 12: "Hh", 13: "h",
    }
    for y, s in hair_left.items():
        x0 = 16 - hw[y]
        g.row(y, x0, s)
        for i, ch in enumerate(s):
            g.put(15 + hw[y] - i, y, ch)
    # 房の出っぱり（左右で少し違えて手描きの味を出す）
    g.put(16 - hw[3] + 2, 3, "h"); g.put(15 + hw[6] - 3, 6, "H")
    g.put(16 - hw[8] + 1, 8, "I"); g.put(15 + hw[10] - 1, 10, "I"); g.put(16 - hw[12], 12, "I")

    # --- 耳の中 ---
    g.put(2, 14, "s"); g.put(2, 15, "d"); g.put(2, 16, "s")
    g.put(29, 14, "d"); g.put(29, 15, "d"); g.put(29, 16, "d")

    # --- 鼻（鼻すじのハイライト → 鼻先 → 下側の影） ---
    g.hl(10, 15, 16, "L"); g.hl(11, 15, 16, "L"); g.hl(12, 15, 16, "L")
    g.row(13, 14, "pLLp")
    g.row(14, 13, "sSLSps")
    g.row(15, 13, "spSSps")
    g.row(16, 13, "dssssd")

    # --- 頬（血色。2×2 に 1 ドット添えて丸く） ---
    g.row(14, 7, "CC"); g.row(15, 6, "CCC")
    g.row(14, 23, "CC"); g.row(15, 23, "CCC")
    g.put(8, 16, "p"); g.put(23, 16, "p")
    # 目の下のたるみ（65 歳）
    g.hl(14, 10, 13, "p"); g.hl(14, 18, 21, "p")

    return g


MUSTACHE = "M2"


def mustache(g, droop=False):
    """口ヒゲ。口との間に肌を 1 行（19 行目）残す。"""
    if MUSTACHE == "M1":
        # 1 行の細いヒゲ、端だけ 1 行垂れる
        g.row(17, 11, "hHHHHHHHHh")
        g.row(18, 10, "hH"); g.row(18, 20, "Hh")
    elif MUSTACHE == "M2":
        # 鼻下の中央だけ 2 行、両端は 1 行で細く
        g.row(17, 10, "hhHHHHHHHHhh")
        g.row(18, 13, "hHHHHh")
    elif MUSTACHE == "M3":
        # M2 の上面を白く（軽く見せる）
        g.row(17, 10, "hIIHHHHHHIIh")
        g.row(18, 13, "hHHHHh")
    if droop:
        g.put(9, 18, "h"); g.put(22, 18, "h")
        g.put(10, 18, "h"); g.put(21, 18, "h")


def brows_smile(g):
    # 太い眉、外側がやや下がるゆるい弧
    g.row(8, 10, "hhhh"); g.row(9, 9, "Hhhh")
    g.row(8, 18, "hhhh"); g.row(9, 19, "hhhH")


def brows_cheer(g):
    # 1 行上がって弧が強まる（うれしい）
    g.row(7, 10, "hhh"); g.row(8, 9, "Hhhhh")
    g.row(7, 19, "hhh"); g.row(8, 18, "hhhhH")


FROWN = "F1"


def brows_frown(g):
    # ハの字（内側が上がり外側が下がる）= 困り顔・痛い
    g.row(8, 12, "hh"); g.row(9, 10, "hhh"); g.row(10, 8, "hh")
    g.row(8, 18, "hh"); g.row(9, 19, "hhh"); g.row(10, 22, "hh")
    # 眉間のしわ
    g.put(15, 9, "d"); g.put(16, 9, "d")


def sweat(g):
    # 右のこめかみの汗（頭の外に浮かせる）
    g.put(29, 7, "K")
    g.row(8, 28, "KaK")
    g.row(9, 28, "KWaK")
    g.row(10, 29, "KK")


def no_cheeks(g):
    for x in (7, 8, 23, 24):
        g.put(x, 14, "S")
    for x in (6, 7, 8, 23, 24, 25):
        g.put(x, 15, "S")


EYE = "I"


def eyes_open(g):
    rows = {
        # A: まぶた + 2 行、左上ハイライト
        "A": ["KKKK", "QWEQ", "QEEQ", "pppp"],
        # B: まぶた + 3 行（縦長）
        "B": ["KKKK", "QWEQ", "QEEQ", "QEEQ"],
        # C: まぶた + 2 行、ハイライト無し
        "C": ["KKKK", "QEEQ", "QEEQ", "pppp"],
        # D: まぶた無し 2 行 + ハイライト
        "D": ["pppp", "QWEQ", "QEEQ", "pppp"],
        # E: まぶた + 2 行、瞳 3 幅でハイライト左上、白目は外側 1 ドットのみ
        "E": ["KKKK", "QWEE", "QEEE", "pppp"],
        # F: まぶた + 白目 1 行 + 瞳 2 行（瞳が下寄り = 老眼のたれ目）
        "F": ["KKKK", "QQQQ", "QWEQ", "QEEQ"],
        # G: まぶた + 2 行、下まぶた線 s
        "G": ["KKKK", "QWEQ", "QEEQ", "ssss"],
        # H: 5 幅、瞳 3×2 に左上ハイライト
        "H": ["KKKKK", "QWEEQ", "QEEEQ", "ppppp"],
        # I: 4 幅、瞳 2×2、ハイライトを灰色 t で控えめに
        "I": ["KKKK", "QtEQ", "QEEQ", "pppp"],
        # J: 5 幅、瞳 3×2、ハイライト灰色
        "J": ["KKKKK", "QtEEQ", "QEEEQ", "ppppp"],
        # C2: 4 幅ハイライト無し・下まぶた s
        "C2": ["KKKK", "QEEQ", "QEEQ", "ssss"],
    }[EYE]
    wide = len(rows[0]) == 5
    for i, r in enumerate(rows):
        g.row(10 + i, 9 if wide else 10, r)
        g.row(10 + i, 18, r)


def eyes_shut_x(g):
    # ぎゅっと閉じる（><）
    g.row(10, 10, "KK"); g.row(11, 12, "KK"); g.row(12, 10, "KK")
    g.row(10, 20, "KK"); g.row(11, 18, "KK"); g.row(12, 20, "KK")
    g.hl(13, 10, 13, "p"); g.hl(13, 18, 21, "p")


def eyes_shut_arc(g):
    # 閉じて への字に潰す（∪）
    g.row(11, 10, "K  K"); g.row(12, 11, "KK")
    g.row(11, 18, "K  K"); g.row(12, 19, "KK")
    g.hl(13, 10, 13, "p"); g.hl(13, 18, 21, "p")


def mouth_smile(g):
    # 歯を見せて笑う（19 行目は肌のまま）
    g.row(20, 11, "MQQQQQQQQM")
    g.row(21, 12, "MQQQQQQM")
    g.row(22, 13, "MMMMMM")
    g.put(12, 22, "d"); g.put(19, 22, "d")


def mouth_cheer(g):
    # 大きく開けて笑う。上の歯・口の中・舌
    g.row(20, 11, "MQQQQQQQQM")
    g.row(21, 10, "MmmmmmmmmmmM")
    g.row(22, 10, "MmmRRRRRRmmM")
    g.row(23, 11, "MMMMMMMMMM")
    g.put(10, 23, "d"); g.put(21, 23, "d")


def mouth_clench(g):
    # 歯を食いしばる
    g.row(20, 11, "MMMMMMMMMM")
    g.row(21, 11, "MQQMQQMQQM")
    g.row(22, 11, "MMMMMMMMMM")


def mouth_ugh(g):
    # 小さく「うっ」
    g.row(20, 13, "MMMMMM")
    g.row(21, 12, "MmmmmmmM")
    g.row(22, 13, "MMMMMM")


def make(name):
    g = base()
    if name == "smile":
        mustache(g); brows_smile(g); eyes_open(g); mouth_smile(g)
    elif name == "cheer":
        mustache(g); brows_cheer(g); eyes_open(g); mouth_cheer(g)
    elif name == "frown":
        mustache(g, droop=True); no_cheeks(g); brows_frown(g); sweat(g)
        if FROWN == "F1":
            eyes_shut_x(g); mouth_clench(g)
        elif FROWN == "F2":
            eyes_shut_arc(g); mouth_ugh(g)
        elif FROWN == "F3":
            eyes_shut_x(g); mouth_ugh(g)
    return g.rows()


def variant_sheet():
    global MUSTACHE, FROWN
    ms = []
    for v in ("M1", "M2", "M3"):
        MUSTACHE = v
        ms.append(make("smile"))
    MUSTACHE = "M2"
    fs = []
    for v in ("F1", "F2", "F3"):
        FROWN = v
        fs.append(make("frown"))
    FROWN = "F1"
    top = render(ms, 10); bottom = render(fs, 10)
    img = Image.new("RGB", (max(top.width, bottom.width), top.height + bottom.height), (255, 255, 255))
    img.paste(top, (0, 0)); img.paste(bottom, (0, top.height))
    img.save(os.path.join(OUT, "variants.png"))


def rgb(v):
    return ((v >> 16) & 255, (v >> 8) & 255, v & 255)


def render(rows_list, scale, gap=16, plate=(220, 238, 249)):
    n = len(rows_list)
    img = Image.new("RGB", (n * (W * scale + gap) + gap, H * scale + gap * 2), (255, 255, 255))
    px = img.load()
    for i, rows in enumerate(rows_list):
        ox = gap + i * (W * scale + gap)
        oy = gap
        for y in range(H):
            for x in range(W):
                ch = rows[y][x]
                col = plate if ch == "." else rgb(PAL[ch])
                for dy in range(scale):
                    for dx in range(scale):
                        px[ox + x * scale + dx, oy + y * scale + dy] = col
    return img


def eye_sheet():
    global EYE
    faces = []
    vs = ["C", "H", "I", "J", "C2"]
    for v in vs:
        EYE = v
        faces.append(make("smile"))
    img = render(faces, 8, gap=8)
    img.save(os.path.join(OUT, "eyes.png"))
    scale = 8; gap = 8
    crops = []
    for i in range(len(vs)):
        ox = gap + i * (W * scale + gap); oy = gap
        crops.append(img.crop((ox + 6 * scale, oy + 6 * scale, ox + 26 * scale, oy + 16 * scale)).resize((20 * 16, 10 * 16), Image.NEAREST))
    out = Image.new("RGB", (3 * (crops[0].width + 10) + 10, 2 * (crops[0].height + 10) + 10), (255, 255, 255))
    for i, c in enumerate(crops):
        out.paste(c, (10 + (i % 3) * (c.width + 10), 10 + (i // 3) * (c.height + 10)))
    out.save(os.path.join(OUT, "eyes-zoom.png"))
    EYE = "I"


def head_sheet():
    global HW
    out = []
    for hw in (HW_A, HW_B):
        HW = hw
        out += [make(n) for n in ("smile", "frown")]
    render(out, 10).save(os.path.join(OUT, "heads.png"))
    HW = HW_B


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "eyes":
        eye_sheet(); return
    if len(sys.argv) > 1 and sys.argv[1] == "heads":
        head_sheet(); return
    if len(sys.argv) > 1 and sys.argv[1] == "variants":
        variant_sheet(); return
    names = ["smile", "cheer", "frown"]
    faces = [make(n) for n in names]
    for n, rows in zip(names, faces):
        assert len(rows) == H and all(len(r) == W for r in rows), n
        bad = {c for r in rows for c in r if c != "." and c not in PAL}
        assert not bad, (n, bad)
    render(faces, 10).save(os.path.join(OUT, "faces.png"))
    # 小さい見え方: 44pt 枠 = 32 ドットで 1 ドット ≒ 1.4pt → Retina 2x で ≒ 2.75px。2px と 4px を出す
    small = Image.new("RGB", (3 * (W * 4 + 16) + 16, H * 4 + 16 + H * 2 + 32), (255, 255, 255))
    small.paste(render(faces, 4), (0, 0))
    small.paste(render(faces, 2), (0, H * 4 + 32))
    small.save(os.path.join(OUT, "faces-small.png"))
    old = {
        "smile": [".....KKKKKK.....", "...KKHHSSHHKK...", "..KHHhSSSShHHK..", "..KHhSSSSSShHK..", ".KHhShhSSSShhSHK",
                  ".KHhSQESSSSQESHK", ".KhSSSSSsSSSSShK", ".KsSSCSSSSSSCSsK", ".KsSSShhHHhhSSsK", "..KsSShMMMMhSsK.",
                  "..KKsSSQQQQSsKK.", "....KsSSSSSsK...", ".....KKssKKK....", ".......KKK......", "................"],
        "cheer": [".....KKKKKK.....", "...KKHHSSHHKK...", "..KHHhSSSShHHK..", "..KHhSSSSSShHK..", ".KHhShhSSSShhSHK",
                  ".KHhSQESSSSQESHK", ".KhSSSSSsSSSSShK", ".KsSSCSSSSSSCSsK", ".KsSSShhHHhhSSsK", "..KsSShMMMMhSsK.",
                  "..KKsMMMMMMMsKK.", "....KsQQQQQsK...", ".....KKssKKK....", ".......KKK......", "................"],
        "frown": [".....KKKKKK.....", "...KKHHSSHHKK...", "..KHHhSSSShHHK..", "..KHhSSSSSShHK..", ".KHhSSShhShhSSHK",
                  ".KHhSQESSSSQESHK", ".KhSSSSSsSSSSShK", ".KsSSCSSSSSSCSsK", ".KsSSShhHHhhSSsK", "..KsSShhhhhhSsK.",
                  "..KKsSMMMMMSsKK.", "....KsSSSSSsK...", ".....KKssKKK....", ".......KKK......", "................"],
    }
    def render_any(rows_list, scale, gap=16, plate=(220, 238, 249)):
        w0, h0 = len(rows_list[0][0]), len(rows_list[0])
        img = Image.new("RGB", (len(rows_list) * (w0 * scale + gap) + gap, h0 * scale + gap * 2), (255, 255, 255))
        px = img.load()
        for i, rows in enumerate(rows_list):
            ox = gap + i * (w0 * scale + gap); oy = gap
            for y in range(h0):
                for x in range(w0):
                    ch = rows[y][x]
                    col = plate if ch == "." else rgb(PAL[ch])
                    for dy in range(scale):
                        for dx in range(scale):
                            px[ox + x * scale + dx, oy + y * scale + dy] = col
        return img
    top = render_any([old[n] for n in names], 20)
    bottom = render(faces, 10)
    cmp = Image.new("RGB", (max(top.width, bottom.width), top.height + bottom.height), (255, 255, 255))
    cmp.paste(top, (0, 0)); cmp.paste(bottom, (0, top.height))
    cmp.save(os.path.join(OUT, "final-compare.png"))
    with open(os.path.join(OUT, "rows.txt"), "w") as f:
        for n, rows in zip(names, faces):
            f.write(f"    // {n} {W}x{H}\n    static let {n}Rows: [String] = [\n")
            for r in rows:
                f.write(f'        "{r}",\n')
            f.write("    ]\n")
    print("\n".join(faces[0]))


if __name__ == "__main__":
    main()
