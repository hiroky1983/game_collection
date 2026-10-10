#!/usr/bin/env python3
"""App内イベント告知動画モック（柵越えおじさん 週間ランキング戦 開幕）を ffmpeg で組む。

usage: build.py portrait|card [--no-text]
"""
import os, subprocess, sys, shutil

S = "/private/tmp/claude-501/-Users-yamadahiroki-myspace-game-collection/792b949b-8dc6-4021-8001-08a2ed00cbe0/scratchpad"
OUT = f"{S}/event-video"
W = f"{OUT}/work"
RAW_HR = f"{OUT}/rec/homerun_just.mp4"                  # 1206x2622 実録画・ジャストミートの場外 175 m（会長指示 1・2026-10-10）
RANK = f"{OUT}/rec/rank_top.mp4"                        # 1206x2622 入れ替えアニメ B 案・9 位→1 位＋祝福（会長指示 2）
OJISAN = f"{W}/ojisan.png"                               # 1254x1254 3D 静止画
FACES = f"{W}/faces.png"                                 # 表情一覧 1536x1024
F8 = f"{W}/hiraW8.ttc"
F6 = f"{W}/hiraW6.ttc"
FPS = 30

mode = sys.argv[1] if len(sys.argv) > 1 else "portrait"
TEXT = "--no-text" not in sys.argv
PORTRAIT = mode == "portrait"
VW, VH = (1080, 1920) if PORTRAIT else (1920, 1080)
tag = ("p" if PORTRAIT else "c") + ("" if TEXT else "_notext")
os.makedirs(W, exist_ok=True)

NAVY = "0x15306E"
E_VARIANT = os.environ.get("E_VARIANT", "")      # 締め（E）の案: '' = 現行, 'A' / 'B' / 'C'
VAR_SUFFIX = f"_{E_VARIANT}" if E_VARIANT else ""
YEL = "0xFFD54A"
RED = "0xF26B5B"


def run(args, desc=""):
    r = subprocess.run(args, capture_output=True, text=True)
    if r.returncode != 0:
        print("FAILED:", desc, "\n", " ".join(args), "\n", r.stderr[-3000:])
        sys.exit(1)


def text_png(name, text, size, color="white", font=F8, border=0, bcolor="black",
             shadow=0, w=None, h=None, line_spacing=10):
    """透明キャンバスに文字を描いた PNG を作る（アニメ用の素材）。"""
    w = w or (VW if PORTRAIT else 1400)
    h = h or int(size * (text.count("\n") + 1) * 1.45 + 60)
    tf = f"{W}/t_{name}.txt"
    with open(tf, "w") as f:
        f.write(text)
    dt = (f"drawtext=fontfile={font}:textfile={tf}:fontsize={size}:fontcolor={color}"
          f":x=(w-text_w)/2:y=(h-text_h)/2:line_spacing={line_spacing}")
    if border:
        dt += f":borderw={border}:bordercolor={bcolor}"
    if shadow:
        dt += f":shadowx={shadow}:shadowy={shadow}:shadowcolor=black@0.45"
    out = f"{W}/t_{name}_{tag}.png"
    run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
         f"color=c=black@0.0:s={w}x{h}:d=1,format=rgba", "-vf", dt + ",format=rgba",
         "-frames:v", "1", "-update", "1", out], f"text {name}")
    return out, w, h


def face_png(name, x, y, cw=270, ch=118):
    """表情一覧から 1 コマ切り出し、灰色背景を抜く。"""
    out = f"{W}/face_{name}.png"
    run(["ffmpeg", "-v", "error", "-y", "-i", FACES, "-vf",
         f"crop={cw}:{ch}:{x}:{y},colorkey=0x676767:0.10:0.10,format=rgba",
         "-frames:v", "1", "-update", "1", out], f"face {name}")
    return out


