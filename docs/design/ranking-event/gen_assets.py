#!/usr/bin/env python3
"""シーン E の案 A/B/C 用の絵素材を純 Python で描く（PIL 無し・raw RGBA → ffmpeg で PNG/連番に）。"""
import math, os, random, struct, subprocess, sys

W = "/private/tmp/claude-501/-Users-yamadahiroki-myspace-game-collection/792b949b-8dc6-4021-8001-08a2ed00cbe0/scratchpad/event-video/work"
FPS = 30
THEME = [(0xFF, 0x6F, 0x61), (0x22, 0xC3, 0xBE), (0x8C, 0x7B, 0xE0), (0xFF, 0xC2, 0x4B), (0xFF, 0x8F, 0xB1), (0xFF, 0xFF, 0xFF)]


def to_png(raw, w, h, out):
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgba", "-s", f"{w}x{h}", "-i", "-",
                    "-frames:v", "1", "-update", "1", out], input=raw, check=True)


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.buf = bytearray(w * h * 4)

    def put(self, x, y, c, a=255):
        if 0 <= x < self.w and 0 <= y < self.h:
            i = (y * self.w + x) * 4
            if a >= 255:
                self.buf[i:i + 4] = bytes((c[0], c[1], c[2], 255))
            else:
                # 上に重ねる（source-over）
                da = self.buf[i + 3]
                oa = a + da * (255 - a) // 255
                if oa == 0:
                    return
                for k in range(3):
                    self.buf[i + k] = min(255, (c[k] * a + self.buf[i + k] * da * (255 - a) // 255) // oa)
                self.buf[i + 3] = min(255, oa)

    def disc(self, cx, cy, r, c, soft=1.5, alpha=255):
        m = r + soft + 2
        for y in range(int(cy - m), int(cy + m + 1)):
            for x in range(int(cx - m), int(cx + m + 1)):
                d = math.hypot(x - cx, y - cy) - r
                if d < soft:
                    a = alpha if d <= 0 else int(alpha * (1 - d / soft))
                    self.put(x, y, c, a)

    def ring(self, cx, cy, r, width, c, alpha=255):
        for y in range(int(cy - r - width - 2), int(cy + r + width + 3)):
            for x in range(int(cx - r - width - 2), int(cx + r + width + 3)):
                d = abs(math.hypot(x - cx, y - cy) - r)
                if d < width:
                    a = int(alpha * (1 - d / width))
                    self.put(x, y, c, a)

    def polygon(self, pts, c, alpha=255):
        ys = [p[1] for p in pts]
        for y in range(int(min(ys)), int(max(ys)) + 1):
            xs = []
            n = len(pts)
            for i in range(n):
                (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % n]
                if (y0 <= y < y1) or (y1 <= y < y0):
                    xs.append(x0 + (y - y0) * (x1 - x0) / (y1 - y0))
            xs.sort()
            for j in range(0, len(xs) - 1, 2):
                for x in range(int(xs[j]), int(xs[j + 1]) + 1):
                    self.put(x, y, c, alpha)

    def rot_rect(self, cx, cy, w, h, ang, c, sx=1.0):
        ca, sa = math.cos(ang), math.sin(ang)
        hw, hh = w * sx / 2, h / 2
        pts = [(cx + ca * dx - sa * dy, cy + sa * dx + ca * dy) for dx, dy in ((-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh))]
        self.polygon(pts, c)


def rnd(i, k):
    random.seed(i * 7919 + k * 104729)
    return random.random()


def confetti(frames, w=540, h=960, pieces=80, out=f"{W}/confetti_540.rgba", speed=1.0):
    """紙吹雪の連番（raw RGBA）。上から降ってひらひら。"""
    with open(out, "wb") as f:
        for n in range(frames):
            t = n / FPS
            cv = Canvas(w, h)
            for i in range(pieces):
                r = [rnd(i, k) for k in range(8)]
                # 最初から画面全体に散らばっていて、下に抜けたら上から降り直す
                y = (t * speed * (150 + 120 * r[1]) + h * r[2]) % (h + 60) - 30
                x = w * r[0] + math.sin(t * (2 + r[3] * 2) + r[3] * 6.28) * 12
                ang = t * (2.5 + r[4] * 4) + r[5] * 6.28
                pw, ph = 4 + 3 * r[6], 6 + 5 * r[7]
                sx = max(0.15, abs(math.cos(t * (4 + r[6] * 3) + r[2] * 6.28)))
                cv.rot_rect(x, y, pw, ph, ang, THEME[i % len(THEME)], sx)
            f.write(cv.buf)
    print("confetti", frames, "frames ->", out)


def moon(size=560, out=f"{W}/moon.png"):
    cv = Canvas(size, size)
    c = size / 2
    r = size * 0.46
    # ほのかな光彩
    for k in range(6):
        cv.disc(c, c, r + 8 + k * 9, (0xFF, 0xF1, 0xB8), soft=10, alpha=22)
    cv.disc(c, c, r, (0xFF, 0xF1, 0xB8), soft=2)
    # 右下に影（球感）
    for k in range(20):
        cv.disc(c + r * 0.25 + k * 2, c + r * 0.25 + k * 2, r * 0.9, (0xE8, 0xD2, 0x8A), soft=30, alpha=5)
    # クレーター
    for (dx, dy, rr) in ((-0.3, -0.2, 0.13), (0.25, -0.35, 0.09), (0.1, 0.25, 0.16), (-0.4, 0.3, 0.08), (0.45, 0.15, 0.07)):
        cv.disc(c + dx * r, c + dy * r, rr * r, (0xE4, 0xCF, 0x8E), soft=3, alpha=170)
        cv.disc(c + dx * r - rr * r * 0.2, c + dy * r - rr * r * 0.2, rr * r * 0.75, (0xF4, 0xE2, 0xA6), soft=3, alpha=120)
    to_png(bytes(cv.buf), size, size, out)
    print("moon ->", out)


def stars(w=1080, h=1920, out=f"{W}/stars.png"):
    cv = Canvas(w, h)
    random.seed(42)
    for i in range(260):
        x, y = random.random() * w, random.random() * h * 0.8
        rr = random.choice((1.0, 1.0, 1.4, 1.8, 2.4))
        a = random.randint(120, 255)
        cv.disc(x, y, rr, (0xFF, 0xFF, 0xFF), soft=1.2, alpha=a)
    to_png(bytes(cv.buf), w, h, out)
    print("stars ->", out)


def ball(size=120, out=f"{W}/ball.png"):
    cv = Canvas(size * 3, size)
    # 尾（左へ伸びる光）
    for k in range(60):
        a = int(120 * (1 - k / 60))
        cv.disc(size * 3 - size / 2 - k * 3.6, size / 2, size * 0.22 * (1 - k / 80), (0xFF, 0xF6, 0xC8), soft=4, alpha=a)
    cv.disc(size * 3 - size / 2, size / 2, size * 0.3, (0xFF, 0xFF, 0xFF), soft=2)
    # 縫い目
    for k in range(-8, 9):
        cv.put(int(size * 3 - size / 2 - size * 0.12 + k * 0.6), int(size / 2 + k * 1.6), (0xE0, 0x40, 0x40))
        cv.put(int(size * 3 - size / 2 + size * 0.12 - k * 0.6), int(size / 2 + k * 1.6), (0xE0, 0x40, 0x40))
    to_png(bytes(cv.buf), size * 3, size, out)
    print("ball ->", out)


def flash(size=900, out=f"{W}/flash_ring.png"):
    cv = Canvas(size, size)
    cv.ring(size / 2, size / 2, size * 0.42, 26, (0xFF, 0xFF, 0xFF))
    cv.disc(size / 2, size / 2, size * 0.2, (0xFF, 0xFF, 0xFF), soft=size * 0.12, alpha=200)
    to_png(bytes(cv.buf), size, size, out)
    print("flash ->", out)


def crown(w=420, h=300, out=f"{W}/crown.png"):
    cv = Canvas(w, h)
    y = (0xFF, 0xC2, 0x4B)
    dark = (0xE0, 0x9A, 0x1E)
    # 本体（3 つの山）
    base_y, top = h * 0.82, h * 0.22
    pts = [(w * 0.08, base_y), (w * 0.05, top + 20), (w * 0.3, h * 0.55), (w * 0.5, top - 20), (w * 0.7, h * 0.55), (w * 0.95, top + 20), (w * 0.92, base_y)]
    cv.polygon(pts, y)
    # 下の帯
    cv.polygon([(w * 0.08, base_y - 36), (w * 0.92, base_y - 36), (w * 0.92, base_y + 10), (w * 0.08, base_y + 10)], dark)
    # 先端の玉と宝石
    for px in (w * 0.05, w * 0.5, w * 0.95):
        cv.disc(px, (top + 20) if px != w * 0.5 else top - 20, 22, y, soft=2)
    cv.disc(w * 0.5, h * 0.62, 24, (0xFF, 0x6F, 0x61), soft=2)
    cv.disc(w * 0.27, h * 0.68, 15, (0x22, 0xC3, 0xBE), soft=2)
    cv.disc(w * 0.73, h * 0.68, 15, (0x8C, 0x7B, 0xE0), soft=2)
    to_png(bytes(cv.buf), w, h, out)
    print("crown ->", out)


if __name__ == "__main__":
    which = sys.argv[1:] or ["confetti", "moon", "stars", "ball", "flash", "crown"]
    for name in which:
        if name == "confetti":
            confetti(frames=int(3.6 * FPS), speed=1.3)
        else:
            globals()[name]()