class Scene:
    """1 シーン = ベース映像 + 重ねる PNG 群。ffmpeg を 1 回呼んで mp4 にする。"""

    def __init__(self, name, dur, base_count=1):
        self.name, self.dur = name, dur
        self.base_count = base_count   # base_inputs に含める入力の数（PNG の入力番号はこの後ろから）
        self.inputs = []     # ffmpeg 入力引数の塊
        self.chain = []      # filter_complex 行
        self.layers = []     # (label, filter) 重ねる順

    def add_png(self, path):
        idx = len(self.inputs) + self.base_count
        self.inputs.append(["-loop", "1", "-framerate", str(FPS), "-t", str(self.dur), "-i", path])
        return f"[{idx}:v]"

    def pop(self, png, w, h, t0, y, x="(W-w)/2", scale_from=2.2, dur=0.18, hold=None, pre=""):
        """ドンと叩きつける登場（大→等倍）。y は PNG 中心の位置。"""
        src = self.add_png(png)
        lab = f"l{len(self.layers)}"
        p = f"((t-{t0})/{dur})"
        s = f"if(lt({p},1),1+{scale_from - 1}*(1-{p}),1)"
        self.chain.append(f"{src}{pre}scale=w='iw*{s}':h='ih*{s}':eval=frame[{lab}]")
        en = f"gte(t,{t0})" if hold is None else f"between(t,{t0},{t0 + hold})"
        self.layers.append((lab, f"overlay=x='{x}':y='{y}-h/2':enable='{en}'"))

    def fade_in(self, png, w, h, t0, y, x="(W-w)/2", dur=0.3, hold=None, slide=0):
        """ふわっと（＋少し上にスライドして）出る。"""
        src = self.add_png(png)
        lab = f"l{len(self.layers)}"
        self.chain.append(f"{src}format=rgba,fade=t=in:st={t0}:d={dur}:alpha=1[{lab}]")
        en = f"gte(t,{t0})" if hold is None else f"between(t,{t0},{t0 + hold})"
        yy = f"{y}-h/2+{slide}*max(0,1-(t-{t0})/{dur})"
        self.layers.append((lab, f"overlay=x='{x}':y='{yy}':enable='{en}'"))

    def layer(self, png, pre, overlay):
        """任意の前処理フィルタ `pre`（空可）と overlay の引数で PNG を重ねる。"""
        src = self.add_png(png)
        lab = f"l{len(self.layers)}"
        self.chain.append(f"{src}{pre}format=rgba[{lab}]" if pre else f"{src}format=rgba[{lab}]")
        self.layers.append((lab, overlay))

    def render(self, base_inputs, base_filter):
        """base_inputs: ['-i', ...] 等。base_filter: '[0:v]...' で終端ラベル [base] を作る。"""
        fc = [base_filter] + self.chain
        cur = "[base]"
        for i, (lab, f) in enumerate(self.layers):
            nxt = f"[o{i}]"
            fc.append(f"{cur}[{lab}]{f}{nxt}")
            cur = nxt
        fc.append(f"{cur}format=yuv420p[out]")
        out = f"{W}/scene_{self.name}_{tag}{VAR_SUFFIX if self.name == 'e' else ''}.mp4"
        only = os.environ.get("ONLY")
        if only and self.name not in only.split(",") and os.path.exists(out):
            return out   # 既存のシーンを使い回す（ONLY=c などで指定シーンだけ作り直す）
        args = ["ffmpeg", "-v", "error", "-y"] + base_inputs
        for i in self.inputs:
            args += i
        args += ["-filter_complex", ";".join(fc), "-map", "[out]", "-t", str(self.dur),
                 "-r", str(FPS), "-c:v", "libx264", "-preset", "fast", "-crf", "16",
                 "-pix_fmt", "yuv420p", "-an", out]
        run(args, f"scene {self.name}")
        return out


def phone_in_landscape(src_label, out_label, src_w, src_h, x_phone=1230):
    """縦録画を横カードに置く: 背景は同じ映像をぼかして敷き、右側に端末画面を置く。"""
    ph_w = int(1080 * src_w / src_h) // 2 * 2
    return (f"{src_label}split[bgsrc][fgsrc];"
            f"[bgsrc]scale=1920:-2,crop=1920:1080,boxblur=40:8,eq=brightness=-0.25:saturation=0.8[bg];"
            f"[fgsrc]scale={ph_w}:1080[fg];"
            f"[bg][fg]overlay=x={x_phone}:y=0{out_label}")


# ---------------------------------------------------------------- シーン A: おじさん 3D 静止画 + 開幕
def scene_a():
    dur = 3.2
    sc = Scene("a", dur)
    n = int(dur * FPS)
    big = 2700
    if PORTRAIT:
        pw, ph = big, 4800            # 9:16 に上下パディング
        pad = f"pad={pw}:{ph}:0:{(ph - big) // 2}:color={NAVY}"
        off_x, off_y = 0, (ph - big) // 2
        ball = (2261, 230 / 1254 * big + off_y)
        face = (900, 560 / 1254 * big + off_y)
    else:
        pw, ph = 4800, big            # 16:9 に左右パディング
        pad = f"pad={pw}:{ph}:{(pw - big) // 2}:0:color={NAVY}"
        off_x, off_y = (pw - big) // 2, 0
        ball = (1050 / 1254 * big + off_x, 230 / 1254 * big)
        face = (560 / 1254 * big + off_x, 520 / 1254 * big)
    # 0〜1.1 秒: ボールのどアップから引く（イーズアウト）、以降ゆっくり顔へ寄る
    z0, z1, z2 = 3.0, 1.86, 2.05
    n1 = int(1.1 * FPS)
    e1 = f"(1-pow(1-min(on/{n1},1),3))"
    e2 = f"max(0,(on-{n1})/({n}-{n1}))"
    z = f"if(lt(on,{n1}),{z0}+({z1}-{z0})*{e1},{z1}+({z2}-{z1})*{e2})"
    cx = f"{ball[0]}+({face[0]}-{ball[0]})*(1-pow(1-min(on/{n1},1),3))"
    cy = f"{ball[1]}+({face[1]}-{ball[1]})*(1-pow(1-min(on/{n1},1),3))"
    base = (f"[0:v]scale={big}:{big}:flags=lanczos,{pad},"
            f"zoompan=z='{z}':x='clip(({cx})-(iw/zoom)/2,{off_x},{off_x}+{big}-iw/zoom)'"
            f":y='clip(({cy})-(ih/zoom)/2,{off_y},{off_y}+{big}-ih/zoom)'"
            f":d={n}:s={VW}x{VH}:fps={FPS},"
            f"fade=t=in:st=0:d=0.2:color=white[base]")
    if TEXT:
        if PORTRAIT:
            p1, w1, h1 = text_png("a1", "週間ランキング戦", 128, "white", F8, border=10, bcolor=NAVY, shadow=8)
            p2, w2, h2 = text_png("a2", "開幕！", 230, YEL, F8, border=14, bcolor=RED, shadow=10)
            sc.pop(p1, w1, h1, 1.05, 1000)
            sc.pop(p2, w2, h2, 1.35, 1250, scale_from=2.8)
        else:
            p1, w1, h1 = text_png("a1", "週間ランキング戦", 120, "white", F8, border=10, bcolor=NAVY, shadow=8, w=1100)
            p2, w2, h2 = text_png("a2", "開幕！", 220, YEL, F8, border=14, bcolor=RED, shadow=10, w=1100)
            sc.pop(p1, w1, h1, 1.05, 330, x="W*0.30-w/2")
            sc.pop(p2, w2, h2, 1.35, 560, x="W*0.30-w/2", scale_from=2.8)
    return sc.render(["-loop", "1", "-framerate", str(FPS), "-t", str(dur), "-i", OJISAN], base)


# ---------------------------------------------------------------- シーン B: 実際のホームラン録画
def scene_b():
    # 1 球目（ジャストミート・場外 175 m センター）: 31.8 構え→33.0 振り | 33.0–33.7 閃光・ヒットストップ（等速）|
    # 飛行 2.4 倍速 | 37.2 場外！カード 1.2 秒 | 10 球の結果（エクセレント！8 本 1,402 m ニューレコード）0.9 秒＋最後のコマ 0.7 秒止め
    parts = [(31.8, 33.0, 1.0, 0), (33.0, 33.7, 1.0, 0), (33.7, 37.2, 2.4, 0), (37.2, 38.4, 1.0, 0), (99.65, 100.55, 1.0, 0.7)]
    dur = round(sum((b - a) / s + hold for a, b, s, hold in parts), 2)
    sc = Scene("b", dur)
    fc = []
    for i, (a, b, s, hold) in enumerate(parts):
        pad = f",tpad=stop_mode=clone:stop_duration={hold}" if hold else ""
        fc.append(f"[0:v]trim={a}:{b},setpts=(PTS-STARTPTS)/{s}{pad}[b{i}]")
    fc.append("".join(f"[b{i}]" for i in range(len(parts))) + f"concat=n={len(parts)}:v=1:a=0,fps={FPS}[cat]")
    if PORTRAIT:
        fc.append("[cat]scale=1080:-2,crop=1080:1920:0:140[base]")
    else:
        fc.append(phone_in_landscape("[cat]", "[base]", 1206, 2622))
    if TEXT:
        if PORTRAIT:
            p1, w1, h1 = text_png("b1", "実際のゲーム画面", 44, "white", F6, border=4, bcolor="black@0.6")
            sc.fade_in(p1, w1, h1, 0.0, 1800, dur=0.2)
            p2, w2, h2 = text_png("b2", "飛ばせ！", 150, YEL, F8, border=12, bcolor=RED, shadow=8)
            sc.pop(p2, w2, h2, 2.0, 1250, hold=1.4, scale_from=2.5)
        else:
            p1, w1, h1 = text_png("b1", "実際のゲーム画面", 40, "white", F6, border=4, bcolor="black@0.6", w=1100)
            sc.fade_in(p1, w1, h1, 0.0, 1000, x="W*0.30-w/2", dur=0.2)
            p2, w2, h2 = text_png("b2", "飛ばせ！", 170, YEL, F8, border=12, bcolor=RED, shadow=8, w=1100)
            sc.pop(p2, w2, h2, 2.0, 480, x="W*0.30-w/2", hold=1.4, scale_from=2.5)
            p3, w3, h3 = text_png("b3", "柵を越えたら\n飛距離が記録に", 78, "white", F8, border=8, bcolor=NAVY, w=1100)
            sc.pop(p3, w3, h3, 3.45, 480, x="W*0.30-w/2")
    return sc.render(["-i", RAW_HR], ";".join(fc))


# ---------------------------------------------------------------- シーン C: ランキングの入れ替えアニメ（B 案）
def scene_c():
    # 1.9s 静止（9 位）→ 数え上げ → 1 位へ飛び上がる → 5.0s 王冠と「1位！」が弾け、紙吹雪
    a, b = 1.9, 7.2
    dur = round(b - a, 2)
    sc = Scene("c", dur)
    fc = [f"[0:v]trim={a}:{b},setpts=PTS-STARTPTS,fps={FPS}[cat]"]
    if PORTRAIT:
        fc.append("[cat]scale=1080:-2,crop=1080:1920:0:140[base]")
    else:
        fc.append(phone_in_landscape("[cat]", "[base]", 1206, 2622))
    if TEXT:
        if PORTRAIT:
            p1, w1, h1 = text_png("c1", "今週、あなたは何位？", 86, "white", F8, border=10, bcolor=NAVY, shadow=6)
            sc.pop(p1, w1, h1, 0.15, 75)
            p2, w2, h2 = text_png("c2", "全国のおじさんと飛距離で勝負", 54, YEL, F8, border=6, bcolor=NAVY)
            sc.fade_in(p2, w2, h2, 3.3, 1700, dur=0.25, slide=30)
        else:
            p1, w1, h1 = text_png("c1", "今週、あなたは\n何位？", 120, "white", F8, border=10, bcolor=NAVY, shadow=6, w=1100)
            sc.pop(p1, w1, h1, 0.15, 420, x="W*0.30-w/2")
            p2, w2, h2 = text_png("c2", "全国のおじさんと飛距離で勝負", 56, YEL, F8, border=6, bcolor=NAVY, w=1100)
            sc.fade_in(p2, w2, h2, 3.3, 690, x="W*0.30-w/2", dur=0.25, slide=30)
    return sc.render(["-i", RANK], ";".join(fc))


# ---------------------------------------------------------------- シーン D: ルール 3 行 + 表情
def scene_d():
    dur = 4.0
    sc = Scene("d", dur)
    base = f"[0:v]format=yuv420p[base]"
    # 表情は罫線を埋めた一覧から余白ごと切り出した PNG（work/face2_*.png・顎まで入っている・#1995 会長指摘 3）
    fp = {n: f"{W}/face2_{n}.png" for n in ("normal", "surprise", "smile")}
    if PORTRAIT:
        lines = [("d1", "毎週月曜に\nリセット", 0.0, 380),
                 ("d2", "1ゲーム10球の\n総飛距離で勝負", 0.9, 820),
                 ("d3", "月まで飛ばせ", 1.9, 1230)]
        for i, (n, t, t0, y) in enumerate(lines):
            big = i == 2
            p, w, h = text_png(n, t, 150 if big else 104, YEL if big else "white", F8,
                               border=12 if big else 0, bcolor=RED, shadow=8)
            sc.pop(p, w, h, t0, y, scale_from=2.6 if big else 1.8)
        # 表情: 真顔 → 驚き → 笑顔（右下）
        for i, (n, t0) in enumerate([("normal", 0.0), ("surprise", 0.9), ("smile", 1.9)]):
            hold = None if i == 2 else 0.9
            sc.pop(fp[n], 810, 0, t0, 1600, x="(W-w)/2", scale_from=1.6, hold=hold, pre="scale=810:-1:flags=lanczos,")
    else:
        lines = [("d1", "毎週月曜にリセット", 0.0, 250),
                 ("d2", "1ゲーム10球の総飛距離で勝負", 0.9, 470),
                 ("d3", "月まで飛ばせ", 1.9, 760)]
        for i, (n, t, t0, y) in enumerate(lines):
            big = i == 2
            p, w, h = text_png(n, t, 170 if big else 80, YEL if big else "white", F8,
                               border=12 if big else 0, bcolor=RED, shadow=8, w=1300)
            sc.pop(p, w, h, t0, y, x="W*0.33-w/2", scale_from=2.6 if big else 1.8)
        for i, (n, t0) in enumerate([("normal", 0.0), ("surprise", 0.9), ("smile", 1.9)]):
            hold = None if i == 2 else 0.9
            sc.pop(fp[n], 600, 0, t0, 540, x="W-w-60", scale_from=1.6, hold=hold, pre="scale=600:-1:flags=lanczos,")
    return sc.render(["-f", "lavfi", "-i", f"color=c={NAVY}:s={VW}x{VH}:r={FPS}:d={dur}"], base)


# ---------------------------------------------------------------- シーン E: 締め（あそびば）
def scene_e():
    dur = 2.6
    sc = Scene("e", dur)
    base = f"[0:v]format=yuv420p[base]"
    if PORTRAIT:
        p1, w1, h1 = text_png("e1", "あそびば", 190, "white", F8, shadow=8)
        sc.pop(p1, w1, h1, 0.1, 880, scale_from=1.6)
        p2, w2, h2 = text_png("e2", "柵越えおじさん 週間ランキング戦", 60, YEL, F8)
        sc.fade_in(p2, w2, h2, 0.5, 1060, dur=0.3, slide=30)
        p3, w3, h3 = text_png("e3", "ランキングは予告なく終了する場合があります", 30, "white@0.7", F6)
        sc.fade_in(p3, w3, h3, 0.8, 1850, dur=0.3)
    else:
        p1, w1, h1 = text_png("e1", "あそびば", 200, "white", F8, shadow=8, w=1200)
        sc.pop(p1, w1, h1, 0.1, 470, x="W*0.33-w/2", scale_from=1.6)
        p2, w2, h2 = text_png("e2", "柵越えおじさん 週間ランキング戦", 64, YEL, F8, w=1200)
        sc.fade_in(p2, w2, h2, 0.5, 650, x="W*0.33-w/2", dur=0.3, slide=30)
        p3, w3, h3 = text_png("e3", "ランキングは予告なく終了する場合があります", 30, "white@0.7", F6, w=1200)
        sc.fade_in(p3, w3, h3, 0.8, 800, x="W*0.33-w/2", dur=0.3)
    src = sc.add_png(f"{W}/ojisan.png")
    # おじさんの絵を小さく下（横は右）に
    if PORTRAIT:
        sc.chain.append(f"{src}scale=520:520,fade=t=in:st=0.3:d=0.3:alpha=1[oj]")
        sc.layers.append(("oj", "overlay=x=(W-w)/2:y=1480-h/2"))
    else:
        sc.chain.append(f"{src}scale=760:760,fade=t=in:st=0.3:d=0.3:alpha=1[oj]")
        sc.layers.append(("oj", "overlay=x=W-w-80:y=(H-h)/2"))
    return sc.render(["-f", "lavfi", "-i", f"color=c={NAVY}:s={VW}x{VH}:r={FPS}:d={dur}"], base)


# ---------------------------------------------------------------- 締めの案（会長指示 2026-10-10「最後のコマがショボい」）
RAYS_CX, RAYS_CY = (540, 760) if PORTRAIT else (960, 540)


def rays_and_confetti(dur, rays_alpha=0.16, rays_speed=1.2, rays_n=14, confetti=True, bg=None):
    """紺地＋回る放射（黄）＋紙吹雪（gen_assets.py の連番）のベース。戻り値: (base_inputs, base_filter 先頭部, base_count)。"""
    bgsrc = bg or f"color=c={NAVY}:s={VW}x{VH}:r={FPS}:d={dur}"
    inputs = ["-f", "lavfi", "-i", bgsrc]
    count = 1
    fc = (f"color=c=0xFFC24B:s={VW}x{VH}:r={FPS}:d={dur}[yel];"
          f"color=c=gray:s={VW}x{VH}:r={FPS}:d={dur},format=gray,"
          f"geq=lum='255*gt(sin({rays_n}*atan2(Y-{RAYS_CY},X-{RAYS_CX})+T*{rays_speed}),0)*max(0,1-hypot(X-{RAYS_CX},Y-{RAYS_CY})/1150)'[mask];"
          f"[yel][mask]alphamerge,format=rgba,colorchannelmixer=aa={rays_alpha}[rays];"
          f"[0:v][rays]overlay=0:0[bg0]")
    last = "[bg0]"
    if confetti:
        inputs += ["-f", "rawvideo", "-pix_fmt", "rgba", "-s", "540x960", "-r", str(FPS), "-i", f"{W}/confetti_540.rgba"]
        if PORTRAIT:
            fc += f";[1:v]scale={VW}:{VH}:flags=bilinear,format=rgba[conf];[bg0][conf]overlay=0:0[bg1]"
        else:
            # 縦の連番を正方形に切って 2 枚並べ、横幅に合わせる
            fc += (";[1:v]scale=1080:1920:flags=bilinear,crop=1080:1080:0:420,split[c1][c2];[c1][c2]hstack,"
                   f"crop={VW}:{VH}:120:0,format=rgba[conf];[bg0][conf]overlay=0:0[bg1]")
        last = "[bg1]"
        count = 2
    return inputs, fc, last, count


def scene_e_A():
    """案 A: 野球のおじさんの 3D 静止画をドンと出す。放射＋紙吹雪、大きくタイトル、「毎週月曜スタート」、最後に「あそびば」。"""
    dur = 3.2
    inputs, fc, last, count = rays_and_confetti(dur)
    sc = Scene("e", dur, base_count=count)
    base = fc + f";{last}format=yuv420p[base]"
    if PORTRAIT:
        sc.pop(f"{W}/ojisan.png", 0, 0, 0.12, 700, scale_from=1.7, dur=0.22, pre="scale=860:860:flags=lanczos,")
        p1, w1, h1 = text_png("eA1", "柵越えおじさん", 100, "white", F8, border=10, bcolor=NAVY, shadow=6)
        sc.pop(p1, w1, h1, 0.55, 1270)
        p2, w2, h2 = text_png("eA2", "週間ランキング戦", 124, YEL, F8, border=12, bcolor=RED, shadow=8)
        sc.pop(p2, w2, h2, 0.75, 1415, scale_from=2.6)
        p3, w3, h3 = text_png("eA3", "毎週月曜スタート", 70, "white", F8, border=6, bcolor=NAVY)
        sc.fade_in(p3, w3, h3, 1.35, 1570, dur=0.25, slide=30)
        p4, w4, h4 = text_png("eA4", "あそびば", 120, "white", F8, shadow=8)
        sc.pop(p4, w4, h4, 1.95, 200, scale_from=1.8)
        p5, w5, h5 = text_png("eA5", "ランキングは予告なく終了する場合があります", 30, "white@0.75", F6)
        sc.fade_in(p5, w5, h5, 1.2, 1860, dur=0.3)
    else:
        # 横: 左に絵（780px）、右に文字の列
        sc.pop(f"{W}/ojisan.png", 0, 0, 0.12, 540, x="110", scale_from=1.7, dur=0.22, pre="scale=780:780:flags=lanczos,")
        cx = "1400-w/2"
        p1, w1, h1 = text_png("eA1", "柵越えおじさん", 92, "white", F8, border=10, bcolor=NAVY, shadow=6, w=1000)
        sc.pop(p1, w1, h1, 0.55, 400, x=cx)
        p2, w2, h2 = text_png("eA2", "週間ランキング戦", 112, YEL, F8, border=12, bcolor=RED, shadow=8, w=1000)
        sc.pop(p2, w2, h2, 0.75, 540, scale_from=2.6, x=cx)
        p3, w3, h3 = text_png("eA3", "毎週月曜スタート", 64, "white", F8, border=6, bcolor=NAVY, w=1000)
        sc.fade_in(p3, w3, h3, 1.35, 680, x=cx, dur=0.25, slide=30)
        p4, w4, h4 = text_png("eA4", "あそびば", 110, "white", F8, shadow=8, w=1000)
        sc.pop(p4, w4, h4, 1.95, 200, x=cx, scale_from=1.8)
        p5, w5, h5 = text_png("eA5", "ランキングは予告なく終了する場合があります", 28, "white@0.75", F6, w=1000)
        sc.fade_in(p5, w5, h5, 1.2, 1020, x=cx, dur=0.3)
    return sc.render(inputs, base)


def scene_e_B():
    """案 B: 打球が月に当たるオチ。夜空・星・月、打球が飛んで月に当たり閃光、「月まで飛ばせ！」→ ガッツポーズ → タイトル。"""
    dur = 3.6
    night = f"gradients=s={VW}x{VH}:c0=0x05091E:c1=0x1A2C66:x0=540:y0=0:x1=540:y1={VH}:r={FPS}:d={dur}"
    inputs = ["-f", "lavfi", "-i", night]
    sc = Scene("e", dur, base_count=1)
    base = "[0:v]format=yuv420p[base]"
    sc.layer(f"{W}/stars.png", "", "overlay=0:0")
    # 月（右上）。当たった直後 0.3 秒だけ揺れる
    mx, my = 560, 180
    hit = 0.85
    sc.layer(f"{W}/moon.png", "",
             f"overlay=x='{mx}+if(between(t,{hit},{hit + 0.3}),14*sin((t-{hit})*95)*(1-(t-{hit})/0.3),0)':"
             f"y='{my}+if(between(t,{hit},{hit + 0.3}),9*sin((t-{hit})*70)*(1-(t-{hit})/0.3),0)'")
    # 打球: 左下から月の中心へ、弧を描いて 0.85 秒で到達。尾は進行方向（右上）の反対へ
    bx0, by0, bx1, by1 = -260, 1560, mx + 280, my + 280
    p = f"min(1,max(0,t/{hit}))"
    sc.layer(f"{W}/ball.png", "rotate=-PI/4:ow=400:oh=400:c=black@0,scale=300:300,",
             f"overlay=x='{bx0}+({bx1}-{bx0})*{p}-150':y='{by0}+({by1}-{by0})*{p}-150-420*sin(PI*{p})':enable='lt(t,{hit})'")
    # 閃光の輪（当たった瞬間に広がって消える）
    fl = f"((t-{hit})/0.4)"
    sc.layer(f"{W}/flash_ring.png", f"scale=w='900*(0.25+1.6*min(1,max(0,{fl})))':h='900*(0.25+1.6*min(1,max(0,{fl})))':eval=frame,"
             f"format=rgba,fade=t=out:st={hit}:d=0.4:alpha=1,",
             f"overlay=x='{mx + 280}-w/2':y='{my + 280}-h/2':enable='between(t,{hit},{hit + 0.4})'")
    p1, w1, h1 = text_png("eB1", "月まで飛ばせ！", 136, YEL, F8, border=12, bcolor=RED, shadow=8)
    sc.pop(p1, w1, h1, hit + 0.1, 870, scale_from=2.8)
    # ガッツポーズのおじさん（左下）
    sc.pop(f"{W}/finale_good.png", 0, 0, 1.35, 1470, x="20", scale_from=1.5, dur=0.22, pre="scale=640:-1:flags=lanczos,")
    p2, w2, h2 = text_png("eB2", "柵越えおじさん\n週間ランキング戦", 72, "white", F8, border=8, bcolor=NAVY, shadow=6, w=560, line_spacing=14)
    sc.pop(p2, w2, h2, 1.9, 1250, x="800-w/2")
    p3, w3, h3 = text_png("eB3", "あそびば", 104, "white", F8, shadow=8, w=560)
    sc.pop(p3, w3, h3, 2.4, 1520, x="800-w/2", scale_from=1.8)
    p4, w4, h4 = text_png("eB4", "ランキングは予告なく終了する場合があります", 30, "white@0.75", F6)
    sc.fade_in(p4, w4, h4, 1.6, 1880, dur=0.3)
    return sc.render(inputs, base)


def scene_e_C():
    """案 C: 1 位の王冠を被った笑顔のおじさん＋「今週の 1 位はキミだ」→ タイトル。"""
    dur = 3.2
    inputs, fc, last, count = rays_and_confetti(dur, rays_alpha=0.14, rays_speed=0.9)
    sc = Scene("e", dur, base_count=count)
    base = fc + f";{last}format=yuv420p[base]"
    # 笑顔（900 幅）
    sc.pop(f"{W}/face2_smile.png", 0, 0, 0.12, 760, scale_from=1.7, dur=0.22, pre="scale=900:-1:flags=lanczos,")
    # 王冠が上から落ちて頭に乗る（0.5〜0.8 秒）→ 小さく弾む
    t0, ty = 0.5, 430
    pp = f"min(1,max(0,(t-{t0})/0.3))"
    bounce = f"if(gt(t,{t0 + 0.3}),-26*abs(sin((t-{t0 + 0.3})*14))*exp(-(t-{t0 + 0.3})*5),0)"
    sc.layer(f"{W}/crown.png", "scale=520:-1:flags=lanczos,",
             f"overlay=x='(W-w)/2':y='{ty}-h/2-900*pow(1-{pp},2)+{bounce}':enable='gte(t,{t0})'")
    p1, w1, h1 = text_png("eC1", "今週の 1 位は", 92, "white", F8, border=8, bcolor=NAVY, shadow=6)
    sc.pop(p1, w1, h1, 1.0, 1170)
    p2, w2, h2 = text_png("eC2", "キミだ", 170, YEL, F8, border=14, bcolor=RED, shadow=10)
    sc.pop(p2, w2, h2, 1.2, 1340, scale_from=2.8)
    p3, w3, h3 = text_png("eC3", "柵越えおじさん 週間ランキング戦", 58, "white", F8, border=6, bcolor=NAVY)
    sc.fade_in(p3, w3, h3, 1.85, 1540, dur=0.25, slide=30)
    p4, w4, h4 = text_png("eC4", "あそびば", 110, "white", F8, shadow=8)
    sc.pop(p4, w4, h4, 2.3, 1700, scale_from=1.8)
    p5, w5, h5 = text_png("eC5", "ランキングは予告なく終了する場合があります", 30, "white@0.75", F6)
    sc.fade_in(p5, w5, h5, 1.6, 1870, dur=0.3)
    return sc.render(inputs, base)


def main():
    e = {"A": scene_e_A, "B": scene_e_B, "C": scene_e_C}.get(E_VARIANT, scene_e)
    scenes = [scene_a(), scene_b(), scene_c(), scene_d(), e()]
    lst = f"{W}/concat_{tag}.txt"
    with open(lst, "w") as f:
        for s in scenes:
            f.write(f"file '{s}'\n")
    total = sum(float(subprocess.check_output(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", s])) for s in scenes)
    name = {"p": "event_portrait.mp4", "c": "event_card.mp4",
            "p_notext": "event_portrait_notext.mp4", "c_notext": "event_card_notext.mp4"}[tag]
    if E_VARIANT:
        name = name.replace(".mp4", f"_E{E_VARIANT}.mp4")
    out = f"{OUT}/{name}"
    # 末尾を白にフェードして冒頭の白フラッシュへループ
    run(["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", lst,
         "-vf", f"fade=t=out:st={total - 0.4:.2f}:d=0.4:color=white,format=yuv420p",
         "-r", str(FPS), "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-profile:v", "high",
         "-level", "4.2", "-pix_fmt", "yuv420p", "-color_primaries", "bt709", "-color_trc", "bt709",
         "-colorspace", "bt709", "-an", "-movflags", "+faststart", out], "final")
    print("OK", out, f"{total:.2f}s")


if __name__ == "__main__":
    main()
