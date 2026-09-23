// 柵越えおじさん（プレミアム枠・ホームラン案）のモック生成器（#1316）。
// macOS 上で `swiftc -O mock.swift -o mockgen && ./mockgen <出力ディレクトリ> [--3d]` で
// iPhone 実寸（393×852pt・@2x）の PNG を書き出す（`--3d` で 3D 方向の 21〜29 だけ）。アプリのビルドには一切使わない使い捨て。
// 01〜16 は初回・2 回目（ドット絵 / 滑らかな塗り）の記録。21〜29 が現行（会長決裁 2026-09-24: 絵柄は 3D・
// センターカメラで打者を正面に・ミート点の第 2 軸）。3D は透視投影 + トゥーン調 2D 部品の疑似 3D（末尾の MARK を参照）。
// ドット絵は OjisanPixel と同じパレットを使い、頭身（デフォルメ強度）を引数で変えて生成する。
import AppKit
import SwiftUI

// MARK: - パレット（Core の OjisanPixel.palette + 試作ブランチの中間色 + 本モックの追加色）

let palette: [Character: UInt32] = [
    "K": 0x2B2634, "S": 0xF2C8A0, "s": 0xD69E76, "W": 0xFAF6EC, "Y": 0xF0C030, "y": 0xC4901C,
    "B": 0x3E4E80, "b": 0x28345C, "H": 0x9696A2, "h": 0x626270, "E": 0x221E28, "R": 0xD43C2C,
    "r": 0x96241C, "T": 0x34343C, "t": 0x787882, "C": 0xE87860, "N": 0xAA763E, "G": 0x60586E,
    "M": 0x96282C, "Q": 0xFAF6EC, "X": 0x3C2828,
    "L": 0xFBE0BE, "p": 0xE8B88E, "d": 0xB57A52, "I": 0xC8C8D2, "m": 0x5E1418, "a": 0x6CB8E8,
    // 本モックの追加: 投手のユニフォーム・バットの陰・ボールの縫い目
    "U": 0xF4F2F6, "u": 0xC6C2CE, "n": 0x7A5228, "V": 0xD43C2C,
    // 方向A（高密度ドット絵）の追加: ヘルメットのハイライト・黄のハイライト・バットのハイライト
    "P": 0x5C6FA6, "Z": 0xF8DC7A, "o": 0xC89A5A,
]

func hexColor(_ v: UInt32, _ a: Double = 1) -> Color {
    Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255, opacity: a)
}

// MARK: - ドット絵キャンバス（図形合成 → 縁取り）

struct PixelCanvas {
    let w: Int, h: Int
    var g: [[Character]]
    init(w: Int, h: Int) { self.w = w; self.h = h; g = Array(repeating: Array(repeating: ".", count: w), count: h) }
    init(rows: [String]) { h = rows.count; w = rows[0].count; g = rows.map { Array($0) } }

    subscript(x: Int, y: Int) -> Character {
        get { (x >= 0 && y >= 0 && x < w && y < h) ? g[y][x] : "." }
        set { if x >= 0 && y >= 0 && x < w && y < h { g[y][x] = newValue } }
    }
    mutating func rect(_ x: Int, _ y: Int, _ rw: Int, _ rh: Int, _ c: Character) {
        for yy in y..<(y + rh) { for xx in x..<(x + rw) { self[xx, yy] = c } }
    }
    mutating func ellipse(cx: Double, cy: Double, rx: Double, ry: Double, _ c: Character) {
        for y in 0..<h { for x in 0..<w {
            let dx = (Double(x) + 0.5 - cx) / rx, dy = (Double(y) + 0.5 - cy) / ry
            if dx * dx + dy * dy <= 1 { self[x, y] = c }
        } }
    }
    func inEllipse(_ x: Int, _ y: Int, cx: Double, cy: Double, rx: Double, ry: Double) -> Bool {
        let dx = (Double(x) + 0.5 - cx) / rx, dy = (Double(y) + 0.5 - cy) / ry
        return dx * dx + dy * dy <= 1
    }
    mutating func line(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ c: Character, thick: Int = 1) {
        let dx = abs(x1 - x0), dy = -abs(y1 - y0), sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1
        var err = dx + dy, x = x0, y = y0
        while true {
            for t in 0..<thick { self[x + t, y] = c; if thick > 1 { self[x, y + t] = c } }
            if x == x1 && y == y1 { break }
            let e2 = 2 * err
            if e2 >= dy { err += dy; x += sx }
            if e2 <= dx { err += dx; y += sy }
        }
    }
    /// 透明で、上下左右のどれかが不透明なドットを縁取り色にする。
    mutating func outline(_ c: Character = "K") {
        var out = g
        for y in 0..<h { for x in 0..<w where g[y][x] == "." {
            if self[x - 1, y] != "." || self[x + 1, y] != "." || self[x, y - 1] != "." || self[x, y + 1] != "." { out[y][x] = c }
        } }
        g = out
    }
    mutating func blit(_ o: PixelCanvas, _ x: Int, _ y: Int) {
        for yy in 0..<o.h { for xx in 0..<o.w where o.g[yy][xx] != "." { self[x + xx, y + yy] = o.g[yy][xx] } }
    }
    func flipped() -> PixelCanvas { var c = self; c.g = g.map { $0.reversed() }; return c }
    var rows: [String] { g.map { String($0) } }
    /// 不透明部分の外接矩形で切り抜く（余白 1）。
    func trimmed() -> PixelCanvas {
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h { for x in 0..<w where g[y][x] != "." { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } }
        guard maxX >= 0 else { return self }
        var c = PixelCanvas(w: maxX - minX + 3, h: maxY - minY + 3)
        for y in minY...maxY { for x in minX...maxX { c[x - minX + 1, y - minY + 1] = g[y][x] } }
        return c
    }

    func cgImage(scale s: Int) -> CGImage? {
        let W = w * s, H = h * s
        var px = [UInt8](repeating: 0, count: W * H * 4)
        for y in 0..<h { for x in 0..<w {
            let ch = g[y][x]; guard ch != ".", let rgb = palette[ch] else { continue }
            let r = UInt8((rgb >> 16) & 0xFF), gg = UInt8((rgb >> 8) & 0xFF), b = UInt8(rgb & 0xFF)
            for dy in 0..<s { for dx in 0..<s {
                let i = ((y * s + dy) * W + (x * s + dx)) * 4
                px[i] = r; px[i + 1] = gg; px[i + 2] = b; px[i + 3] = 255
            } }
        } }
        guard let prov = CGDataProvider(data: Data(px) as CFData) else { return nil }
        return CGImage(width: W, height: H, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: W * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: prov, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

// MARK: - おじさん（正面・バッター）の生成器。頭身＝デフォルメ強度を引数で変える

struct Proportion {
    let name: String, sub: String
    let headW: Int, headH: Int, torsoW: Int, torsoH: Int, legH: Int
    let eyeW: Int, eyeH: Int, pupil: Int, browH: Int, mustacheH: Int, cheek: Int
}

/// L1: 現行の走者（頭 14 ドット・約 3 頭身）相当。L2: 2.5 頭身。L3: 2 頭身（ちびキャラ）。
let proportions: [Proportion] = [
    Proportion(name: "A 現行相当（約3頭身）", sub: "頭 14 ドット・走者と同じ比率", headW: 14, headH: 13, torsoW: 12, torsoH: 10, legH: 8, eyeW: 2, eyeH: 2, pupil: 1, browH: 1, mustacheH: 1, cheek: 1),
    Proportion(name: "B 中デフォルメ（2.5頭身）", sub: "頭 18 ドット・目を大きく", headW: 18, headH: 16, torsoW: 13, torsoH: 8, legH: 6, eyeW: 3, eyeH: 3, pupil: 2, browH: 2, mustacheH: 2, cheek: 2),
    Proportion(name: "C 強デフォルメ（2頭身）", sub: "頭 24 ドット・胴と脚を最小に", headW: 24, headH: 21, torsoW: 14, torsoH: 6, legH: 4, eyeW: 4, eyeH: 5, pupil: 2, browH: 2, mustacheH: 2, cheek: 2),
]

enum Pose { case stance, swing, cheer, frown }

func ojisan(_ p: Proportion, pose: Pose) -> PixelCanvas {
    let W = 60, H = 56
    var c = PixelCanvas(w: W, h: H)
    let shoeH = 2
    let legTop = H - 2 - shoeH - p.legH
    let torsoTop = legTop - p.torsoH
    let headBottom = torsoTop + 1
    let headTop = headBottom - p.headH
    let tcx = 24
    let hcx = Double(tcx), hcy = Double(headTop) + Double(p.headH) / 2
    let rx = Double(p.headW) / 2, ry = Double(p.headH) / 2

    // バット（体の後ろに来る部分を先に描く）
    let batLen = 20
    var hands = (x: tcx + p.torsoW / 2 + 2, y: torsoTop + 2)
    var batEnd = (x: hands.x + 7, y: hands.y - batLen)
    switch pose {
    case .stance:
        hands = (x: tcx + p.torsoW / 2 + 1, y: torsoTop + 1)
        batEnd = (x: hands.x + 8, y: hands.y - batLen + 2)
    case .swing:
        hands = (x: tcx + p.torsoW / 2 + 6, y: torsoTop + p.torsoH / 2)
        batEnd = (x: hands.x + batLen, y: hands.y + 1)
    case .cheer, .frown:
        // バットは足元に転がす
        c.line(tcx - 14, H - 3, tcx + 4, H - 3, "N", thick: 2)
        c.line(tcx - 14, H - 3, tcx - 10, H - 3, "X", thick: 2)
    }
    if pose == .stance || pose == .swing {
        c.line(hands.x, hands.y, batEnd.x, batEnd.y, "N", thick: 2)
        c.line(hands.x + 1, hands.y + 1, batEnd.x + 1, batEnd.y + 1, "n", thick: 1)
    }

    // 靴・脚・胴
    let torsoX = tcx - p.torsoW / 2 + (pose == .swing ? 1 : 0)
    c.rect(torsoX, legTop, p.torsoW, p.legH, "B")
    c.rect(torsoX, legTop, 1, p.legH, "b")
    c.rect(torsoX + p.torsoW / 2, legTop + max(1, p.legH / 2), 1, p.legH - max(1, p.legH / 2), "b") // 股
    c.rect(torsoX - 1, H - 2 - shoeH, p.torsoW / 2 + 1, shoeH, "T")
    c.rect(torsoX + p.torsoW / 2 + 1, H - 2 - shoeH, p.torsoW / 2 + 1, shoeH, "T")
    c.rect(torsoX, torsoTop, p.torsoW, p.torsoH, "Y")
    c.rect(torsoX, torsoTop, 1, p.torsoH, "y")
    c.rect(torsoX + p.torsoW - 1, torsoTop, 1, p.torsoH, "y")
    if p.torsoH >= 4 { c.rect(tcx - 1, torsoTop, 2, 2, "Q"); c[tcx - 2, torsoTop] = "Q"; c[tcx + 1, torsoTop] = "Q" }

    // 頭（肌 → 側頭の白髪 → 耳 → 眉・目・鼻・頬・ヒゲ・口）
    c.ellipse(cx: hcx, cy: hcy, rx: rx, ry: ry, "S")
    for y in 0..<H { for x in 0..<W where c.inEllipse(x, y, cx: hcx, cy: hcy, rx: rx, ry: ry) {
        let fx = (Double(x) + 0.5 - hcx) / rx, fy = (Double(y) + 0.5 - hcy) / ry
        if fy > -0.15 && fy < 0.45 && abs(fx) > 0.62 { c[x, y] = abs(fx) > 0.8 ? "h" : "H" }
        if fy > 0.86 { c[x, y] = "s" } // 顎の陰
        if fy < -0.55 && abs(fx) < 0.5 { c[x, y] = "L" } // 頭頂のハイライト（薄い頭）
    } }
    // 耳
    let earY = Int(hcy) - 1
    c.rect(Int(hcx - rx) - 1, earY, 2, max(2, p.headH / 6), "s")
    c.rect(Int(hcx + rx) - 1, earY, 2, max(2, p.headH / 6), "s")
    // 眉
    let browY = Int(hcy - ry * (p.headH >= 16 ? 0.34 : 0.46))
    let browW = max(3, p.headW / 4)
    let browOff = max(1, p.headW / 9)
    let browShift = (pose == .frown) ? 1 : 0
    c.rect(Int(hcx) - browOff - browW, browY + browShift, browW, p.browH, "h")
    c.rect(Int(hcx) + browOff, browY + browShift, browW, p.browH, "h")
    if pose == .frown { c[Int(hcx) - browOff - 1, browY] = "h"; c[Int(hcx) + browOff, browY] = "h" } // 内側を吊り上げて「困り眉」
    // 目
    let eyeY = browY + p.browH + 1
    let eyeOff = max(1, p.headW / 10)
    if pose == .frown {
        // ＞＜ の目（外側が上がる斜線）と、こめかみの汗
        let ey = eyeY + p.eyeH / 2
        c.line(Int(hcx) - eyeOff - p.eyeW, ey - 1, Int(hcx) - eyeOff - 1, ey, "E")
        c.line(Int(hcx) - eyeOff - p.eyeW, ey + 1, Int(hcx) - eyeOff - 1, ey, "E")
        c.line(Int(hcx) + eyeOff + p.eyeW - 1, ey - 1, Int(hcx) + eyeOff, ey, "E")
        c.line(Int(hcx) + eyeOff + p.eyeW - 1, ey + 1, Int(hcx) + eyeOff, ey, "E")
        let sx = Int(hcx + rx) + 1, sy = browY - 1
        c[sx, sy] = "a"; c[sx, sy + 1] = "a"; c[sx + 1, sy + 1] = "a"; c[sx, sy + 2] = "W"; c[sx + 1, sy + 2] = "a"
    } else {
        c.rect(Int(hcx) - eyeOff - p.eyeW, eyeY, p.eyeW, p.eyeH, "Q")
        c.rect(Int(hcx) + eyeOff, eyeY, p.eyeW, p.eyeH, "Q")
        c.rect(Int(hcx) - eyeOff - p.pupil, eyeY + p.eyeH - p.pupil, p.pupil, p.pupil, "E")
        c.rect(Int(hcx) + eyeOff, eyeY + p.eyeH - p.pupil, p.pupil, p.pupil, "E")
        if p.eyeH >= 4 { c[Int(hcx) - eyeOff - 1, eyeY + p.eyeH - 2] = "W"; c[Int(hcx) + eyeOff + 1, eyeY + p.eyeH - 2] = "W" }
        if pose == .cheer { c.rect(Int(hcx) - eyeOff - p.eyeW, eyeY + p.eyeH - 1, p.eyeW, 1, "s"); c.rect(Int(hcx) + eyeOff, eyeY + p.eyeH - 1, p.eyeW, 1, "s") } // 笑って細める
    }
    // 鼻
    let noseY = eyeY + p.eyeH
    c.rect(Int(hcx) - (p.headW >= 18 ? 1 : 0), noseY, p.headW >= 18 ? 2 : 1, max(1, p.headH / 8), "s")
    // 頬
    let cheekY = noseY
    c.rect(Int(hcx - rx * 0.62) - p.cheek / 2, cheekY, p.cheek, p.cheek, "C")
    c.rect(Int(hcx + rx * 0.62) - p.cheek / 2, cheekY, p.cheek, p.cheek, "C")
    // ヒゲ
    let musY = noseY + max(1, p.headH / 8)
    let musW = max(2, Int(rx * 0.62))
    for i in 0..<(musW * 2) { for j in 0..<p.mustacheH {
        c[Int(hcx) - musW + i, musY + j] = ((i + j) % 3 == 0) ? "H" : "h"
    } }
    // 口（ヒゲとの間に肌 1 ドット）
    let mouthY = musY + p.mustacheH + (p.headH >= 16 ? 1 : 0)
    let mouthW = max(2, Int(rx * 0.5))
    switch pose {
    case .cheer:
        c.rect(Int(hcx) - mouthW, mouthY, mouthW * 2, max(2, p.headH / 7), "M")
        c.rect(Int(hcx) - mouthW + 1, mouthY, mouthW * 2 - 2, 1, "Q")
        c.rect(Int(hcx) - mouthW + 2, mouthY + max(2, p.headH / 7) - 1, mouthW * 2 - 4, 1, "R")
    case .frown:
        c.rect(Int(hcx) - mouthW + 1, mouthY, mouthW * 2 - 2, 1, "M")
        c.rect(Int(hcx) - mouthW, mouthY - 1, 1, 1, "M"); c.rect(Int(hcx) + mouthW - 1, mouthY - 1, 1, 1, "M") // への字
    default:
        c.rect(Int(hcx) - mouthW, mouthY, mouthW * 2, 1, "M")
        if p.headH >= 16 { c.rect(Int(hcx) - mouthW + 1, mouthY + 1, mouthW * 2 - 2, 1, "Q") }
    }

    // 腕と手（体の上に描く）
    let shoulderL = (x: torsoX, y: torsoTop + 1), shoulderR = (x: torsoX + p.torsoW - 1, y: torsoTop + 1)
    switch pose {
    case .stance:
        c.line(shoulderL.x, shoulderL.y + 1, hands.x, hands.y + 1, "S", thick: 2)
        c.line(shoulderR.x, shoulderR.y, hands.x, hands.y, "S", thick: 2)
        c.line(shoulderL.x, shoulderL.y + 1, shoulderL.x + 2, shoulderL.y + 1, "Y", thick: 2)
        c.line(shoulderR.x - 1, shoulderR.y, shoulderR.x + 1, shoulderR.y, "Y", thick: 2)
        c.rect(hands.x, hands.y, 3, 3, "S"); c.rect(hands.x + 1, hands.y - 1, 2, 1, "X"); c.rect(hands.x + 2, hands.y + 3, 2, 1, "X")
    case .swing:
        c.line(shoulderL.x, shoulderL.y + 1, hands.x, hands.y + 1, "S", thick: 2)
        c.line(shoulderR.x, shoulderR.y, hands.x, hands.y, "S", thick: 2)
        c.line(shoulderL.x, shoulderL.y + 1, shoulderL.x + 2, shoulderL.y + 1, "Y", thick: 2)
        c.line(shoulderR.x - 1, shoulderR.y, shoulderR.x + 1, shoulderR.y, "Y", thick: 2)
        c.rect(hands.x, hands.y, 3, 3, "S"); c.rect(hands.x + 3, hands.y + 1, 2, 2, "X")
    case .cheer:
        let reach = p.headW / 2 + 4
        c.line(shoulderL.x, shoulderL.y, tcx - reach, headTop + 3, "S", thick: 2)
        c.line(shoulderR.x, shoulderR.y, tcx + reach, headTop + 3, "S", thick: 2)
        c.rect(tcx - reach - 2, headTop, 3, 3, "S"); c.rect(tcx + reach, headTop, 3, 3, "S")
    case .frown:
        c.line(shoulderL.x, shoulderL.y, shoulderL.x - 3, torsoTop + p.torsoH + 2, "S", thick: 2)
        c.line(shoulderR.x, shoulderR.y, shoulderR.x + 3, torsoTop + p.torsoH + 2, "S", thick: 2)
    }
    c.outline("K")
    return c.trimmed()
}

/// 投手（左向き・投げ終わり）。打者より遠いので画面では小さく出す。
func pitcher() -> PixelCanvas {
    var c = PixelCanvas(w: 34, h: 40)
    c.rect(11, 22, 10, 10, "U"); c.rect(11, 22, 1, 10, "u")      // 脚（ユニ白）
    c.rect(9, 32, 6, 2, "T"); c.rect(17, 32, 6, 2, "T")             // スパイク
    c.rect(10, 12, 12, 10, "U"); c.rect(10, 12, 1, 10, "u"); c.rect(15, 12, 1, 10, "u") // 胴・胸のライン
    c.rect(20, 14, 2, 4, "b")                                        // 背番号代わりの帯
    c.ellipse(cx: 16, cy: 7.5, rx: 5, ry: 5, "S")                     // 頭
    c.rect(11, 2, 10, 3, "B"); c.rect(6, 4, 7, 1, "B")                // 帽子・つば（左向き）
    c[13, 8] = "E"; c[13, 9] = "E"                                   // 目（左向き）
    c.rect(11, 11, 4, 1, "s")                                        // 口元の陰
    c.line(20, 14, 28, 4, "S", thick: 2); c.rect(27, 1, 4, 4, "N")    // 投げ終わりの腕とグローブ
    c.line(11, 15, 4, 20, "S", thick: 2); c.rect(2, 19, 3, 3, "S")     // 前の腕
    c.outline("K")
    return c.trimmed()
}

func ball() -> PixelCanvas {
    var c = PixelCanvas(w: 8, h: 8)
    c.ellipse(cx: 4, cy: 4, rx: 3, ry: 3, "W")
    c[3, 2] = "V"; c[2, 3] = "V"; c[5, 5] = "V"; c[4, 6] = "V"
    c.outline("K")
    return c.trimmed()
}

/// Core の正面顔（16×15・手描き。`OjisanPixel.smileRows` の写し）。
let coreSmile16 = PixelCanvas(rows: [
    ".....KKKKKK.....", "...KKHHSSHHKK...", "..KHHhSSSShHHK..", "..KHhSSSSSShHK..", ".KHhShhSSSShhSHK",
    ".KHhSQESSSSQESHK", ".KhSSSSSsSSSSShK", ".KsSSCSSSSSSCSsK", ".KsSSShhHHhhSSsK", "..KsSShMMMMhSsK.",
    "..KKsSSQQQQSsKK.", "....KsSSSSSsK...", ".....KKssKKK....", ".......KKK......", "................",
])
/// 試作ブランチ（wip/ojisan-puzzle-prototype）の 32×30 正面顔（会長が「デフォルメが弱い」と指摘した現行モック）。
let wipSmile32 = PixelCanvas(rows: [
    "...........KKKKKKKKKK...........", ".........KKpppppppppsKK.........", "........KppSSSLLLLSSSpsK........",
    ".......KIHhSLLLLLLLLSSHIK.......", "......KIHhSSLLLLLLLLLShHIK......", ".....KIHHhSSSLLLLLLLSShHHIK.....",
    "....KIIHhSSSSSLLLLLSSSSHHIIK....", "....KIHHhSSSSSSLLLSSSSShHHIK....", "...KHIhSSShhhhSSSShhhhSSShHHK...",
    "...KIHhSSHhhhSSSSSShhhHSShHIK...", "...KHHhSSSKKKKSLLSKKKKSSShIHK...", "..KIHhSSSSQtEQSLLSQtEQSSSShHIK..",
    "..KIhSSSSSQEEQSLLSQEEQSSSSShHK..", ".KphSSSSSSpppppLLpppppSSSSSphsK.", ".KsSSSSCCSppppSLSpppppSCCSSpSdK.",
    ".KdSSSCCCSSSSspSSpsSSSSCCCSpSdK.", ".KsdSSSSpSSSSdssssdSSSSpSSSpddK.", ".KdKpSSSSShhHHHHHHHHhhSSSSpsKdK.",
    "..KKpSSSSSSSShHHHHhSSSSSSSpsKK..", "...KdSSSSSSSSSSSSSSSSSSSSSpdK...", "....KppSSSSMQQQQQQQQMSSSSpsK....",
    "....KdpSSSSSMQQQQQQMSSSSSpdK....", ".....KdppSSSdMMMMMMdSSSppdK.....", "......KdppSSSSLLLLSSSSppdK......",
    ".......KdppSSSSLLSSSSppdK.......", "........KKsppppppppppsKK........", "..........KKsppppppsKK..........",
    "............KssssssK............", ".............KKKKKK.............", "................................",
])

// MARK: - 方向A: 高密度ドット絵（2 倍グリッド・陰影・野球のユニフォーム）。会長決裁 2026-09-24

extension PixelCanvas {
    /// 右下の縁を暗い色、左上の縁を明るい色に置き換えて立体感を足す（縁取りの前に呼ぶ）。
    mutating func shade(dark: [Character: Character], light: [Character: Character]) {
        var out = g
        for y in 0..<h { for x in 0..<w {
            let ch = g[y][x]; guard ch != "." else { continue }
            let edgeDark = self[x, y + 1] == "." || self[x + 1, y] == "."
            let edgeLight = self[x, y - 1] == "." || self[x - 1, y] == "."
            if edgeDark, let d = dark[ch] { out[y][x] = d }
            else if edgeLight, let l = light[ch] { out[y][x] = l }
        } }
        g = out
    }
}

let shadeDark: [Character: Character] = ["U": "u", "S": "s", "Y": "y", "B": "b", "N": "n", "H": "h", "T": "E"]
let shadeLight: [Character: Character] = ["U": "W", "B": "P", "Y": "Z", "N": "o", "S": "L"]

/// 打者（正面・ユニフォーム姿）。頭 30 ドット・全身 66 ドット（約 2.2 頭身）。前回の B 案（頭 18）の約 2 倍のグリッド。
/// ヘルメット（紺・黄の中央ライン・投手側の耳当て）、白のピンストライプのジャージ、黄のアンダーシャツ、
/// 紺のベルトとストッキング、黒のスパイク、黄のバッティンググローブ。薄い頭は「柵越え」でヘルメットを取ったときに見せる。
func ojisanHD(_ pose: Pose) -> PixelCanvas {
    let W = 104, H = 90
    var c = PixelCanvas(w: W, h: H)
    let shoeH = 4, legH = 14, torsoH = 18, headW = 30, headH = 30, torsoW = 24
    let legTop = H - 2 - shoeH - legH
    let torsoTop = legTop - torsoH
    let headTop = torsoTop + 1 - headH
    let tcx = 36
    let hcx = Double(tcx), hcy = Double(headTop) + Double(headH) / 2
    let rx = Double(headW) / 2, ry = Double(headH) / 2
    let torsoX = tcx - torsoW / 2 + (pose == .swing ? 2 : 0)
    let batLen = 34

    func bat(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) {
        c.line(x0, y0, x1, y1, "N", thick: 3)
        c.line(x0 + 1, y0 + 2, x1 + 1, y1 + 2, "n", thick: 1)
        c.line(x0, y0 - 1, x1, y1 - 1, "o", thick: 1)
        c.rect(x0 - 1, y0 - 1, 4, 4, "n")
    }
    func glove(_ x: Int, _ y: Int) { c.rect(x, y, 5, 5, "Y"); c.rect(x + 3, y + 3, 2, 2, "y"); c[x, y] = "Z" }

    // 構えのバットは体の後ろ（先に描く）。柵越え・空振りは足元に転がす
    let stanceHands = (x: torsoX + torsoW + 3, y: torsoTop + 2)
    if pose == .stance { bat(stanceHands.x + 1, stanceHands.y + 1, stanceHands.x + 12, stanceHands.y - batLen + 6) }
    if pose == .cheer || pose == .frown { c.line(tcx - 18, H - 3, tcx + 8, H - 3, "N", thick: 2); c.line(tcx - 18, H - 3, tcx - 14, H - 3, "n", thick: 2) }

    // 脚（白パンツ → 紺のストッキング → スパイク）
    let legW = torsoW / 2 - 1
    for lx in [torsoX, torsoX + torsoW - legW] {
        c.rect(lx, legTop, legW, legH - 5, "U")
        c.rect(lx + legW - 1, legTop, 1, legH - 5, "u")
        c.rect(lx, legTop + legH - 5, legW, 5, "B")
        c.rect(lx - 1, legTop + legH, legW + 2, shoeH, "T")
        c.rect(lx - 1, legTop + legH, legW + 2, 1, "t")
    }
    // 胴（ジャージ: ピンストライプ・前立てとボタン・黄の V 襟・ベルト）
    c.rect(torsoX, torsoTop, torsoW, torsoH, "U")
    for i in stride(from: 3, to: torsoW - 2, by: 4) where abs(torsoX + i - tcx) > 1 { c.rect(torsoX + i, torsoTop, 1, torsoH, "I") }
    c.rect(torsoX, torsoTop, 1, torsoH, "u"); c.rect(torsoX + torsoW - 1, torsoTop, 1, torsoH, "u")
    c.rect(torsoX + 1, torsoTop, torsoW - 2, 1, "u")
    c.rect(tcx - 1, torsoTop + 2, 2, torsoH - 2, "W")
    for j in stride(from: 5, to: torsoH - 3, by: 4) { c[tcx, torsoTop + j] = "b" }
    c.rect(tcx - 4, torsoTop, 3, 1, "Y"); c.rect(tcx + 1, torsoTop, 3, 1, "Y")
    c[tcx - 2, torsoTop + 1] = "Y"; c[tcx + 1, torsoTop + 1] = "Y"; c[tcx - 1, torsoTop + 2] = "Y"; c[tcx, torsoTop + 2] = "Y"
    c.rect(torsoX, legTop - 2, torsoW, 2, "b"); c.rect(tcx - 1, legTop - 2, 2, 2, "Y")

    // 頭（肌 → 側頭の白髪 → 顎の影 → 耳）
    c.ellipse(cx: hcx, cy: hcy, rx: rx, ry: ry, "S")
    for y in 0..<H { for x in 0..<W where c.inEllipse(x, y, cx: hcx, cy: hcy, rx: rx, ry: ry) {
        let fx = (Double(x) + 0.5 - hcx) / rx, fy = (Double(y) + 0.5 - hcy) / ry
        if fy > 0.82 || (fx > 0.72 && fy > 0.25) { c[x, y] = "s" }
        if fy > -0.22 && fy < 0.55 && abs(fx) > 0.66 { c[x, y] = (abs(fx) > 0.86 || fy > 0.3) ? "h" : "H" }
        if pose == .cheer && fy < -0.45 && fx > -0.55 && fx < 0.2 { c[x, y] = "L" }
    } }
    c.rect(Int(hcx - rx) - 2, Int(hcy) - 2, 3, 6, "S"); c.rect(Int(hcx + rx) - 1, Int(hcy) - 2, 3, 6, "S")
    c[Int(hcx - rx) - 1, Int(hcy)] = "s"; c[Int(hcx + rx), Int(hcy)] = "s"
    // ヘルメット（柵越えは脱いで右手に持つ）
    let cut = Int(hcy - ry * 0.28)
    if pose != .cheer {
        for y in 0..<H { for x in 0..<W where y < cut && c.inEllipse(x, y, cx: hcx, cy: hcy - 1, rx: rx + 2, ry: ry + 1) {
            let fx = (Double(x) + 0.5 - hcx) / (rx + 2), fy = (Double(y) + 0.5 - (hcy - 1)) / (ry + 1)
            c[x, y] = (fx < -0.15 && fy < -0.35) ? "P" : ((fx > 0.5 || fy > -0.08) ? "b" : "B")
        } }
        c.rect(Int(hcx) - 1, headTop - 2, 2, cut - headTop + 2, "Y")
        c.rect(Int(hcx - rx) - 3, cut, headW + 6, 2, "b"); c.rect(Int(hcx - rx) - 3, cut, headW + 6, 1, "B")
        c.rect(Int(hcx + rx) - 3, cut + 1, 5, 9, "B"); c.rect(Int(hcx + rx) + 1, cut + 1, 1, 9, "b")
    }
    // 顔（眉 → 目 → 鼻 → 頬 → ヒゲ → 口）
    let browY = cut + 1, browW = 8, browOff = 2, browH = 2
    let shift = pose == .frown ? 1 : 0
    c.rect(Int(hcx) - browOff - browW, browY + shift, browW, browH, "h")
    c.rect(Int(hcx) + browOff, browY + shift, browW, browH, "h")
    if pose == .frown { c.rect(Int(hcx) - browOff - 2, browY, 2, 2, "h"); c.rect(Int(hcx) + browOff, browY, 2, 2, "h") }
    let eyeY = browY + browH + 2, eyeW = 5, eyeH = 5, eyeOff = 3
    if pose == .frown {
        let ey = eyeY + 2
        c.line(Int(hcx) - eyeOff - eyeW, ey - 2, Int(hcx) - eyeOff - 1, ey, "E"); c.line(Int(hcx) - eyeOff - eyeW, ey + 2, Int(hcx) - eyeOff - 1, ey, "E")
        c.line(Int(hcx) + eyeOff + eyeW - 1, ey - 2, Int(hcx) + eyeOff, ey, "E"); c.line(Int(hcx) + eyeOff + eyeW - 1, ey + 2, Int(hcx) + eyeOff, ey, "E")
        let sx = Int(hcx + rx) + 4, sy = browY - 5
        c.rect(sx, sy, 2, 2, "a"); c.rect(sx - 1, sy + 2, 4, 3, "a"); c[sx, sy + 3] = "W"
    } else {
        c.rect(Int(hcx) - eyeOff - eyeW, eyeY, eyeW, eyeH, "Q"); c.rect(Int(hcx) + eyeOff, eyeY, eyeW, eyeH, "Q")
        // 瞳は両目とも投手側（右）に寄せる
        c.rect(Int(hcx) - eyeOff - 3, eyeY + 1, 3, 4, "E"); c.rect(Int(hcx) + eyeOff + 2, eyeY + 1, 3, 4, "E")
        c[Int(hcx) - eyeOff - 3, eyeY + 1] = "W"; c[Int(hcx) + eyeOff + 2, eyeY + 1] = "W"
        if pose == .cheer { c.rect(Int(hcx) - eyeOff - eyeW, eyeY + eyeH - 2, eyeW, 2, "s"); c.rect(Int(hcx) + eyeOff, eyeY + eyeH - 2, eyeW, 2, "s") }
    }
    let noseY = eyeY + eyeH
    c.rect(Int(hcx) - 1, noseY, 3, 3, "s"); c[Int(hcx) - 1, noseY] = "p"
    c.rect(Int(hcx - rx * 0.6) - 2, noseY, 4, 3, "C"); c.rect(Int(hcx + rx * 0.6) - 2, noseY, 4, 3, "C")
    // ヒゲ: 上段は白髪のハイライト、中段は灰、下段は濃い灰。両端の角を落とし、中央に 2 ドットの分け目
    let musY = noseY + 3, musW = 9
    for i in 0..<(musW * 2) { for j in 0..<3 {
        if (j == 0 || j == 2) && (i == 0 || i == musW * 2 - 1) { continue }
        let center = abs(i - musW + (i >= musW ? 0 : 1)) <= 0
        c[Int(hcx) - musW + i, musY + j] = j == 0 ? (center ? "h" : "H") : (j == 1 ? "h" : "G")
    } }
    let mouthY = musY + 4, mouthW = 6
    switch pose {
    case .cheer:
        c.rect(Int(hcx) - mouthW, mouthY, mouthW * 2, 5, "M"); c.rect(Int(hcx) - mouthW + 1, mouthY, mouthW * 2 - 2, 2, "Q"); c.rect(Int(hcx) - mouthW + 2, mouthY + 3, mouthW * 2 - 4, 2, "R")
    case .frown:
        c.rect(Int(hcx) - mouthW + 1, mouthY + 1, mouthW * 2 - 2, 2, "M"); c[Int(hcx) - mouthW, mouthY] = "M"; c[Int(hcx) + mouthW - 1, mouthY] = "M"
    default:
        c.rect(Int(hcx) - mouthW, mouthY, mouthW * 2, 2, "M"); c.rect(Int(hcx) - mouthW + 1, mouthY + 2, mouthW * 2 - 2, 1, "Q")
    }

    // 腕・手（袖口の白は最後に被せる）
    let shL = (x: torsoX - 2, y: torsoTop + 4), shR = (x: torsoX + torsoW + 1, y: torsoTop + 4)
    switch pose {
    case .stance:
        c.line(shL.x, shL.y + 2, stanceHands.x, stanceHands.y + 3, "S", thick: 3)
        c.line(shR.x, shR.y, stanceHands.x + 1, stanceHands.y, "S", thick: 3)
        glove(stanceHands.x, stanceHands.y + 3); glove(stanceHands.x + 2, stanceHands.y - 2)
    case .swing:
        let hands = (x: torsoX + torsoW + 9, y: torsoTop + 7)
        c.line(shL.x, shL.y + 2, hands.x, hands.y + 2, "S", thick: 3)
        c.line(shR.x, shR.y, hands.x, hands.y, "S", thick: 3)
        bat(hands.x + 3, hands.y + 1, hands.x + batLen, hands.y - 1)
        glove(hands.x - 1, hands.y - 1); glove(hands.x + 2, hands.y + 2)
    case .cheer:
        let reach = headW / 2 + 6
        c.line(shL.x, shL.y, tcx - reach, headTop + 2, "S", thick: 3)
        c.line(shR.x, shR.y, tcx + reach, headTop, "S", thick: 3)
        glove(tcx - reach - 3, headTop - 2); glove(tcx + reach - 1, headTop - 4)
        c.ellipse(cx: Double(tcx + reach + 5), cy: Double(headTop - 7), rx: 6.5, ry: 4.5, "B")
        c.rect(tcx + reach - 3, headTop - 4, 16, 2, "b"); c.rect(tcx + reach + 4, headTop - 11, 2, 6, "Y"); c[tcx + reach + 1, headTop - 10] = "P"
    case .frown:
        c.line(shL.x, shL.y, shL.x - 4, torsoTop + torsoH + 4, "S", thick: 3)
        c.line(shR.x, shR.y, shR.x + 4, torsoTop + torsoH + 4, "S", thick: 3)
        glove(shL.x - 6, torsoTop + torsoH + 3); glove(shR.x + 3, torsoTop + torsoH + 3)
    }
    c.rect(torsoX - 4, torsoTop + 1, 5, 4, "U"); c.rect(torsoX + torsoW - 1, torsoTop + 1, 5, 4, "U")
    c.rect(torsoX - 4, torsoTop + 4, 5, 1, "u"); c.rect(torsoX + torsoW - 1, torsoTop + 4, 5, 1, "u")
    c.shade(dark: shadeDark, light: shadeLight)
    c.outline("K")
    return c.trimmed()
}

/// 投手（左向き・投げ終わり）の高密度版。打者と同じ陰影の規則。
func pitcherHD() -> PixelCanvas {
    var c = PixelCanvas(w: 56, h: 64)
    c.rect(18, 36, 8, 12, "U"); c.rect(28, 38, 8, 10, "U"); c.rect(25, 36, 1, 12, "u")
    c.rect(18, 48, 8, 4, "B"); c.rect(28, 48, 8, 4, "B")
    c.rect(16, 52, 11, 4, "T"); c.rect(27, 52, 11, 4, "T"); c.rect(16, 52, 11, 1, "t"); c.rect(27, 52, 11, 1, "t")
    c.rect(16, 20, 20, 16, "U"); for i in stride(from: 3, to: 18, by: 4) { c.rect(16 + i, 20, 1, 16, "I") }
    c.rect(16, 20, 20, 1, "u"); c.rect(16, 34, 20, 2, "b"); c.rect(31, 23, 3, 5, "R")
    c.ellipse(cx: 25, cy: 13, rx: 8, ry: 8, "S")
    for y in 0..<64 { for x in 0..<56 where y < 11 && c.inEllipse(x, y, cx: 25, cy: 12, rx: 9, ry: 8) { c[x, y] = (x < 22 && y < 7) ? "P" : "B" } }
    c.rect(10, 10, 16, 2, "b"); c.rect(10, 10, 16, 1, "B")
    c.rect(19, 13, 2, 3, "E"); c.rect(17, 18, 6, 1, "s"); c[22, 15] = "s"
    c.line(34, 23, 46, 8, "S", thick: 3); c.rect(44, 3, 7, 7, "N"); c.rect(45, 4, 5, 5, "n"); c.rect(45, 4, 2, 2, "o")
    c.line(17, 25, 6, 34, "S", thick: 3); c.rect(3, 33, 5, 5, "S")
    c.rect(14, 20, 5, 4, "U"); c.rect(33, 20, 5, 4, "U")
    c.shade(dark: shadeDark, light: shadeLight)
    c.outline("K")
    return c.trimmed()
}

// MARK: - SwiftUI 部品

struct Px: View {
    let canvas: PixelCanvas; let scale: Int
    var body: some View {
        if let cg = canvas.cgImage(scale: 1) {
            Image(decorative: cg, scale: 1).resizable().interpolation(.none)
                .frame(width: CGFloat(canvas.w * scale), height: CGFloat(canvas.h * scale))
        }
    }
}

/// 非整数倍で置くとき（アイコンの当てはめなど）。
struct PxF: View {
    let canvas: PixelCanvas; let scale: CGFloat
    var body: some View {
        if let cg = canvas.cgImage(scale: 1) {
            Image(decorative: cg, scale: 1).resizable().interpolation(.none)
                .frame(width: CGFloat(canvas.w) * scale, height: CGFloat(canvas.h) * scale)
        }
    }
}

enum T {
    static let bg = hexColor(0xFFF6EC), surface = hexColor(0xFFFFFF), ink = hexColor(0x4A3B33), inkSub = hexColor(0x9A8A80)
    static let coral = hexColor(0xFF6F61), teal = hexColor(0x22C3BE), purple = hexColor(0x8C7BE0), yellow = hexColor(0xFFC24B), pink = hexColor(0xFF8FB1)
    static let fillCoral = hexColor(0xFF8A7E), fillPurple = hexColor(0xB3A6F0), fillMuted = hexColor(0x9A8A80)
    static let onAccent = ink
    static func f(_ s: CGFloat, _ w: Font.Weight = .bold) -> Font { .system(size: s, weight: w, design: .rounded) }
}

let screenW: CGFloat = 393, screenH: CGFloat = 852

struct Phone<Content: View>: View {
    let dark: Bool; let content: Content
    init(dark: Bool = false, @ViewBuilder _ c: () -> Content) { self.dark = dark; content = c() }
    var body: some View {
        ZStack(alignment: .top) {
            content
            // Dynamic Island と時刻（実寸の見当を付けるため）
            Capsule().fill(.black).frame(width: 125, height: 37).padding(.top, 11)
            HStack { Text("9:41").font(T.f(17, .semibold)); Spacer(); Text("●●● ᯤ ▮").font(T.f(13)) }
                .foregroundStyle(dark ? .white : T.ink).padding(.horizontal, 30).padding(.top, 18)
            // ホームインジケータ
            VStack { Spacer(); Capsule().fill(dark ? Color.white : T.ink).frame(width: 140, height: 5).padding(.bottom, 8) }
        }
        .frame(width: screenW, height: screenH)
    }
}

struct NavBar: View {
    let title: String
    var body: some View {
        HStack {
            Circle().fill(T.surface).frame(width: 44, height: 44).overlay(Image(systemName: "chevron.left").font(T.f(17)).foregroundStyle(T.coral))
            Spacer()
            Text(title).font(T.f(20)).foregroundStyle(T.ink)
            Spacer()
            HStack(spacing: 12) {
                Image(systemName: "questionmark.circle").font(T.f(20)).foregroundStyle(T.coral)
                Image(systemName: "trophy.fill").font(T.f(20)).foregroundStyle(T.coral)
            }.padding(.horizontal, 12).frame(height: 44).background(Capsule().fill(T.surface))
        }
        .padding(.horizontal, 16).padding(.top, 56)
    }
}

struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ c: () -> Content) { content = c() }
    var body: some View {
        content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20).fill(T.surface).shadow(color: .black.opacity(0.08), radius: 8, y: 3))
    }
}

struct Chip: View {
    let text: String; var fill: Color = T.fillCoral; var icon: String? = nil
    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(T.f(12)) }
            Text(text).font(T.f(13))
        }
        .foregroundStyle(T.onAccent).padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(fill))
    }
}

struct BigButton: View {
    let text: String; var icon: String? = nil; var fill: Color = T.fillCoral; var fg: Color = T.onAccent
    var body: some View {
        HStack(spacing: 8) {
            if let icon { Image(systemName: icon).font(T.f(18)) }
            Text(text).font(T.f(19, .heavy))
        }
        .foregroundStyle(fg).frame(maxWidth: .infinity).frame(height: 56)
        .background(RoundedRectangle(cornerRadius: 16).fill(fill))
    }
}

struct Banner: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 4).fill(hexColor(0xE9E1D6)).frame(height: 50)
            .overlay(Text("バナー広告（既存ゲームと同じ枠）").font(T.f(12, .medium)).foregroundStyle(T.inkSub))
            .padding(.horizontal, 12)
    }
}

/// 今日の挑戦（ボールの並び）。
struct Challenges: View {
    let remaining: Int, total: Int
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { i in
                Circle().fill(i < remaining ? T.fillCoral : hexColor(0xEFE7DC)).frame(width: 22, height: 22)
                    .overlay(Circle().stroke(i < remaining ? T.coral : hexColor(0xD9CFC3), lineWidth: 2))
                    .overlay(Image(systemName: "baseball").font(.system(size: 12, weight: .bold)).foregroundStyle(i < remaining ? T.onAccent : hexColor(0xD9CFC3)))
            }
        }
    }
}

// MARK: - 画面 1: 打席前（体験版）

struct LobbyTrial: View {
    var remaining = 2
    var body: some View {
        ZStack(alignment: .bottom) {
            T.bg.ignoresSafeArea()
            VStack(spacing: 12) {
                NavBar(title: "柵越えおじさん")
                VStack(spacing: 12) {
                    Card {
                        HStack(alignment: .center, spacing: 14) {
                            Px(canvas: ojisanHD(.stance), scale: 2)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("1 挑戦 = 10 球").font(T.f(20, .heavy)).foregroundStyle(T.ink)
                                Text("タイミングだけで柵を越えろ。\nアウトは無い。10 球ぜんぶ振れる。").font(T.f(13, .medium)).foregroundStyle(T.inkSub)
                                Chip(text: "体験版", fill: T.fillPurple, icon: "sparkles")
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack { Text("今日の挑戦").font(T.f(15)).foregroundStyle(T.ink); Spacer(); Text("残り \(remaining) / 3").font(T.f(15, .heavy)).foregroundStyle(T.coral) }
                            Challenges(remaining: remaining, total: 3)
                            Text("0:00 に 3 回に戻ります").font(T.f(12, .medium)).foregroundStyle(T.inkSub)
                            HStack(spacing: 8) {
                                smallButton("広告を見て +1", sub: "1 本 30 秒・きょう あと 5 本", icon: "play.rectangle.fill", fill: T.fillCoral)
                                smallButton("アンケートで +1", sub: "3 問・30 秒・1 日 1 回", icon: "list.bullet.clipboard.fill", fill: T.fillPurple)
                            }
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("きろく").font(T.f(15)).foregroundStyle(T.ink)
                            HStack {
                                stat("自己ベスト", "812 m"); Spacer(); stat("最長の 1 本", "131 m"); Spacer(); stat("通算 柵越え", "27 本")
                            }
                            HStack(spacing: 6) { Image(systemName: "trophy.fill").foregroundStyle(T.coral); Text("順位表（Game Center）").font(T.f(13)).foregroundStyle(T.coral) }
                        }
                    }
                    BigButton(text: "打席に立つ", icon: "figure.baseball")
                    Text("挑戦回数は打席に立った時点で 1 つ減ります").font(T.f(11, .medium)).foregroundStyle(T.inkSub)
                }.padding(.horizontal, 16)
                Spacer(minLength: 0)
                Banner().padding(.bottom, 24)
            }
        }
    }
    func smallButton(_ t: String, sub: String, icon: String, fill: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(T.f(16))
            VStack(alignment: .leading, spacing: 1) { Text(t).font(T.f(13, .heavy)); Text(sub).font(T.f(10, .medium)) }
        }
        .foregroundStyle(T.onAccent).frame(maxWidth: .infinity, alignment: .leading).padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(fill))
    }
    func stat(_ l: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(l).font(T.f(11)).foregroundStyle(T.inkSub); Text(v).font(T.f(17, .heavy).monospacedDigit()).foregroundStyle(T.ink) }
    }
}

// MARK: - 画面 2: 打席前（本導入＝通貨と強化あり）

struct LobbyFull: View {
    let p = proportions[1]
    var body: some View {
        ZStack(alignment: .bottom) {
            T.bg.ignoresSafeArea()
            VStack(spacing: 12) {
                NavBar(title: "柵越えおじさん")
                VStack(spacing: 12) {
                    Card {
                        HStack(alignment: .center, spacing: 14) {
                            Px(canvas: ojisanHD(.stance), scale: 2)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack { Text("今日の挑戦").font(T.f(13)).foregroundStyle(T.inkSub); Spacer(); Text("残り 2 / 3").font(T.f(13, .heavy)).foregroundStyle(T.coral) }
                                Challenges(remaining: 2, total: 3)
                                HStack(spacing: 6) { Image(systemName: "circle.hexagongrid.circle.fill").foregroundStyle(T.yellow); Text("1,240").font(T.f(20, .heavy).monospacedDigit()).foregroundStyle(T.ink); Text("コイン").font(T.f(12)).foregroundStyle(T.inkSub) }
                            }
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack { Text("つよさ").font(T.f(15)).foregroundStyle(T.ink); Spacer(); Text("コインは飛距離で貯まる（乱数なし）").font(T.f(11, .medium)).foregroundStyle(T.inkSub) }
                            upgrade("パワー", lv: 2, price: "320", icon: "bolt.fill", tint: T.coral)
                            upgrade("ミート", lv: 1, price: "180", icon: "scope", tint: T.teal)
                            upgrade("バット", lv: 3, price: "500", icon: "wand.and.rays", tint: T.purple)
                            Text("買えるのは強さだけ。挑戦回数はコインで買えない（広告・アンケートのみ）").font(T.f(11, .medium)).foregroundStyle(T.inkSub)
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("きょうの配球").font(T.f(15)).foregroundStyle(T.ink)
                            HStack { Text("ストレート中心・全国同じ 10 球").font(T.f(13, .medium)).foregroundStyle(T.inkSub); Spacer(); Chip(text: "連続 4 日", fill: T.fillPurple, icon: "flame.fill") }
                        }
                    }
                    BigButton(text: "打席に立つ", icon: "figure.baseball")
                }.padding(.horizontal, 16)
                Spacer(minLength: 0)
                Banner().padding(.bottom, 24)
            }
        }
    }
    func upgrade(_ n: String, lv: Int, price: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(T.f(16)).foregroundStyle(tint).frame(width: 24)
            Text(n).font(T.f(15)).foregroundStyle(T.ink).frame(width: 52, alignment: .leading)
            HStack(spacing: 3) { ForEach(0..<5, id: \.self) { i in RoundedRectangle(cornerRadius: 2).fill(i < lv ? tint : hexColor(0xEFE7DC)).frame(width: 14, height: 8) } }
            Spacer()
            HStack(spacing: 4) { Image(systemName: "circle.hexagongrid.circle.fill").font(T.f(12)).foregroundStyle(T.yellow); Text(price).font(T.f(13, .heavy).monospacedDigit()) }
                .foregroundStyle(T.onAccent).padding(.horizontal, 10).padding(.vertical, 6).background(Capsule().fill(T.yellow))
        }
    }
}

// MARK: - 画面 3: 打席（横視点・収縮リング）

struct Stadium: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [hexColor(0x8ED0F4), hexColor(0xD8EEFA)], startPoint: .top, endPoint: .bottom)
            // 遠景のスタンド（客席の帯）
            VStack(spacing: 0) {
                Spacer().frame(height: 250)
                Crowd(rows: 5).frame(height: 60)
                Rectangle().fill(hexColor(0x2F7A4F)).frame(height: 18).overlay(Rectangle().fill(T.yellow).frame(height: 3), alignment: .top)
                LinearGradient(colors: [hexColor(0x63B564), hexColor(0x4E9E52)], startPoint: .top, endPoint: .bottom)
                Rectangle().fill(hexColor(0xC28C58)).frame(height: 110)
            }
            // 芝の刈り筋
            VStack(spacing: 22) { ForEach(0..<8, id: \.self) { _ in Rectangle().fill(.white.opacity(0.06)).frame(height: 11) } }.padding(.top, 340)
        }
    }
}

struct Crowd: View {
    let rows: Int
    var dot: CGFloat = 6
    var body: some View {
        Canvas { ctx, size in
            let cols = Int(size.width / dot)
            let cs: [Color] = [T.coral, T.teal, T.purple, T.yellow, T.pink, .white, hexColor(0x4A3B33)]
            var seed = 7
            for r in 0..<rows { for c in 0..<cols {
                seed = (seed * 1103515245 + 12345) & 0x7fffffff
                let col = cs[seed % cs.count]
                ctx.fill(Path(ellipseIn: CGRect(x: CGFloat(c) * dot + (r % 2 == 0 ? 0 : dot / 2), y: CGFloat(r) * (size.height / CGFloat(rows)), width: dot - 1, height: dot - 1)), with: .color(col.opacity(0.85)))
            } }
        }
        .background(hexColor(0x5C6B8C))
    }
}

struct AtBat: View {
    let p = proportions[1]
    var body: some View {
        ZStack(alignment: .top) {
            Stadium()
            // 投手（遠いので 2 倍）・ボール（軌跡つき）・打者（3 倍）
            Px(canvas: pitcher(), scale: 2).position(x: 318, y: 566)
            ForEach(0..<4, id: \.self) { i in
                Circle().fill(.white.opacity(0.35 - Double(i) * 0.08)).frame(width: 9, height: 9).position(x: 250 + CGFloat(i) * 14, y: 640 - CGFloat(i) * 6)
            }
            Px(canvas: ball(), scale: 3).position(x: 236, y: 646)
            Px(canvas: ojisan(p, pose: .stance), scale: 3).position(x: 112, y: 684)
            // 判定リング: 白い的（固定・線は細く、内側を薄く塗る）と、収縮してくるコーラルの輪（太い）
            Circle().fill(.white.opacity(0.18)).frame(width: 46, height: 46).position(x: 196, y: 662)
            Circle().stroke(.white, lineWidth: 1).frame(width: 46, height: 46).position(x: 196, y: 662)
            Circle().stroke(T.coral, lineWidth: 5).frame(width: 118, height: 118).position(x: 196, y: 662)
            Circle().fill(T.coral.opacity(0.12)).frame(width: 118, height: 118).position(x: 196, y: 662)
            // HUD（上）
            VStack(spacing: 6) {
                HStack {
                    hud("3 / 10 球", icon: "baseball.fill")
                    Spacer()
                    VStack(spacing: 0) { Text("今回").font(T.f(11)).foregroundStyle(.white.opacity(0.85)); Text("246 m").font(T.f(28, .heavy).monospacedDigit()).foregroundStyle(.white) }
                    Spacer()
                    hud("柵越え 1", icon: "flag.checkered")
                }
                .padding(.horizontal, 16).padding(.top, 60)
                HStack(spacing: 8) { Chip(text: "1 球目 118 m", fill: .white.opacity(0.9)); Chip(text: "2 球目 128 m 柵越え", fill: T.yellow) }
            }
            // 前の球の判定（フェードアウト中）
            Text("ナイス！").font(T.f(34, .heavy)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 2).position(x: 196, y: 470)
            // 下の案内
            VStack { Spacer()
                HStack(spacing: 8) { Image(systemName: "hand.tap.fill"); Text("輪が的に重なった瞬間にタップ") }
                    .font(T.f(15)).foregroundStyle(.white).padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(.black.opacity(0.35))).padding(.bottom, 40)
            }
            // 戻る（左上・小さく）
            HStack { Image(systemName: "pause.fill").font(T.f(15)).foregroundStyle(T.coral).frame(width: 36, height: 36).background(Circle().fill(.white)); Spacer() }
                .padding(.leading, 16).padding(.top, 108)
        }
    }
    func hud(_ t: String, icon: String) -> some View {
        HStack(spacing: 5) { Image(systemName: icon).font(T.f(12)); Text(t).font(T.f(14, .heavy).monospacedDigit()) }
            .foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 7).background(Capsule().fill(.black.opacity(0.35)))
    }
}

// MARK: - 画面 4: 外野カメラ（打球の行方）

struct Outfield: View {
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [hexColor(0x6FBFF0), hexColor(0xBDE3F8)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 0) {
                Spacer().frame(height: 300)
                Crowd(rows: 12).frame(height: 150)
                // フェンス（濃い緑・上端に黄色の線・距離表示）
                ZStack {
                    LinearGradient(colors: [hexColor(0x2F7A4F), hexColor(0x225C3A)], startPoint: .top, endPoint: .bottom)
                    Text("120m").font(.system(size: 34, weight: .heavy)).foregroundStyle(.white.opacity(0.9))
                }.frame(height: 90).overlay(Rectangle().fill(T.yellow).frame(height: 5), alignment: .top)
                Rectangle().fill(hexColor(0xC28C58)).frame(height: 40) // ウォーニングトラック
                ZStack(alignment: .top) {
                    LinearGradient(colors: [hexColor(0x5FB05F), hexColor(0x3F8E45)], startPoint: .top, endPoint: .bottom)
                    VStack(spacing: 24) { ForEach(0..<8, id: \.self) { _ in Rectangle().fill(.white.opacity(0.07)).frame(height: 12) } }
                }
            }
            // 打球の弧（点線）とボール
            Path { p in p.move(to: CGPoint(x: 30, y: 760)); p.addQuadCurve(to: CGPoint(x: 330, y: 330), control: CGPoint(x: 120, y: 250)) }
                .stroke(.white.opacity(0.7), style: StrokeStyle(lineWidth: 3, dash: [6, 8]))
            ForEach(0..<3, id: \.self) { i in Circle().fill(.white.opacity(0.3 - Double(i) * 0.08)).frame(width: 14, height: 14).position(x: 300 - CGFloat(i) * 16, y: 333 + CGFloat(i) * 6) }
            Px(canvas: ball(), scale: 5).position(x: 318, y: 332)
            // 見出し
            VStack(spacing: 4) {
                Text("柵越え！").font(T.f(48, .black)).foregroundStyle(T.yellow).shadow(color: .black.opacity(0.4), radius: 3, y: 3)
                Text("131 m").font(T.f(64, .black).monospacedDigit()).foregroundStyle(.white).shadow(color: .black.opacity(0.4), radius: 3, y: 3)
                Chip(text: "ジャスト", fill: T.yellow, icon: "star.fill")
            }.padding(.top, 84)
            // 紙吹雪
            ForEach(0..<24, id: \.self) { i in
                let x = CGFloat((i * 71) % 380) + 6, y = CGFloat((i * 137) % 260) + 260
                RoundedRectangle(cornerRadius: 1).fill([T.coral, T.teal, T.pink, T.yellow][i % 4]).frame(width: 6, height: 10).rotationEffect(.degrees(Double(i * 37))).position(x: x, y: y)
            }
            VStack { Spacer(); HStack(spacing: 6) { Image(systemName: "baseball.fill"); Text("4 球目まで 377 m ／ 柵越え 2") }.font(T.f(14, .heavy)).foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 8).background(Capsule().fill(.black.opacity(0.35))).padding(.bottom, 40) }
        }
    }
}

// MARK: - 画面 5: 10 球の結果

struct Result: View {
    let p = proportions[1]
    let balls: [(Int, String)] = [(118, "hit"), (128, "hr"), (0, "miss"), (131, "hr"), (96, "hit"), (124, "hr"), (77, "hit"), (0, "miss"), (127, "hr"), (111, "hit")]
    var body: some View {
        ZStack(alignment: .bottom) {
            T.bg.ignoresSafeArea()
            VStack(spacing: 12) {
                NavBar(title: "柵越えおじさん")
                VStack(spacing: 12) {
                    Card {
                        HStack(spacing: 14) {
                            Px(canvas: ojisanHD(.cheer), scale: 2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("10 球の結果").font(T.f(13)).foregroundStyle(T.inkSub)
                                Text("912 m").font(T.f(40, .black).monospacedDigit()).foregroundStyle(T.ink)
                                HStack(spacing: 6) { Chip(text: "柵越え 4 本", fill: T.yellow, icon: "flag.checkered"); Chip(text: "ベスト更新！", fill: T.pink) }
                            }
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("1 球ずつ").font(T.f(15)).foregroundStyle(T.ink)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                                ForEach(0..<10, id: \.self) { i in
                                    let b = balls[i]
                                    VStack(spacing: 3) {
                                        Image(systemName: b.1 == "hr" ? "star.fill" : (b.1 == "hit" ? "baseball.fill" : "xmark")).font(T.f(14)).foregroundStyle(b.1 == "hr" ? T.yellow : (b.1 == "hit" ? T.teal : T.inkSub))
                                        Text(b.1 == "miss" ? "空振り" : "\(b.0) m").font(T.f(11, .heavy).monospacedDigit()).foregroundStyle(T.ink)
                                    }.frame(maxWidth: .infinity).padding(.vertical, 8).background(RoundedRectangle(cornerRadius: 10).fill(b.1 == "hr" ? T.yellow.opacity(0.25) : hexColor(0xF7F1E8)))
                                }
                            }
                            HStack { Text("最長 131 m（4 球目・ジャスト）").font(T.f(12, .medium)).foregroundStyle(T.inkSub); Spacer(); Text("順位表に送信済み").font(T.f(12, .medium)).foregroundStyle(T.inkSub) }
                        }
                    }
                    Card {
                        HStack { Text("今日の挑戦").font(T.f(15)).foregroundStyle(T.ink); Spacer(); Challenges(remaining: 1, total: 3); Text("残り 1").font(T.f(13, .heavy)).foregroundStyle(T.coral) }
                    }
                    BigButton(text: "もう一回（残り 1）", icon: "arrow.counterclockwise")
                    BigButton(text: "ホームへ", fill: hexColor(0xEFE7DC), fg: T.ink)
                }.padding(.horizontal, 16)
                Spacer(minLength: 0)
                Banner().padding(.bottom, 24)
            }
        }
    }
}

// MARK: - 画面 6: 回数を使い切ったときのシート（広告 or アンケート）

struct Recover: View {
    let p = proportions[1]
    var body: some View {
        ZStack(alignment: .bottom) {
            LobbyTrial(remaining: 0)
            Color.black.opacity(0.4)
            VStack(spacing: 14) {
                Capsule().fill(hexColor(0xD9CFC3)).frame(width: 36, height: 5).padding(.top, 8)
                HStack(spacing: 12) {
                    Px(canvas: ojisanHD(.frown), scale: 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("今日の挑戦を使い切りました").font(T.f(19, .heavy)).foregroundStyle(T.ink)
                        Text("残り 0 / 3 ・ 0:00 に 3 回に戻ります").font(T.f(13, .medium)).foregroundStyle(T.inkSub)
                    }
                }
                option("広告を見て +1 回", sub: "30 秒ほどの動画。1 本で 1 回。きょう あと 5 本", icon: "play.rectangle.fill", fill: T.fillCoral)
                option("アンケートに答えて +1 回", sub: "3 問・30 秒。1 日 1 回。答えは開発の参考にします", icon: "list.bullet.clipboard.fill", fill: T.fillPurple)
                Text("明日にする").font(T.f(15)).foregroundStyle(T.inkSub).padding(.vertical, 6)
                Text("コインでは買えません。増やせるのは時間（挑戦回数）だけです").font(T.f(11, .medium)).foregroundStyle(T.inkSub).padding(.bottom, 28)
            }
            .padding(.horizontal, 20).frame(maxWidth: .infinity)
            .background(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24).fill(T.bg))
        }
    }
    func option(_ t: String, sub: String, icon: String, fill: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(T.f(22)).frame(width: 32)
            VStack(alignment: .leading, spacing: 2) { Text(t).font(T.f(16, .heavy)); Text(sub).font(T.f(11, .medium)) }
            Spacer(); Image(systemName: "chevron.right").font(T.f(14))
        }
        .foregroundStyle(T.onAccent).padding(14).frame(maxWidth: .infinity).background(RoundedRectangle(cornerRadius: 16).fill(fill))
    }
}

// MARK: - 画面 7: キャラデザインの比較（デフォルメ 3 段階 × 4 ポーズ、現行の手描き顔を参照に並べる）

struct CharacterSheet: View {
    var body: some View {
        ZStack(alignment: .top) {
            T.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                Text("キャラ案: デフォルメ強度の 3 段階").font(T.f(20, .heavy)).foregroundStyle(T.ink).padding(.top, 64)
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 4) { Px(canvas: coreSmile16, scale: 4); Text("現行 Core 16×15\n（公開中）").font(T.f(10)).multilineTextAlignment(.center) }
                    VStack(spacing: 4) { Px(canvas: wipSmile32, scale: 2); Text("試作 32×30\n（#1125）").font(T.f(10)).multilineTextAlignment(.center) }
                    Text("下の 3 案は生成器で組んだ叩き台。頭身・目の大きさ・描き込み量だけを変え、色と特徴（薄い頭・白髪の側頭・太い眉・ヒゲ・黄ポロ・紺ズボン）は共通。決まった案を手で描き直して Core に置く。")
                        .font(T.f(11, .medium)).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                }.foregroundStyle(T.inkSub)
                ForEach(0..<3, id: \.self) { i in
                    let p = proportions[i]
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text(p.name).font(T.f(15, .heavy)).foregroundStyle(T.ink); Spacer(); Text(p.sub).font(T.f(11, .medium)).foregroundStyle(T.inkSub) }
                            HStack(alignment: .bottom, spacing: 8) {
                                ForEach([Pose.stance, .swing, .cheer, .frown], id: \.self) { pose in
                                    VStack(spacing: 2) { Px(canvas: ojisan(p, pose: pose), scale: 2); Text(label(pose)).font(T.f(10)).foregroundStyle(T.inkSub) }
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
                HStack(alignment: .bottom, spacing: 16) {
                    Text("ハブのカード相当（1 ドット = 1pt）→").font(T.f(11, .medium)).foregroundStyle(T.inkSub)
                    ForEach(0..<3, id: \.self) { i in Px(canvas: ojisan(proportions[i], pose: .stance), scale: 1) }
                    Spacer()
                }
            }.padding(.horizontal, 16)
        }
    }
    func label(_ p: Pose) -> String { switch p { case .stance: "構え"; case .swing: "スイング"; case .cheer: "柵越え"; case .frown: "空振り" } }
}

// MARK: - 画面 8: 置き場所の 2 案（あそびば内のプレミアム枠カード / 別アプリのアイコン）

struct Placement: View {
    let p = proportions[1]
    var body: some View {
        ZStack(alignment: .top) {
            T.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 20) {
                Text("置き場所の 2 案").font(T.f(20, .heavy)).foregroundStyle(T.ink).padding(.top, 64)
                Text("案 1: あそびば内のプレミアム枠（ハブの先頭にカードを 1 枚）").font(T.f(14)).foregroundStyle(T.inkSub)
                HStack(spacing: 12) {
                    hubCard(premium: true)
                    hubCard(premium: false)
                }
                Text("案 2: 別アプリに切り出す（アイコンとストア名）").font(T.f(14)).foregroundStyle(T.inkSub)
                HStack(spacing: 24) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 28).fill(LinearGradient(colors: [hexColor(0x8ED0F4), hexColor(0x63B564)], startPoint: .top, endPoint: .bottom)).frame(width: 120, height: 120)
                        PxF(canvas: ojisanHD(.swing), scale: 1.4).offset(x: -4, y: 6)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("柵越えおじさん").font(T.f(20, .heavy)).foregroundStyle(T.ink)
                        Text("1 日 3 回の柵越え勝負").font(T.f(13, .medium)).foregroundStyle(T.inkSub)
                        Text("あそびばのおじさんが別アプリで主役に。\nハブ・広告 SDK・Game Center は作り直し。").font(T.f(11, .medium)).foregroundStyle(T.inkSub)
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("比較の要点（詳細は README）").font(T.f(14, .heavy)).foregroundStyle(T.ink)
                        Text("・流入: 案 1 は既存 DAU にそのまま届く／案 2 は ASO をゼロから\n・実装: 案 1 は広告・記録・GC の受け口を流用／案 2 は基盤ごと複製\n・体験版の検証: 案 1 のほうが早く・安く回せる\n・IAP（広告除去）: 案 1 は「あそびば全体の広告除去」に広がる論点を抱える").font(T.f(12, .medium)).foregroundStyle(T.inkSub)
                    }
                }
            }.padding(.horizontal, 16)
        }
    }
    func hubCard(premium: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                ZStack { RoundedRectangle(cornerRadius: 14).fill(T.yellow).frame(width: 52, height: 52); Px(canvas: coreSmile16, scale: 3) }
                Spacer()
                if premium { Chip(text: "残り 2 回", fill: T.fillPurple) } else { Chip(text: "きょう 1 回", fill: hexColor(0xEFE7DC)) }
            }
            Text("柵越えおじさん").font(T.f(17, .heavy)).foregroundStyle(T.ink)
            Text(premium ? "1 日 3 回。10 球で柵を越えろ" : "1 日 1 回のおためし").font(T.f(11, .medium)).foregroundStyle(T.inkSub)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(T.surface).shadow(color: .black.opacity(0.08), radius: 8, y: 3))
        .overlay(alignment: .topTrailing) {
            if premium { Text("プレミアム").font(T.f(10, .heavy)).foregroundStyle(T.onAccent).padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(T.fillCoral)).offset(x: -8, y: -8) }
        }
    }
}

// MARK: - 方向A の球場（密度を上げたドット絵路線: 照明塔・スコアボード・広告パネル・バッターボックス・マウンド）

struct StadiumHD: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [hexColor(0x6EC0F0), hexColor(0xC8E8FA)], startPoint: .top, endPoint: .bottom)
            // 照明塔 2 本
            ForEach([64.0, 336.0], id: \.self) { x in
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 2).fill(hexColor(0xE8EEF4)).frame(width: 40, height: 20)
                        .overlay(LazyVGrid(columns: Array(repeating: GridItem(.fixed(6), spacing: 2), count: 5), spacing: 2) { ForEach(0..<10, id: \.self) { _ in Circle().fill(T.yellow.opacity(0.9)).frame(width: 6, height: 6) } }.padding(2))
                    Rectangle().fill(hexColor(0x8A96A8)).frame(width: 5, height: 72)
                }.position(x: x, y: 190)
            }
            // スコアボード
            RoundedRectangle(cornerRadius: 6).fill(hexColor(0x2B2634)).frame(width: 150, height: 46)
                .overlay(VStack(spacing: 2) {
                    Text("3 球目   246 m").font(.system(size: 15, weight: .heavy, design: .monospaced)).foregroundStyle(T.yellow)
                    Text("HR 1   BEST 812").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(hexColor(0xF2F2F2))
                }).overlay(RoundedRectangle(cornerRadius: 6).stroke(hexColor(0x8A96A8), lineWidth: 2)).position(x: 196, y: 214)
            VStack(spacing: 0) {
                Spacer().frame(height: 238)
                Rectangle().fill(hexColor(0x3E4E80)).frame(height: 8)
                Crowd(rows: 9, dot: 4).frame(height: 72)
                ZStack {
                    Rectangle().fill(hexColor(0x2F7A4F))
                    HStack(spacing: 8) { ForEach(0..<6, id: \.self) { i in RoundedRectangle(cornerRadius: 2).fill([Color.white, T.yellow, T.teal][i % 3].opacity(0.85)).frame(height: 12) } }.padding(.horizontal, 10)
                }.frame(height: 22).overlay(alignment: .top) { Rectangle().fill(T.yellow).frame(height: 3) }
                Rectangle().fill(hexColor(0xC28C58)).frame(height: 10)
                ZStack(alignment: .top) {
                    LinearGradient(colors: [hexColor(0x6BB86A), hexColor(0x4E9E52)], startPoint: .top, endPoint: .bottom)
                    VStack(spacing: 20) { ForEach(0..<9, id: \.self) { _ in Rectangle().fill(.white.opacity(0.07)).frame(height: 12) } }
                }
                Rectangle().fill(hexColor(0xC28C58)).frame(height: 116)
            }
            // 内野の土のカーブ・バッターボックスの白線・ホームベース・マウンド
            Canvas { ctx, _ in
                ctx.fill(Path(ellipseIn: CGRect(x: -60, y: 690, width: 513, height: 120)), with: .color(hexColor(0xC28C58)))
                ctx.fill(Path(ellipseIn: CGRect(x: 268, y: 596, width: 100, height: 22)), with: .color(hexColor(0xD09A62)))
                ctx.fill(Path(CGRect(x: 312, y: 600, width: 12, height: 3)), with: .color(.white.opacity(0.9)))
                var box = Path(); box.move(to: CGPoint(x: 52, y: 712)); box.addLine(to: CGPoint(x: 168, y: 712)); box.addLine(to: CGPoint(x: 176, y: 776)); box.addLine(to: CGPoint(x: 40, y: 776)); box.closeSubpath()
                ctx.stroke(box, with: .color(.white.opacity(0.85)), lineWidth: 3)
                var plate = Path(); plate.move(to: CGPoint(x: 184, y: 738)); plate.addLine(to: CGPoint(x: 212, y: 738)); plate.addLine(to: CGPoint(x: 212, y: 748)); plate.addLine(to: CGPoint(x: 198, y: 758)); plate.addLine(to: CGPoint(x: 184, y: 748)); plate.closeSubpath()
                ctx.fill(plate, with: .color(.white))
                var foul = Path(); foul.move(to: CGPoint(x: 206, y: 740)); foul.addLine(to: CGPoint(x: 393, y: 598))
                ctx.stroke(foul, with: .color(.white.opacity(0.6)), lineWidth: 2)
            }
        }
    }
}

// MARK: - 方向B: 滑らかな塗り（3D 風）。SwiftUI の図形とグラデーションだけで描く（Canvas も画像も使わない）

typealias Pt = CGPoint

/// 2 点を結ぶカプセル（腕・脚・バット）。
func limb(_ a: Pt, _ b: Pt, w: CGFloat, _ fill: AnyShapeStyle) -> some View {
    let dx = b.x - a.x, dy = b.y - a.y
    let len = (dx * dx + dy * dy).squareRoot()
    return Capsule().fill(fill).frame(width: len + w, height: w).rotationEffect(.radians(atan2(dy, dx))).position(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
}

enum V {
    static let skin = AnyShapeStyle(RadialGradient(colors: [hexColor(0xFBE0BE), hexColor(0xE8B88E)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 2, endRadius: 40))
    static let skinFlat = AnyShapeStyle(LinearGradient(colors: [hexColor(0xF6D2A8), hexColor(0xD69E76)], startPoint: .topLeading, endPoint: .bottomTrailing))
    static let navy = AnyShapeStyle(LinearGradient(colors: [hexColor(0x6C80B8), hexColor(0x28345C)], startPoint: .topLeading, endPoint: .bottomTrailing))
    static let white = AnyShapeStyle(LinearGradient(colors: [.white, hexColor(0xD4D2DC)], startPoint: .topLeading, endPoint: .bottomTrailing))
    static let yellow = AnyShapeStyle(LinearGradient(colors: [hexColor(0xFFE070), hexColor(0xD8A020)], startPoint: .topLeading, endPoint: .bottomTrailing))
    static let wood = AnyShapeStyle(LinearGradient(colors: [hexColor(0xE0B478), hexColor(0x7A4E24)], startPoint: .top, endPoint: .bottom))
    static let gray = AnyShapeStyle(LinearGradient(colors: [hexColor(0xC4C4CE), hexColor(0x7E7E8C)], startPoint: .topLeading, endPoint: .bottomTrailing))
    static let dark = AnyShapeStyle(LinearGradient(colors: [hexColor(0x4A4A56), hexColor(0x1E1E28)], startPoint: .top, endPoint: .bottom))
    static let red = AnyShapeStyle(LinearGradient(colors: [hexColor(0xB83030), hexColor(0x7A1818)], startPoint: .top, endPoint: .bottom))
}

/// 打者（滑らかな塗り）。座標系は 200×176pt（中心 x = 100）。ポーズはドット絵版と同じ 4 つ。
struct VecOjisan: View {
    let pose: Pose
    var body: some View {
        let shL = Pt(x: 72, y: 94), shR = Pt(x: 128, y: 94)
        ZStack {
            Ellipse().fill(.black.opacity(0.22)).frame(width: 84, height: 16).blur(radius: 3).position(x: 100, y: 168)
            // バット（構えは体の後ろ）
            if pose == .stance { batView(Pt(x: 146, y: 88), Pt(x: 170, y: 26)) }
            if pose == .cheer || pose == .frown { batView(Pt(x: 60, y: 165), Pt(x: 120, y: 165)) }
            // 脚（白パンツが胴の下に見えるよう、胴より 8pt 下まで出す）
            ForEach([84.0, 116.0], id: \.self) { x in
                Capsule().fill(V.white).frame(width: 24, height: 50).position(x: x, y: 142)
                Capsule().fill(V.navy).frame(width: 24, height: 16).position(x: x, y: 157)
                RoundedRectangle(cornerRadius: 5).fill(V.dark).frame(width: 30, height: 12).position(x: x, y: 166)
                Capsule().fill(.white.opacity(0.35)).frame(width: 5, height: 22).position(x: x - 7, y: 138)
            }
            // 胴（ジャージ）
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(V.white)
                HStack(spacing: 6) { ForEach(0..<9, id: \.self) { _ in Rectangle().fill(hexColor(0x28345C).opacity(0.28)).frame(width: 1.5) } }
                Rectangle().fill(.white).frame(width: 7)
                VStack(spacing: 8) { ForEach(0..<4, id: \.self) { _ in Circle().fill(hexColor(0x28345C)).frame(width: 3.5, height: 3.5) } }.offset(y: 4)
                Path { p in p.move(to: Pt(x: 20, y: -1)); p.addLine(to: Pt(x: 33, y: 13)); p.addLine(to: Pt(x: 46, y: -1)) }.stroke(V.yellow, lineWidth: 5)
                LinearGradient(colors: [.clear, .black.opacity(0.18)], startPoint: .top, endPoint: .bottom).frame(height: 14).offset(y: -19)
            }
            .frame(width: 66, height: 54).clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(alignment: .bottom) { Capsule().fill(V.navy).frame(width: 66, height: 8).overlay(RoundedRectangle(cornerRadius: 2).fill(V.yellow).frame(width: 10, height: 6)) }
            .rotationEffect(.degrees(pose == .swing ? -6 : 0))
            .position(x: 100, y: 108)
            // 袖口（白）と腕・手袋・バット
            Capsule().fill(V.white).frame(width: 22, height: 16).rotationEffect(.degrees(24)).position(x: 70, y: 96)
            Capsule().fill(V.white).frame(width: 22, height: 16).rotationEffect(.degrees(-24)).position(x: 130, y: 96)
            switch pose {
            case .stance:
                limb(shL, Pt(x: 140, y: 92), w: 14, V.skinFlat); limb(shR, Pt(x: 146, y: 84), w: 14, V.skinFlat)
                Circle().fill(V.yellow).frame(width: 17, height: 17).position(x: 142, y: 92); Circle().fill(V.yellow).frame(width: 17, height: 17).position(x: 148, y: 82)
            case .swing:
                limb(shL, Pt(x: 150, y: 108), w: 14, V.skinFlat); limb(shR, Pt(x: 152, y: 102), w: 14, V.skinFlat)
                batView(Pt(x: 158, y: 105), Pt(x: 198, y: 103))
                Circle().fill(V.yellow).frame(width: 17, height: 17).position(x: 150, y: 108); Circle().fill(V.yellow).frame(width: 17, height: 17).position(x: 156, y: 100)
            case .cheer:
                limb(shL, Pt(x: 50, y: 30), w: 14, V.skinFlat); limb(shR, Pt(x: 150, y: 26), w: 14, V.skinFlat)
                Circle().fill(V.yellow).frame(width: 17, height: 17).position(x: 48, y: 26); Circle().fill(V.yellow).frame(width: 17, height: 17).position(x: 152, y: 22)
                helmet(scale: 0.55).position(x: 164, y: 12)
            case .frown:
                limb(shL, Pt(x: 60, y: 132), w: 14, V.skinFlat); limb(shR, Pt(x: 140, y: 132), w: 14, V.skinFlat)
                Circle().fill(V.yellow).frame(width: 17, height: 17).position(x: 58, y: 136); Circle().fill(V.yellow).frame(width: 17, height: 17).position(x: 142, y: 136)
            }
            head
        }
        .frame(width: 200, height: 176)
    }

    func batView(_ a: Pt, _ b: Pt) -> some View {
        ZStack {
            limb(a, b, w: 10, V.wood)
            limb(Pt(x: a.x, y: a.y - 2), Pt(x: b.x, y: b.y - 2), w: 2.5, AnyShapeStyle(Color.white.opacity(0.35)))
            Circle().fill(V.wood).frame(width: 14, height: 14).position(a)
            limb(a, Pt(x: a.x + (b.x - a.x) * 0.22, y: a.y + (b.y - a.y) * 0.22), w: 10, V.dark)
        }
    }

    func helmet(scale s: CGFloat) -> some View {
        ZStack {
            Circle().fill(V.navy).frame(width: 82 * s, height: 82 * s).mask(Rectangle().frame(width: 100 * s, height: 36 * s).offset(y: -23 * s))
            Ellipse().fill(.white.opacity(0.45)).frame(width: 28 * s, height: 12 * s).rotationEffect(.degrees(-24)).offset(x: -16 * s, y: -28 * s)
            Capsule().fill(V.yellow).frame(width: 5 * s, height: 34 * s).offset(y: -22 * s)
            Ellipse().fill(hexColor(0x1E2848)).frame(width: 92 * s, height: 12 * s).offset(y: -5 * s)
            RoundedRectangle(cornerRadius: 5 * s).fill(V.navy).frame(width: 16 * s, height: 22 * s).offset(x: 36 * s, y: 6 * s)
        }
    }

    var head: some View {
        ZStack {
            // 耳 → 顔 → 側頭の白髪
            Circle().fill(V.skinFlat).frame(width: 15, height: 15).position(x: 64, y: 58)
            Circle().fill(V.skinFlat).frame(width: 15, height: 15).position(x: 136, y: 58)
            Circle().fill(V.skin).frame(width: 74, height: 74).position(x: 100, y: 54)
                .overlay(Circle().fill(LinearGradient(colors: [.clear, .black.opacity(0.14)], startPoint: .top, endPoint: .bottom)).frame(width: 74, height: 74).position(x: 100, y: 54))
            RoundedRectangle(cornerRadius: 6).fill(V.gray).frame(width: 13, height: 24).position(x: 67, y: 58)
            RoundedRectangle(cornerRadius: 6).fill(V.gray).frame(width: 13, height: 24).position(x: 133, y: 58)
            if pose == .cheer { Ellipse().fill(.white.opacity(0.5)).frame(width: 30, height: 12).rotationEffect(.degrees(-20)).position(x: 88, y: 28) }
            // 眉（空振りは内側を吊り上げる）
            Capsule().fill(hexColor(0x5A5A66)).frame(width: 20, height: 6).rotationEffect(.degrees(pose == .frown ? -14 : 6)).position(x: 86, y: 50)
            Capsule().fill(hexColor(0x5A5A66)).frame(width: 20, height: 6).rotationEffect(.degrees(pose == .frown ? 14 : -6)).position(x: 114, y: 50)
            // 目
            if pose == .frown {
                ForEach([88.0, 112.0], id: \.self) { x in
                    Capsule().fill(hexColor(0x221E28)).frame(width: 13, height: 3).rotationEffect(.degrees(x < 100 ? 28 : -28)).position(x: x, y: 58)
                    Capsule().fill(hexColor(0x221E28)).frame(width: 13, height: 3).rotationEffect(.degrees(x < 100 ? -28 : 28)).position(x: x, y: 64)
                }
                Path { p in p.move(to: Pt(x: 146, y: 28)); p.addQuadCurve(to: Pt(x: 152, y: 42), control: Pt(x: 158, y: 36)); p.addQuadCurve(to: Pt(x: 146, y: 28), control: Pt(x: 140, y: 36)) }
                    .fill(LinearGradient(colors: [hexColor(0xA8DCFA), hexColor(0x4EA8E8)], startPoint: .top, endPoint: .bottom))
            } else {
                ForEach([88.0, 112.0], id: \.self) { x in
                    Ellipse().fill(.white).frame(width: 13, height: pose == .cheer ? 10 : 15).position(x: x, y: 61)
                    Circle().fill(hexColor(0x221E28)).frame(width: 7, height: 7).position(x: x + 1, y: pose == .cheer ? 61 : 63)
                    Circle().fill(.white).frame(width: 2.5, height: 2.5).position(x: x - 1, y: pose == .cheer ? 59 : 61)
                }
            }
            // 鼻・頬・ヒゲ・口
            Ellipse().fill(hexColor(0xD69E76)).frame(width: 9, height: 7).position(x: 100, y: 70)
            Circle().fill(T.coral.opacity(0.5)).frame(width: 13, height: 13).blur(radius: 2).position(x: 77, y: 70)
            Circle().fill(T.coral.opacity(0.5)).frame(width: 13, height: 13).blur(radius: 2).position(x: 123, y: 70)
            RoundedRectangle(cornerRadius: 5).fill(V.gray).frame(width: 34, height: 10).position(x: 100, y: 78)
            switch pose {
            case .cheer:
                Ellipse().fill(V.red).frame(width: 22, height: 13).position(x: 100, y: 88)
                Ellipse().fill(T.pink).frame(width: 12, height: 6).position(x: 100, y: 91)
            case .frown:
                Path { p in p.move(to: Pt(x: 91, y: 88)); p.addQuadCurve(to: Pt(x: 109, y: 88), control: Pt(x: 100, y: 82)) }.stroke(hexColor(0x96282C), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            default:
                Path { p in p.move(to: Pt(x: 90, y: 85)); p.addQuadCurve(to: Pt(x: 110, y: 85), control: Pt(x: 100, y: 92)) }.stroke(hexColor(0x96282C), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            if pose != .cheer { helmet(scale: 1).position(x: 100, y: 52) }
        }
    }
}

/// 投手（滑らかな塗り・左向き）。座標系は 120×130pt。
struct VecPitcher: View {
    var body: some View {
        ZStack {
            Ellipse().fill(.black.opacity(0.2)).frame(width: 70, height: 12).blur(radius: 3).position(x: 60, y: 124)
            limb(Pt(x: 52, y: 84), Pt(x: 40, y: 118), w: 16, V.white); limb(Pt(x: 68, y: 84), Pt(x: 78, y: 118), w: 16, V.white)
            RoundedRectangle(cornerRadius: 4).fill(V.dark).frame(width: 22, height: 9).position(x: 38, y: 122); RoundedRectangle(cornerRadius: 4).fill(V.dark).frame(width: 22, height: 9).position(x: 80, y: 122)
            RoundedRectangle(cornerRadius: 14).fill(V.white).frame(width: 46, height: 46).position(x: 60, y: 68)
                .overlay(HStack(spacing: 5) { ForEach(0..<6, id: \.self) { _ in Rectangle().fill(hexColor(0x28345C).opacity(0.25)).frame(width: 1.5, height: 40) } }.position(x: 60, y: 68))
            Capsule().fill(V.navy).frame(width: 46, height: 6).position(x: 60, y: 90)
            limb(Pt(x: 78, y: 52), Pt(x: 104, y: 20), w: 12, V.skinFlat); Circle().fill(V.wood).frame(width: 20, height: 20).position(x: 108, y: 14)
            limb(Pt(x: 42, y: 56), Pt(x: 16, y: 74), w: 12, V.skinFlat); Circle().fill(V.skinFlat).frame(width: 13, height: 13).position(x: 13, y: 76)
            Circle().fill(V.skin).frame(width: 40, height: 40).position(x: 60, y: 34)
            Circle().fill(V.navy).frame(width: 44, height: 44).mask(Rectangle().frame(width: 60, height: 20).offset(y: -12)).position(x: 60, y: 34)
            Ellipse().fill(hexColor(0x1E2848)).frame(width: 34, height: 8).position(x: 44, y: 24)
            Circle().fill(hexColor(0x221E28)).frame(width: 5, height: 5).position(x: 50, y: 34)
        }
        .frame(width: 120, height: 130)
    }
}

/// 方向B の球場: 光・奥行き・ぼかし・遠近の刈り筋。
struct StadiumB: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [hexColor(0x4FA8E8), hexColor(0xC4E6F8)], startPoint: .top, endPoint: .bottom)
            Circle().fill(RadialGradient(colors: [.white.opacity(0.95), .white.opacity(0)], center: .center, startRadius: 0, endRadius: 130)).frame(width: 260, height: 260).position(x: 330, y: 120)
            ForEach([(60.0, 150.0, 90.0), (250.0, 200.0, 110.0), (150.0, 100.0, 70.0)], id: \.0) { c in
                Ellipse().fill(.white.opacity(0.85)).frame(width: c.2, height: c.2 * 0.4).blur(radius: 5).position(x: c.0, y: c.1)
            }
            VStack(spacing: 0) {
                Spacer().frame(height: 238)
                ZStack(alignment: .top) {
                    LinearGradient(colors: [hexColor(0x2E3A5C), hexColor(0x6C7A9C)], startPoint: .top, endPoint: .bottom)
                    Crowd(rows: 10, dot: 4).blur(radius: 1.4).opacity(0.85)
                    Rectangle().fill(LinearGradient(colors: [hexColor(0x1E2848), .clear], startPoint: .top, endPoint: .bottom)).frame(height: 24)
                }.frame(height: 80)
                ZStack {
                    LinearGradient(colors: [hexColor(0x3C9A63), hexColor(0x1E5A38)], startPoint: .top, endPoint: .bottom)
                    HStack(spacing: 8) { ForEach(0..<6, id: \.self) { _ in RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.18)).frame(height: 12) } }.padding(.horizontal, 10)
                }.frame(height: 24).overlay(alignment: .top) { LinearGradient(colors: [hexColor(0xFFE070), hexColor(0xC89A1C)], startPoint: .top, endPoint: .bottom).frame(height: 4) }
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 4)
                Rectangle().fill(LinearGradient(colors: [hexColor(0xD09A62), hexColor(0xB8804A)], startPoint: .top, endPoint: .bottom)).frame(height: 10)
                ZStack(alignment: .top) {
                    LinearGradient(colors: [hexColor(0x8CCC7A), hexColor(0x3F8E45)], startPoint: .top, endPoint: .bottom)
                    Canvas { ctx, size in
                        for i in 0..<9 where i % 2 == 0 {
                            let t0 = CGFloat(i - 4), w0: CGFloat = 26, wb: CGFloat = 86
                            var p = Path()
                            p.move(to: Pt(x: size.width / 2 + t0 * w0, y: 0)); p.addLine(to: Pt(x: size.width / 2 + (t0 + 1) * w0, y: 0))
                            p.addLine(to: Pt(x: size.width / 2 + (t0 + 1) * wb, y: size.height)); p.addLine(to: Pt(x: size.width / 2 + t0 * wb, y: size.height)); p.closeSubpath()
                            ctx.fill(p, with: .color(.white.opacity(0.09)))
                        }
                    }
                }
                Rectangle().fill(LinearGradient(colors: [hexColor(0xCC9660), hexColor(0xA8743E)], startPoint: .top, endPoint: .bottom)).frame(height: 116)
            }
            Canvas { ctx, _ in
                ctx.fill(Path(ellipseIn: CGRect(x: -60, y: 690, width: 513, height: 120)), with: .linearGradient(Gradient(colors: [hexColor(0xD4A068), hexColor(0xA8743E)]), startPoint: Pt(x: 0, y: 690), endPoint: Pt(x: 0, y: 810)))
                ctx.fill(Path(ellipseIn: CGRect(x: 268, y: 596, width: 100, height: 22)), with: .radialGradient(Gradient(colors: [hexColor(0xE0B078), hexColor(0xB8804A)]), center: Pt(x: 318, y: 604), startRadius: 0, endRadius: 50))
                ctx.fill(Path(CGRect(x: 312, y: 600, width: 12, height: 3)), with: .color(.white.opacity(0.9)))
                var box = Path(); box.move(to: Pt(x: 52, y: 712)); box.addLine(to: Pt(x: 168, y: 712)); box.addLine(to: Pt(x: 176, y: 776)); box.addLine(to: Pt(x: 40, y: 776)); box.closeSubpath()
                ctx.stroke(box, with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
                var plate = Path(); plate.move(to: Pt(x: 184, y: 738)); plate.addLine(to: Pt(x: 212, y: 738)); plate.addLine(to: Pt(x: 212, y: 748)); plate.addLine(to: Pt(x: 198, y: 758)); plate.addLine(to: Pt(x: 184, y: 748)); plate.closeSubpath()
                ctx.fill(plate.offsetBy(dx: 2, dy: 3), with: .color(.black.opacity(0.2)))
                ctx.fill(plate, with: .color(.white))
                var foul = Path(); foul.move(to: Pt(x: 206, y: 740)); foul.addLine(to: Pt(x: 393, y: 598))
                ctx.stroke(foul, with: .color(.white.opacity(0.55)), lineWidth: 2)
            }
        }
    }
}

// MARK: - 画面 11・12: 打席の 2 方向（HUD・リング・構図は同じ。変えるのは絵だけ）

struct AtBatHUD: View {
    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 6) {
                HStack {
                    hud("3 / 10 球", icon: "baseball.fill")
                    Spacer()
                    VStack(spacing: 0) { Text("今回").font(T.f(11)).foregroundStyle(.white.opacity(0.85)); Text("246 m").font(T.f(28, .heavy).monospacedDigit()).foregroundStyle(.white) }
                    Spacer()
                    hud("柵越え 1", icon: "flag.checkered")
                }
                .padding(.horizontal, 16).padding(.top, 60)
                HStack(spacing: 8) { Chip(text: "1 球目 118 m", fill: .white.opacity(0.9)); Chip(text: "2 球目 128 m 柵越え", fill: T.yellow) }
            }
            Text("ナイス！").font(T.f(34, .heavy)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 2).position(x: 196, y: 470)
            VStack { Spacer()
                HStack(spacing: 8) { Image(systemName: "hand.tap.fill"); Text("輪が的に重なった瞬間にタップ") }
                    .font(T.f(15)).foregroundStyle(.white).padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(.black.opacity(0.35))).padding(.bottom, 40)
            }
            HStack { Image(systemName: "pause.fill").font(T.f(15)).foregroundStyle(T.coral).frame(width: 36, height: 36).background(Circle().fill(.white)); Spacer() }
                .padding(.leading, 16).padding(.top, 108)
        }
    }
    func hud(_ t: String, icon: String) -> some View {
        HStack(spacing: 5) { Image(systemName: icon).font(T.f(12)); Text(t).font(T.f(14, .heavy).monospacedDigit()) }
            .foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 7).background(Capsule().fill(.black.opacity(0.35)))
    }
}

struct Ring: View {
    var glow: Bool = false
    var body: some View {
        ZStack {
            Circle().fill(.white.opacity(0.18)).frame(width: 46, height: 46)
            Circle().stroke(.white, lineWidth: 1).frame(width: 46, height: 46)
            Circle().fill(T.coral.opacity(0.12)).frame(width: 118, height: 118)
            Circle().stroke(T.coral, lineWidth: 5).frame(width: 118, height: 118).shadow(color: glow ? T.coral.opacity(0.8) : .clear, radius: 8)
        }.position(x: 196, y: 662)
    }
}

struct AtBatA: View {
    var body: some View {
        ZStack(alignment: .top) {
            StadiumHD()
            Px(canvas: pitcherHD(), scale: 2).position(x: 318, y: 556)
            ForEach(0..<4, id: \.self) { i in Circle().fill(.white.opacity(0.35 - Double(i) * 0.08)).frame(width: 9, height: 9).position(x: 250 + CGFloat(i) * 14, y: 640 - CGFloat(i) * 6) }
            Px(canvas: ball(), scale: 3).position(x: 236, y: 646)
            Px(canvas: ojisanHD(.stance), scale: 2).position(x: 112, y: 684)
            Ring()
            AtBatHUD()
        }
    }
}

struct AtBatB: View {
    var body: some View {
        ZStack(alignment: .top) {
            StadiumB()
            VecPitcher().scaleEffect(0.78).position(x: 318, y: 556)
            ForEach(0..<4, id: \.self) { i in Circle().fill(.white.opacity(0.35 - Double(i) * 0.08)).frame(width: 9, height: 9).blur(radius: 1).position(x: 250 + CGFloat(i) * 14, y: 640 - CGFloat(i) * 6) }
            ZStack {
                Circle().fill(RadialGradient(colors: [.white, hexColor(0xC8C8D2)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 1, endRadius: 12)).frame(width: 20, height: 20)
                Path { p in p.move(to: Pt(x: 6, y: 3)); p.addQuadCurve(to: Pt(x: 6, y: 17), control: Pt(x: 1, y: 10)) }.stroke(hexColor(0xD43C2C), lineWidth: 1.5).frame(width: 20, height: 20)
                Path { p in p.move(to: Pt(x: 14, y: 3)); p.addQuadCurve(to: Pt(x: 14, y: 17), control: Pt(x: 19, y: 10)) }.stroke(hexColor(0xD43C2C), lineWidth: 1.5).frame(width: 20, height: 20)
            }.shadow(color: .black.opacity(0.3), radius: 2, y: 2).position(x: 236, y: 646)
            VecOjisan(pose: .stance).position(x: 112, y: 684)
            Ring(glow: true)
            AtBatHUD()
        }
    }
}

// MARK: - 画面 13・14・15: キャラ案の 2 方向と並べ比べ

struct CharacterA: View {
    var body: some View {
        ZStack(alignment: .top) {
            T.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                Text("方向A: ドット絵のまま密度を上げる").font(T.f(20, .heavy)).foregroundStyle(T.ink).padding(.top, 64)
                Text("グリッドを約 1.7 倍（頭 18 → 30 ドット）にし、縁の陰影と服の描き込み（ピンストライプ・前立て・ベルト・耳当て）を足した。色はチャリンコおじさんと同じパレット + 3 色。")
                    .font(T.f(11, .medium)).foregroundStyle(T.inkSub).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ユニフォーム姿・4 ポーズ（2 倍）").font(T.f(15, .heavy)).foregroundStyle(T.ink)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .center, spacing: 6) {
                            ForEach([Pose.stance, .swing, .cheer, .frown], id: \.self) { pose in
                                VStack(spacing: 2) { Px(canvas: ojisanHD(pose), scale: 2).frame(height: 158, alignment: .bottom); Text(label(pose)).font(T.f(10)).foregroundStyle(T.inkSub) }
                            }
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("前回（B 案・普段着）→ 今回。投手も同じ密度に").font(T.f(14, .heavy)).foregroundStyle(T.ink)
                        HStack(alignment: .bottom, spacing: 6) {
                            VStack(spacing: 2) { Px(canvas: ojisan(proportions[1], pose: .stance), scale: 2); Text("頭 18 × 2 倍").font(T.f(9)).foregroundStyle(T.inkSub) }
                            Image(systemName: "arrow.right").font(T.f(16)).foregroundStyle(T.coral).padding(.bottom, 70)
                            VStack(spacing: 2) { Px(canvas: ojisanHD(.stance), scale: 2); Text("頭 30 × 2 倍").font(T.f(9)).foregroundStyle(T.inkSub) }
                            VStack(spacing: 2) { Px(canvas: pitcherHD(), scale: 2); Text("投手").font(T.f(9)).foregroundStyle(T.inkSub) }
                            Spacer(minLength: 0)
                        }
                        HStack(spacing: 10) {
                            ZStack { RoundedRectangle(cornerRadius: 12).fill(T.yellow).frame(width: 44, height: 44); PxF(canvas: coreSmile16, scale: 2.5) }
                            Text("全身は 1 倍でも 66pt あってハブの 44pt には収まらない。ハブのカードは今までどおり Core の正面顔（16×15）を使い、全身は打席・結果・回復シートに出す。").font(T.f(10, .medium)).foregroundStyle(T.inkSub).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }.padding(.horizontal, 16)
        }
    }
    func label(_ p: Pose) -> String { switch p { case .stance: "構え"; case .swing: "スイング"; case .cheer: "柵越え"; case .frown: "空振り" } }
}

struct CharacterB: View {
    var body: some View {
        ZStack(alignment: .top) {
            T.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                Text("方向B: ドット絵を離れて滑らかな塗りに").font(T.f(20, .heavy)).foregroundStyle(T.ink).padding(.top, 64)
                Text("輪郭線を持たず、面のグラデーションと影・光沢で立体を見せる（3D モデルではなく、3D 風の 2D）。特徴（薄い頭・白髪の側頭・太い眉・ヒゲ・頬）と黄・紺の配色はドット絵版と同じ。")
                    .font(T.f(11, .medium)).foregroundStyle(T.inkSub).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ユニフォーム姿・4 ポーズ").font(T.f(15, .heavy)).foregroundStyle(T.ink)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                            ForEach([Pose.stance, .swing, .cheer, .frown], id: \.self) { pose in
                                VStack(spacing: 0) {
                                    VecOjisan(pose: pose).scaleEffect(0.82).frame(width: 164, height: 146)
                                    Text(label(pose)).font(T.f(10)).foregroundStyle(T.inkSub)
                                }
                            }
                        }
                    }
                }
                Card {
                    HStack(alignment: .center, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("小さくしても崩れないのが利点").font(T.f(13, .heavy)).foregroundStyle(T.ink)
                            Text("ベクターなので 44pt に縮めても線がにじまない。逆にドット絵路線の既存ゲームと並ぶハブでは浮く").font(T.f(10, .medium)).foregroundStyle(T.inkSub).fixedSize(horizontal: false, vertical: true)
                        }
                        VecOjisan(pose: .stance).scaleEffect(0.4).frame(width: 80, height: 72)
                        ZStack { RoundedRectangle(cornerRadius: 12).fill(T.yellow).frame(width: 44, height: 44); VecOjisan(pose: .stance).scaleEffect(0.24).frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 12)) }
                    }
                }
            }.padding(.horizontal, 16)
        }
    }
    func label(_ p: Pose) -> String { switch p { case .stance: "構え"; case .swing: "スイング"; case .cheer: "柵越え"; case .frown: "空振り" } }
}

struct CompareAB: View {
    var body: some View {
        ZStack(alignment: .top) {
            T.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                Text("方向A と方向B（同じポーズ・同じ大きさ）").font(T.f(17, .heavy)).foregroundStyle(T.ink).padding(.top, 64).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                HStack(alignment: .top, spacing: 10) {
                    Card {
                        VStack(spacing: 6) {
                            Text("A ドット絵・高密度").font(T.f(14, .heavy)).foregroundStyle(T.ink)
                            Px(canvas: ojisanHD(.stance), scale: 2).frame(width: 140, height: 180)
                            Px(canvas: ojisanHD(.cheer), scale: 2).frame(width: 140, height: 180)
                        }.frame(maxWidth: .infinity)
                    }.clipped()
                    Card {
                        VStack(spacing: 6) {
                            Text("B 滑らかな塗り").font(T.f(14, .heavy)).foregroundStyle(T.ink)
                            VecOjisan(pose: .stance).scaleEffect(0.86).frame(width: 140, height: 180)
                            VecOjisan(pose: .cheer).scaleEffect(0.86).frame(width: 140, height: 180)
                        }.frame(maxWidth: .infinity)
                    }.clipped()
                }
                Card {
                    VStack(alignment: .leading, spacing: 5) {
                        row("描く基盤", "PixelSprite + SpriteKit（走者と同じ）", "SwiftUI の図形（今回のモック）か、描き出した PNG を SpriteKit へ")
                        row("動き", "コマ絵の差し替え（走者と同じ）", "部品ごとの回転・移動（コマ数は不要）")
                        row("新規の絵", "4 ポーズ + 投手 + 球場の部品", "同左 + 影・光の設計（球場側も塗り直し）")
                        row("ハブとの一貫性", "既存ゲームと同じ路線", "1 本だけ絵柄が違う（プレミアムの印にもなる）")
                        row("パワプロとの距離", "遠い（2D のまま）", "近づくが 3D ではない。頭身と光沢で寄せる")
                    }
                }
            }.padding(.horizontal, 16)
        }
    }
    func row(_ k: String, _ a: String, _ b: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(k).font(T.f(11, .heavy)).foregroundStyle(T.ink).frame(width: 70, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            Text(a).font(T.f(10, .medium)).foregroundStyle(T.inkSub).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            Text(b).font(T.f(10, .medium)).foregroundStyle(T.inkSub).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 3D 方向（会長決裁 2026-09-24: 絵柄は 3D に決定・センターカメラで打者を正面に・投手は一直線上・ミート点の第 2 軸）
//
// 本物の 3D ではなく「疑似 3D」: 球場は透視投影（Cam）で描き、人物はトゥーン調（セル 2 階調 + ハイライト・輪郭線なし）の
// 2D 部品を奥行きに応じた大きさで置く。世界座標は本塁が原点、+Z = 投手方向、+Y = 上、+X = 三塁側（右打者が立つ側 = 左翼側）。
// 打席のカメラはセンター（外野）側の高い位置から本塁を見る「テレビ中継のセンターカメラ」。投手は手前で背中越し、
// 打者はカメラ目線の正面、投手 → 本塁 → 捕手 → 審判 → バックネットが画面の中央の一直線に並ぶ。

struct V3 { var x: Double, y: Double, z: Double; init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z } }
func - (a: V3, b: V3) -> V3 { V3(a.x - b.x, a.y - b.y, a.z - b.z) }
func + (a: V3, b: V3) -> V3 { V3(a.x + b.x, a.y + b.y, a.z + b.z) }
func * (a: V3, s: Double) -> V3 { V3(a.x * s, a.y * s, a.z * s) }
func dot(_ a: V3, _ b: V3) -> Double { a.x * b.x + a.y * b.y + a.z * b.z }
func cross(_ a: V3, _ b: V3) -> V3 { V3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x) }
func norm(_ a: V3) -> V3 { let l = dot(a, a).squareRoot(); return V3(a.x / l, a.y / l, a.z / l) }
/// 扇形の座標。θ は中堅を 0 とし、+X（三塁・左翼）側が正（度）。
func polar(_ r: Double, _ deg: Double, y: Double = 0) -> V3 { let t = deg * .pi / 180; return V3(r * sin(t), y, r * cos(t)) }
/// 柵までの距離。両翼 100 m・左右中間 ≒ 114 m・中堅 120 m。
func fenceR(_ deg: Double) -> Double { 100 + 20 * cos(2 * deg * .pi / 180) }

struct Cam {
    let pos: V3, f: V3, r: V3, u: V3, fpx: CGFloat, c: Pt
    init(pos: V3, target: V3, fpx: CGFloat, c: Pt = Pt(x: screenW / 2, y: screenH / 2)) {
        self.pos = pos; f = norm(target - pos); r = norm(cross(f, V3(0, 1, 0))); u = cross(r, f); self.fpx = fpx; self.c = c
    }
    func depth(_ p: V3) -> Double { dot(p - pos, f) }
    func project(_ p: V3) -> Pt {
        let v = p - pos, d = max(dot(v, f), 0.5)
        return Pt(x: c.x + fpx * CGFloat(dot(v, r) / d), y: c.y - fpx * CGFloat(dot(v, u) / d))
    }
    /// 1 m が何 pt に映るか。
    func ppm(_ p: V3) -> CGFloat { fpx / CGFloat(max(depth(p), 0.5)) }
    func poly(_ pts: [V3]) -> Path { var p = line(pts); p.closeSubpath(); return p }
    func line(_ pts: [V3]) -> Path {
        var p = Path()
        for (i, q) in pts.enumerated() { if i == 0 { p.move(to: project(q)) } else { p.addLine(to: project(q)) } }
        return p
    }
    func circle(_ center: V3, r: Double, n: Int = 56) -> Path {
        poly((0..<n).map { i in let t = Double(i) / Double(n) * 2 * .pi; return V3(center.x + r * sin(t), center.y, center.z + r * cos(t)) })
    }
}

struct LCG {
    var s: UInt32
    init(_ s: UInt32) { self.s = s }
    mutating func next() -> UInt32 { s = s &* 1664525 &+ 1013904223; return s >> 8 }
    mutating func unit() -> Double { Double(next() % 10000) / 10000 }
}

// トゥーンの 2 階調（明・暗）。光源は左上で全部品共通。
struct Tone { let l: UInt32, d: UInt32 }
enum TC {
    static let skin = Tone(l: 0xFBE0BE, d: 0xE2A87C), skinDeep = Tone(l: 0xE8B88E, d: 0xC08A60)
    static let navy = Tone(l: 0x5C6FA6, d: 0x28345C), white = Tone(l: 0xFFFFFF, d: 0xC9C6D4), yellow = Tone(l: 0xFFE070, d: 0xD8A020)
    static let wood = Tone(l: 0xDDAE74, d: 0x8A5A2C), gray = Tone(l: 0xD4D4DC, d: 0x8A8A98), dark = Tone(l: 0x4A4A56, d: 0x1E1E28)
    static let red = Tone(l: 0xC03030, d: 0x7A1818), mitt = Tone(l: 0xB8794A, d: 0x6E4222), ump = Tone(l: 0x3A3F52, d: 0x1C1F2A)
    static let grassL: UInt32 = 0x6FBF62, grassD: UInt32 = 0x3E8E45, dirtL: UInt32 = 0xD8A26C, dirtD: UInt32 = 0xA8743E
    static let crowd: [UInt32] = [0xE85D4A, 0x3D6FD8, 0xF2C94C, 0xF4F4F8, 0x2FB5A8, 0x9B6BD8, 0x333A4A, 0xF08FB0, 0x60C070, 0xE9A24C]
}

enum Toon {
    static func stops(_ t: Tone, _ split: Double) -> Gradient {
        Gradient(stops: [.init(color: hexColor(t.l), location: 0), .init(color: hexColor(t.l), location: split), .init(color: hexColor(t.d), location: split + 0.012), .init(color: hexColor(t.d), location: 1)])
    }
    static func cel(_ t: Tone, in r: CGRect, split: Double = 0.55) -> GraphicsContext.Shading {
        .linearGradient(stops(t, split), startPoint: Pt(x: r.minX, y: r.minY), endPoint: Pt(x: r.maxX, y: r.minY + r.width * 0.75))
    }
    static func sphere(_ t: Tone, center: Pt, r: CGFloat, split: Double = 0.6) -> GraphicsContext.Shading {
        .radialGradient(stops(t, split), center: Pt(x: center.x - r * 0.28, y: center.y - r * 0.32), startRadius: 0, endRadius: r * 1.3)
    }
}

func ell(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path { Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2)) }
func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path { Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r) }
/// 2 点を結ぶカプセル（腕・脚・バット）。
func cap(_ a: Pt, _ b: Pt, w: CGFloat) -> Path {
    let dx = b.x - a.x, dy = b.y - a.y, len = (dx * dx + dy * dy).squareRoot()
    return Path(roundedRect: CGRect(x: -w / 2, y: -w / 2, width: len + w, height: w), cornerRadius: w / 2)
        .applying(CGAffineTransform(translationX: a.x, y: a.y).rotated(by: atan2(dy, dx)))
}
func rot(_ p: Path, _ cx: CGFloat, _ cy: CGFloat, _ deg: Double) -> Path { p.applying(CGAffineTransform(translationX: cx, y: cy).rotated(by: deg * .pi / 180)) }

/// 局所座標（y 下向き）で組んだ図形を、画面上の足元 `feet` と拡大率 `s` で置く描き手。
struct Rig {
    let ctx: GraphicsContext, t: CGAffineTransform, s: CGFloat
    init(ctx: GraphicsContext, t: CGAffineTransform, s: CGFloat) { self.ctx = ctx; self.t = t; self.s = s }
    init(_ ctx: GraphicsContext, feet: Pt, s: CGFloat, feetLocal: Pt) {
        self.init(ctx: ctx, t: CGAffineTransform(translationX: feet.x - feetLocal.x * s, y: feet.y - feetLocal.y * s).scaledBy(x: s, y: s), s: s)
    }
    func P(_ x: CGFloat, _ y: CGFloat) -> Pt { Pt(x: x, y: y).applying(t) }
    func cel(_ p: Path, _ tone: Tone, split: Double = 0.55) { let q = p.applying(t); ctx.fill(q, with: Toon.cel(tone, in: q.boundingRect, split: split)) }
    func flat(_ p: Path, _ c: Color) { ctx.fill(p.applying(t), with: .color(c)) }
    func sphere(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ tone: Tone, split: Double = 0.6) {
        let c = P(cx, cy), rr = r * s
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)), with: Toon.sphere(tone, center: c, r: rr, split: split))
    }
    func stroke(_ p: Path, _ c: Color, w: CGFloat) { ctx.stroke(p.applying(t), with: .color(c), style: StrokeStyle(lineWidth: w * s, lineCap: .round, lineJoin: .round)) }
    /// 光沢（白の楕円・半透明）
    func gloss(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat, deg: Double = -25, a: Double = 0.5) { flat(rot(ell(0, 0, w / 2, h / 2), cx, cy, deg), .white.opacity(a)) }
    func shadow(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat, a: Double = 0.26) {
        var c = ctx; c.addFilter(.blur(radius: 2.5 * s))
        c.fill(ell(cx, cy, w / 2, h / 2).applying(t), with: .color(.black.opacity(a)))
    }
    func clipped(_ p: Path) -> Rig { var c = ctx; c.clip(to: p.applying(t)); return Rig(ctx: c, t: t, s: s) }
}

/// おじさんの顔（正面）。`R` は頭の半径。特徴（薄い頭・白髪の側頭・太い眉・ヒゲ・頬）は Core の OjisanPixel と同じ。
func drawOjisanHead(_ g: Rig, hc: Pt, R: CGFloat, pose: Pose) {
    g.sphere(hc.x - R * 1.0, hc.y + R * 0.12, R * 0.2, TC.skinDeep); g.sphere(hc.x + R * 1.0, hc.y + R * 0.12, R * 0.2, TC.skinDeep)
    g.sphere(hc.x, hc.y, R, TC.skin, split: 0.66)
    g.cel(rr(hc.x - R * 1.04, hc.y - R * 0.22, R * 0.36, R * 0.66, R * 0.16), TC.gray); g.cel(rr(hc.x + R * 0.68, hc.y - R * 0.22, R * 0.36, R * 0.66, R * 0.16), TC.gray)
    if pose == .cheer { g.gloss(hc.x - R * 0.3, hc.y - R * 0.66, R * 0.7, R * 0.28) }
    // 眉（空振りは内側を吊り上げる）
    let bw = R * 0.52, bh = R * 0.16
    g.flat(rot(rr(-bw / 2, -bh / 2, bw, bh, bh / 2), hc.x - R * 0.38, hc.y - R * 0.12, pose == .frown ? -14 : 6), hexColor(0x5A5A66))
    g.flat(rot(rr(-bw / 2, -bh / 2, bw, bh, bh / 2), hc.x + R * 0.38, hc.y - R * 0.12, pose == .frown ? 14 : -6), hexColor(0x5A5A66))
    // 目
    for sgn in [-1.0, 1.0] {
        let ex = hc.x + R * 0.33 * sgn, ey = hc.y + R * 0.2
        if pose == .frown {
            let lw = R * 0.34, lh = R * 0.08
            g.flat(rot(rr(-lw / 2, -lh / 2, lw, lh, lh / 2), ex, ey - R * 0.08, sgn < 0 ? 28 : -28), hexColor(0x221E28))
            g.flat(rot(rr(-lw / 2, -lh / 2, lw, lh, lh / 2), ex, ey + R * 0.08, sgn < 0 ? -28 : 28), hexColor(0x221E28))
        } else {
            g.flat(ell(ex, ey, R * 0.18, pose == .cheer ? R * 0.14 : R * 0.2), .white)
            g.flat(ell(ex + R * 0.03, ey + (pose == .cheer ? 0 : R * 0.05), R * 0.095, R * 0.095), hexColor(0x221E28))
            g.flat(ell(ex - R * 0.02, ey - R * 0.03, R * 0.035, R * 0.035), .white)
        }
    }
    if pose == .frown {  // 汗
        var d = Path(); d.move(to: Pt(x: hc.x + R * 1.25, y: hc.y - R * 0.7)); d.addQuadCurve(to: Pt(x: hc.x + R * 1.4, y: hc.y - R * 0.32), control: Pt(x: hc.x + R * 1.56, y: hc.y - R * 0.5)); d.addQuadCurve(to: Pt(x: hc.x + R * 1.25, y: hc.y - R * 0.7), control: Pt(x: hc.x + R * 1.1, y: hc.y - R * 0.5))
        g.cel(d, Tone(l: 0xA8DCFA, d: 0x4EA8E8))
    }
    g.flat(ell(hc.x, hc.y + R * 0.44, R * 0.12, R * 0.09), hexColor(0xD69E76))
    for sgn in [-1.0, 1.0] { var c = g.ctx; c.addFilter(.blur(radius: R * g.s * 0.06)); c.fill(ell(hc.x + R * 0.62 * sgn, hc.y + R * 0.44, R * 0.17, R * 0.17).applying(g.t), with: .color(T.coral.opacity(0.5))) }
    g.cel(rr(hc.x - R * 0.46, hc.y + R * 0.56, R * 0.92, R * 0.27, R * 0.13), TC.gray)
    switch pose {
    case .cheer:
        g.cel(ell(hc.x, hc.y + R * 0.94, R * 0.3, R * 0.18), TC.red); g.flat(ell(hc.x, hc.y + R * 1.02, R * 0.16, R * 0.08), T.pink)
    case .frown:
        var m = Path(); m.move(to: Pt(x: hc.x - R * 0.24, y: hc.y + R * 0.96)); m.addQuadCurve(to: Pt(x: hc.x + R * 0.24, y: hc.y + R * 0.96), control: Pt(x: hc.x, y: hc.y + R * 0.8)); g.stroke(m, hexColor(0x96282C), w: R * 0.08)
    default:
        var m = Path(); m.move(to: Pt(x: hc.x - R * 0.27, y: hc.y + R * 0.88)); m.addQuadCurve(to: Pt(x: hc.x + R * 0.27, y: hc.y + R * 0.88), control: Pt(x: hc.x, y: hc.y + R * 1.06)); g.stroke(m, hexColor(0x96282C), w: R * 0.08)
    }
    if pose != .cheer { drawHelmet(g, hc: hc, R: R) }
}

/// 紺のヘルメット（黄の中央ライン・つば・投手側の耳当て = 右打者は本人の左 = 画面右）。
func drawHelmet(_ g: Rig, hc: Pt, R: CGFloat, flap: Bool = true) {
    let gc = g.clipped(Path(CGRect(x: hc.x - R * 1.5, y: hc.y - R * 1.5, width: R * 3, height: R * 1.44)))
    gc.sphere(hc.x, hc.y - R * 0.06, R * 1.1, TC.navy, split: 0.58)
    gc.flat(cap(Pt(x: hc.x, y: hc.y - R * 1.12), Pt(x: hc.x, y: hc.y - R * 0.2), w: R * 0.14), hexColor(0xF0C030))
    gc.gloss(hc.x - R * 0.44, hc.y - R * 0.74, R * 0.6, R * 0.24)
    g.flat(ell(hc.x, hc.y - R * 0.06, R * 1.26, R * 0.16), hexColor(0x1E2848))
    if flap { g.cel(rr(hc.x + R * 0.86, hc.y - R * 0.12, R * 0.4, R * 0.62, R * 0.14), TC.navy) }
}

/// 右打者・正面（カメラ目線）。局所座標 200×176、足元は (100, 170)。`heads` = 頭身（全身 160 のうち頭の直径が 160/heads）。
func drawBatter(_ ctx: GraphicsContext, feet: Pt, s: CGFloat, pose: Pose, heads: CGFloat = 2.2, shadow: Bool = true) {
    let g = Rig(ctx, feet: feet, s: s, feetLocal: Pt(x: 100, y: 170))
    let R = 80 / heads
    let hc = Pt(x: 100, y: 10 + R)
    let sy = 10 + 2 * R - 6
    let bodyH = 160 - 2 * R
    let torsoH = bodyH * 0.6
    let tw = min(68, 36 + bodyH * 0.36)
    let ly = sy + torsoH - 6
    let armW = max(11, R * 0.34), handR = max(7, R * 0.23), batW = max(8, R * 0.25)
    let shL = Pt(x: 100 - tw * 0.4, y: sy + 8), shR = Pt(x: 100 + tw * 0.4, y: sy + 8)
    if shadow { g.shadow(100, 170, 100, 16) }
    func bat(_ a: Pt, _ b: Pt) {
        let dx = b.x - a.x, dy = b.y - a.y
        g.cel(cap(a, b, w: batW), TC.wood, split: 0.6)
        g.cel(cap(a, Pt(x: a.x + dx * 0.22, y: a.y + dy * 0.22), w: batW), TC.dark)
        g.flat(cap(Pt(x: a.x + dx * 0.3 - batW * 0.25, y: a.y + dy * 0.3 - batW * 0.25), Pt(x: a.x + dx * 0.95 - batW * 0.25, y: a.y + dy * 0.95 - batW * 0.25), w: batW * 0.22), .white.opacity(0.4))
    }
    func leg(_ x0: CGFloat, _ x1: CGFloat) {
        let w = max(16, tw * 0.3)
        g.cel(cap(Pt(x: x0, y: ly), Pt(x: x1, y: 158), w: w), TC.white)
        g.cel(cap(Pt(x: x1, y: 150), Pt(x: x1, y: 163), w: w * 0.92), TC.navy)
        g.cel(rr(x1 - w * 0.62, 161, w * 1.24, 10, 5), TC.dark)
    }
    func hand(_ p: Pt) { g.sphere(p.x, p.y, handR, TC.yellow, split: 0.55) }
    func arm(_ a: Pt, _ b: Pt) { g.cel(cap(a, b, w: armW), TC.skin, split: 0.5) }
    func sleeve(_ p: Pt, left: Bool) { g.cel(ell(p.x + (left ? -3 : 3), p.y + 1, armW * 0.9, armW * 0.66), TC.white) }

    let hands = Pt(x: 100 - tw * 0.5, y: sy + 14)
    switch pose {
    case .stance: bat(Pt(x: hands.x + 2, y: hands.y + 4), Pt(x: hands.x - 22, y: hands.y - 70 - R * 0.4))
    case .cheer, .frown: bat(Pt(x: 42, y: 166), Pt(x: 118, y: 166))
    case .swing: break
    }
    let spread = tw * 0.33
    switch pose {
    case .stance: leg(100 - spread * 0.7, 100 - spread); leg(100 + spread * 0.7, 100 + spread)
    case .swing: leg(100 - spread * 0.5, 100 - spread * 1.3); leg(100 + spread * 0.7, 100 + spread * 0.9)
    default: leg(100 - spread * 0.6, 100 - spread * 0.8); leg(100 + spread * 0.6, 100 + spread * 0.8)
    }
    let torso = rr(100 - tw / 2, sy, tw, torsoH, tw * 0.22)
    g.cel(torso, TC.white, split: 0.62)
    let gc = g.clipped(torso)
    var x = 100 - tw / 2 + 6
    while x < 100 + tw / 2 { gc.stroke(cap(Pt(x: x, y: sy), Pt(x: x, y: sy + torsoH), w: 0.1), hexColor(0x28345C, 0.25), w: 1.4); x += 6 }
    g.flat(rr(96.5, sy + 4, 7, torsoH - 8, 0), .white)
    for i in 0..<3 { g.flat(ell(100, sy + 14 + CGFloat(i) * 10, 1.8, 1.8), hexColor(0x28345C)) }
    var v = Path(); v.move(to: Pt(x: 100 - 14, y: sy - 1)); v.addLine(to: Pt(x: 100, y: sy + 11)); v.addLine(to: Pt(x: 100 + 14, y: sy - 1)); g.stroke(v, hexColor(0xF0C030), w: 4.5)
    g.cel(rr(100 - tw / 2, sy + torsoH - 8, tw, 8, 3), TC.navy); g.flat(rr(96, sy + torsoH - 7.5, 8, 7, 1.5), hexColor(0xF0C030))
    switch pose {
    case .stance:
        sleeve(shL, left: true); sleeve(shR, left: false)
        arm(shR, Pt(x: hands.x + 8, y: hands.y + 6)); arm(shL, Pt(x: hands.x, y: hands.y + 2))
        hand(Pt(x: hands.x + 6, y: hands.y + 8)); hand(Pt(x: hands.x, y: hands.y - 2))
    case .swing:
        let h = Pt(x: 100 + tw * 0.55, y: sy + 22)
        sleeve(shL, left: true); sleeve(shR, left: false)
        arm(shL, h); arm(shR, Pt(x: h.x - 2, y: h.y - 6))
        bat(Pt(x: h.x + 4, y: h.y), Pt(x: h.x + 74, y: h.y - 10))
        hand(h); hand(Pt(x: h.x + 6, y: h.y - 8))
    case .cheer:
        arm(shL, Pt(x: 42, y: sy - 48)); arm(shR, Pt(x: 158, y: sy - 52)); sleeve(shL, left: true); sleeve(shR, left: false)
        hand(Pt(x: 40, y: sy - 54)); hand(Pt(x: 160, y: sy - 58))
        // 脱いだヘルメットが宙に
        let hg = Rig(ctx: ctx, t: g.t.translatedBy(x: 168, y: 14).rotated(by: 0.5), s: s)
        drawHelmet(hg, hc: Pt(x: 0, y: 0), R: R * 0.55, flap: false)
    case .frown:
        arm(shL, Pt(x: 100 - tw * 0.62, y: sy + torsoH + 4)); arm(shR, Pt(x: 100 + tw * 0.62, y: sy + torsoH + 4)); sleeve(shL, left: true); sleeve(shR, left: false)
        hand(Pt(x: 100 - tw * 0.64, y: sy + torsoH + 10)); hand(Pt(x: 100 + tw * 0.64, y: sy + torsoH + 10))
    }
    drawOjisanHead(g, hc: hc, R: R, pose: pose)
}

/// 投手（背中越し・右投げ・リリース直後のフォロースルー）。局所 200×200、足元 (100, 190)。名無しなので背番号なし。
func drawPitcherBack(_ ctx: GraphicsContext, feet: Pt, s: CGFloat) {
    let g = Rig(ctx, feet: feet, s: s, feetLocal: Pt(x: 100, y: 190))
    g.shadow(100, 190, 130, 22)
    // 後ろ脚（画面右・投げ終わって浮く）→ 前脚（画面左・踏み込み）
    g.cel(cap(Pt(x: 114, y: 122), Pt(x: 158, y: 172), w: 26), TC.white); g.cel(cap(Pt(x: 150, y: 164), Pt(x: 160, y: 176), w: 22), TC.navy); g.cel(rr(146, 172, 32, 13, 6), TC.dark)
    g.cel(cap(Pt(x: 86, y: 122), Pt(x: 52, y: 176), w: 28), TC.white); g.cel(cap(Pt(x: 54, y: 168), Pt(x: 50, y: 182), w: 24), TC.navy); g.cel(rr(34, 178, 34, 13, 6), TC.dark)
    // 胴（背中）
    let torso = rr(58, 56, 84, 72, 20); g.cel(torso, TC.white, split: 0.6)
    let gc = g.clipped(torso); var x: CGFloat = 64; while x < 142 { gc.stroke(cap(Pt(x: x, y: 56), Pt(x: x, y: 128), w: 0.1), hexColor(0x28345C, 0.25), w: 1.4); x += 6 }
    g.cel(rr(58, 122, 84, 9, 4), TC.navy)
    // 腕: 左（画面左）はグラブを胸元に、右（画面右）はフォロースルーで体の前を横切る
    g.cel(ell(68, 66, 14, 11), TC.white); g.cel(ell(132, 66, 14, 11), TC.white)
    g.cel(cap(Pt(x: 66, y: 70), Pt(x: 46, y: 98), w: 16), TC.skin); g.sphere(40, 104, 16, TC.mitt, split: 0.55)
    g.cel(cap(Pt(x: 134, y: 66), Pt(x: 92, y: 118), w: 16), TC.skin); g.sphere(88, 122, 9, TC.skin)
    // 首・後頭部・帽子（後ろから: つばは見えない）
    g.cel(cap(Pt(x: 100, y: 52), Pt(x: 100, y: 62), w: 20), TC.skinDeep)
    g.sphere(100, 34, 26, TC.skin)
    let cap1 = g.clipped(Path(CGRect(x: 60, y: 0, width: 80, height: 46)))
    cap1.sphere(100, 32, 27, TC.navy, split: 0.58)
    g.flat(ell(100, 45, 27, 5), hexColor(0x1E2848)); g.sphere(100, 6, 3.5, TC.navy)
    g.gloss(90, 16, 20, 8)
}

/// 捕手（正面・しゃがみ）。局所 200×140、足元 (100, 132)。
func drawCatcher(_ ctx: GraphicsContext, feet: Pt, s: CGFloat) {
    let g = Rig(ctx, feet: feet, s: s, feetLocal: Pt(x: 100, y: 132))
    g.shadow(100, 132, 120, 16)
    for sgn in [-1.0, 1.0] {
        g.cel(cap(Pt(x: 100 + 20 * sgn, y: 92), Pt(x: 100 + 54 * sgn, y: 100), w: 26), TC.white)         // 太もも
        g.cel(rr(100 + 54 * sgn - 13, 98, 26, 30, 8), TC.gray)                                             // すね当て
        g.cel(rr(100 + 54 * sgn - 15, 124, 30, 10, 5), TC.dark)
    }
    g.cel(rr(62, 56, 76, 52, 16), TC.navy)                                                                 // 胸当て
    g.cel(rr(68, 60, 64, 16, 8), Tone(l: 0x7A8CC4, d: 0x3C4C80))
    g.cel(cap(Pt(x: 70, y: 66), Pt(x: 54, y: 96), w: 14), TC.skin); g.sphere(52, 100, 8, TC.skin)          // 右手（画面左）は膝
    g.cel(cap(Pt(x: 130, y: 66), Pt(x: 150, y: 72), w: 14), TC.skin)
    g.sphere(158, 66, 21, TC.mitt, split: 0.5); g.flat(ell(156, 68, 12, 14), hexColor(0xD9A070, 0.7))     // ミット
    g.sphere(100, 32, 24, TC.skin)
    let cap1 = g.clipped(Path(CGRect(x: 60, y: 0, width: 80, height: 34)))
    cap1.sphere(100, 30, 26, TC.navy, split: 0.58)
    g.stroke(rr(80, 20, 40, 36, 12), hexColor(0x9A9AA6), w: 3)                                             // マスク
    for y in [30.0, 40.0, 50.0] { g.stroke(cap(Pt(x: 82, y: y), Pt(x: 118, y: y), w: 0.1), hexColor(0x9A9AA6), w: 2.2) }
}

/// 審判（捕手の後ろ・前かがみ）。局所 200×200、足元 (100, 190)。捕手に大半が隠れる。
func drawUmpire(_ ctx: GraphicsContext, feet: Pt, s: CGFloat) {
    let g = Rig(ctx, feet: feet, s: s, feetLocal: Pt(x: 100, y: 190))
    g.cel(cap(Pt(x: 80, y: 120), Pt(x: 70, y: 180), w: 24), TC.gray); g.cel(cap(Pt(x: 120, y: 120), Pt(x: 130, y: 180), w: 24), TC.gray)
    g.cel(rr(58, 60, 84, 70, 20), TC.ump, split: 0.6)
    g.cel(cap(Pt(x: 66, y: 74), Pt(x: 58, y: 118), w: 15), TC.ump); g.cel(cap(Pt(x: 134, y: 74), Pt(x: 142, y: 118), w: 15), TC.ump)
    g.sphere(60, 122, 8, TC.skin); g.sphere(140, 122, 8, TC.skin)
    g.sphere(100, 36, 24, TC.skin)
    let cap1 = g.clipped(Path(CGRect(x: 60, y: 0, width: 80, height: 36)))
    cap1.sphere(100, 34, 26, TC.ump, split: 0.58)
    g.stroke(rr(80, 24, 40, 36, 12), hexColor(0x9A9AA6), w: 3)
    for y in [34.0, 44.0, 54.0] { g.stroke(cap(Pt(x: 82, y: y), Pt(x: 118, y: y), w: 0.1), hexColor(0x9A9AA6), w: 2.2) }
}

/// ボール（白のトゥーン球 + 赤い縫い目）。
func drawBall(_ ctx: GraphicsContext, at c: Pt, r: CGFloat, alpha: Double = 1) {
    var cc = ctx; cc.opacity = alpha
    cc.fill(ell(c.x, c.y, r, r), with: Toon.sphere(Tone(l: 0xFFFFFF, d: 0xC8C8D2), center: c, r: r, split: 0.62))
    for sgn in [-1.0, 1.0] {
        var p = Path(); p.move(to: Pt(x: c.x + r * 0.5 * sgn, y: c.y - r * 0.78)); p.addQuadCurve(to: Pt(x: c.x + r * 0.5 * sgn, y: c.y + r * 0.78), control: Pt(x: c.x + r * 1.15 * sgn, y: c.y))
        cc.stroke(p, with: .color(hexColor(0xD43C2C)), lineWidth: max(1, r * 0.13))
    }
}

// MARK: - 打席のカメラと球場（センターカメラ）

enum Phase { case pitch, impact }
enum BannerPos { case none, bottom, top }
let atBatCam = Cam(pos: V3(0, 6.5, 50), target: V3(0, 1.5, 0), fpx: 4400)
/// ボールが到達する点（本塁上・ベルトの高さ）= 的の位置。第 1 弾はコース固定（真ん中）。
let ringWorld = V3(0, 0.95, 0.25)

func drawStadium3D(_ ctx: GraphicsContext, _ cam: Cam, size: CGSize) {
    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(colors: [hexColor(0x3E8FD8), hexColor(0xBFE2F7)]), startPoint: .zero, endPoint: Pt(x: 0, y: 260)))
    // バックネット裏のスタンド（Z = -17 の壁）。客席の粒を世界座標で置くので遠近が自動で付く
    let zW = -17.0, wallTop = 0.9, standsTop = 12.0
    ctx.fill(cam.poly([V3(-40, wallTop, zW), V3(40, wallTop, zW), V3(40, standsTop, zW), V3(-40, standsTop, zW)]), with: .linearGradient(Gradient(colors: [hexColor(0x1C2440), hexColor(0x5A6890)]), startPoint: cam.project(V3(0, standsTop, zW)), endPoint: cam.project(V3(0, wallTop, zW))))
    var rng = LCG(11)
    var crowd = ctx; crowd.addFilter(.blur(radius: 1.6))
    var y = wallTop + 0.4
    while y < standsTop {
        var x = -40.0
        while x < 40 {
            let p = V3(x + rng.unit() * 0.12, y, zW), sp = cam.project(p), d = cam.ppm(p) * 0.26
            if sp.y > -10 && sp.y < size.height { crowd.fill(ell(sp.x, sp.y, d / 2, d / 2 * 1.2), with: .color(hexColor(TC.crowd[Int(rng.next() % 10)], 0.9))) }
            x += 0.34
        }
        y += 0.48
    }
    // 屋根の影（上段ほど暗い）とバックネット
    let top = cam.project(V3(0, standsTop, zW)).y, base = cam.project(V3(0, 0, zW)).y
    ctx.fill(Path(CGRect(x: 0, y: min(0, top), width: size.width, height: base - min(0, top))), with: .linearGradient(Gradient(colors: [.black.opacity(0.5), .clear]), startPoint: Pt(x: 0, y: 0), endPoint: Pt(x: 0, y: base * 0.75)))
    var nx = -40.0; while nx < 40 { ctx.stroke(cam.line([V3(nx, 0, zW + 0.5), V3(nx, standsTop, zW + 0.5)]), with: .color(.black.opacity(0.13)), lineWidth: 1); nx += 0.9 }
    // 緑のフェンスパッド（壁の下端）
    ctx.fill(cam.poly([V3(-40, 0, zW), V3(40, 0, zW), V3(40, wallTop, zW), V3(-40, wallTop, zW)]), with: .linearGradient(Gradient(colors: [hexColor(0x2E7A4C), hexColor(0x1F5A36)]), startPoint: cam.project(V3(0, wallTop, zW)), endPoint: cam.project(V3(0, 0, zW))))
    ctx.stroke(cam.line([V3(-40, wallTop, zW), V3(40, wallTop, zW)]), with: .color(hexColor(0xF0C030)), lineWidth: 2)
    // 芝（壁の下端から画面下まで）と刈り筋
    ctx.fill(Path(CGRect(x: 0, y: base - 1, width: size.width, height: size.height - base + 1)), with: .linearGradient(Gradient(colors: [hexColor(0x5AAE58), hexColor(TC.grassD)]), startPoint: Pt(x: 0, y: base), endPoint: Pt(x: 0, y: size.height)))
    var sx = -40.0; var k = 0
    while sx < 40 { if k % 2 == 0 { ctx.fill(cam.poly([V3(sx, 0, zW), V3(sx + 2.6, 0, zW), V3(sx + 2.6, 0, 46), V3(sx, 0, 46)]), with: .color(.white.opacity(0.07))) }; sx += 2.6; k += 1 }
    // 土: 本塁の円・走路・マウンド
    let dirt = GraphicsContext.Shading.linearGradient(Gradient(colors: [hexColor(TC.dirtL), hexColor(TC.dirtD)]), startPoint: Pt(x: 0, y: base), endPoint: Pt(x: 0, y: size.height))
    ctx.fill(cam.circle(V3(0, 0.01, 0), r: 4.2), with: dirt)
    for a in [-45.0, 45.0] {
        let d = polar(1, a), n = V3(d.z, 0, -d.x)
        ctx.fill(cam.poly([polar(3.6, a) + n * 0.55, polar(34, a) + n * 0.55, polar(34, a) - n * 0.55, polar(3.6, a) - n * 0.55]), with: dirt)
    }
    ctx.fill(cam.circle(V3(0, 0.2, 18.44), r: 2.75), with: dirt)
    ctx.fill(cam.poly([V3(-0.3, 0.26, 18.44), V3(0.3, 0.26, 18.44), V3(0.3, 0.26, 18.6), V3(-0.3, 0.26, 18.6)]), with: .color(.white.opacity(0.9)))
    // 白線: ファウルライン・バッターボックス・本塁
    let line = GraphicsContext.Shading.color(.white.opacity(0.85))
    for a in [-45.0, 45.0] { ctx.stroke(cam.line([polar(0.6, a), polar(46, a)]), with: line, lineWidth: 2.5) }
    for sgn in [-1.0, 1.0] { ctx.stroke(cam.poly([V3(0.37 * sgn, 0.01, -1.0), V3(1.59 * sgn, 0.01, -1.0), V3(1.59 * sgn, 0.01, 0.85), V3(0.37 * sgn, 0.01, 0.85)]), with: line, lineWidth: 2.5) }
    ctx.fill(cam.poly([V3(-0.215, 0.02, 0.215), V3(0.215, 0.02, 0.215), V3(0.215, 0.02, 0), V3(0, 0.02, -0.215), V3(-0.215, 0.02, 0)]), with: .color(.white))
}

func drawAtBatScene(_ ctx: GraphicsContext, size: CGSize, phase: Phase) {
    let cam = atBatCam
    drawStadium3D(ctx, cam, size: size)
    // 奥から順に: 審判 → 捕手 → 打者 → ボール → 投手（手前・背中越し）
    let ump = V3(0.35, 0, -2.7); drawUmpire(ctx, feet: cam.project(ump), s: cam.ppm(ump) * 1.85 / 190)
    let cat = V3(0, 0, -1.6); drawCatcher(ctx, feet: cam.project(cat), s: cam.ppm(cat) * 1.0 / 132)
    let bat = V3(0.95, 0, 0); drawBatter(ctx, feet: cam.project(bat), s: cam.ppm(bat) * 1.9 / 160, pose: phase == .pitch ? .stance : .swing)
    if phase == .pitch {
        let rel = V3(0.45, 1.75, 16.6)
        for i in stride(from: 4, through: 0, by: -1) {
            let t = 0.56 - Double(i) * 0.07, p = rel + (ringWorld - rel) * t
            drawBall(ctx, at: cam.project(p), r: 4 + cam.ppm(p) * 0.085, alpha: i == 0 ? 1 : 0.3 - Double(i) * 0.055)
        }
    } else {
        // インパクト直後: 打球が左翼（+X = 画面右）へ、カメラの脇を抜けて飛び出す
        let p = V3(3.4, 2.8, 6.5), sp = cam.project(p)
        var c = ctx; c.addFilter(.blur(radius: 7)); c.fill(cap(cam.project(V3(0.3, 1.0, 0.5)), sp, w: 16), with: .color(.white.opacity(0.55)))
        drawBall(ctx, at: sp, r: 4 + cam.ppm(p) * 0.085)
        let ip = cam.project(ringWorld)
        var star = Path()
        for i in 0..<12 { let a = Double(i) * .pi / 6, r: CGFloat = i % 2 == 0 ? 30 : 12; let q = Pt(x: ip.x + r * CGFloat(cos(a)), y: ip.y + r * CGFloat(sin(a))); if i == 0 { star.move(to: q) } else { star.addLine(to: q) } }
        star.closeSubpath()
        ctx.fill(star, with: .color(hexColor(0xFFE070, 0.9))); ctx.fill(ell(ip.x, ip.y, 9, 9), with: .color(.white))
    }
    let pit = V3(0.1, 0.25, 18.44); drawPitcherBack(ctx, feet: cam.project(pit), s: cam.ppm(pit) * 1.6 / 190)
}

// MARK: - 外野カメラ（方向つき）。打球の向きにカメラが振られ、フェンスの曲がりとポールで「どこへ飛んだか」が判る

struct Shot {
    let dir: Double, dist: Double, cam: Cam
    init(dir: Double, dist: Double, camR: Double = 48, camH: Double = 13, side: Double = -20, fpx: CGFloat = 820) {
        self.dir = dir; self.dist = dist
        cam = Cam(pos: polar(camR, dir + side, y: camH), target: polar(fenceR(dir), dir, y: 5.5), fpx: fpx)
    }
    /// 打球の弧（見た目は柵の 8 m 先に落ちる放物線）。
    func ball(_ t: Double) -> V3 { let d = dist + 3, h = d * 0.12; var p = polar(d * t, dir); p.y = 1 + 4 * h * t * (1 - t); return p }
}

func drawOutfieldScene(_ ctx: GraphicsContext, size: CGSize, shot: Shot) {
    let cam = shot.cam
    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(colors: [hexColor(0x3E8FD8), hexColor(0xC4E6F8)]), startPoint: .zero, endPoint: Pt(x: 0, y: size.height * 0.45)))
    // 地平線から下は芝
    let far = cam.pos + V3(cam.f.x, 0, cam.f.z) * 4000; let hz = cam.project(V3(far.x, 0, far.z)).y
    ctx.fill(Path(CGRect(x: 0, y: hz, width: size.width, height: size.height - hz)), with: .linearGradient(Gradient(colors: [hexColor(0x4E9E52), hexColor(0x7CC46C)]), startPoint: Pt(x: 0, y: hz), endPoint: Pt(x: 0, y: size.height)))
    // 刈り筋（扇形・5° ごとに交互）
    var a = -60.0
    while a < 60 { if Int((a + 60) / 5) % 2 == 0 { ctx.fill(cam.poly([polar(10, a), polar(10, a + 5), polar(fenceR(a + 5) - 3, a + 5), polar(fenceR(a + 2.5) - 3, a + 2.5), polar(fenceR(a) - 3, a)]), with: .color(.white.opacity(0.07))) }; a += 5 }
    // 外野スタンド（フェンスの外の斜面）に客席の粒
    let slopeL = cam.project(polar(fenceR(shot.dir) + 30, shot.dir - 40, y: 14)), slopeR = cam.project(polar(fenceR(shot.dir) + 30, shot.dir + 40, y: 14))
    var stands: [V3] = []
    for i in 0...40 { let t = -60 + Double(i) * 3; stands.append(polar(fenceR(t) + 2, t, y: 0.4)) }
    for i in 0...40 { let t = 60 - Double(i) * 3; stands.append(polar(fenceR(t) + 32, t, y: 15)) }
    ctx.fill(cam.poly(stands), with: .linearGradient(Gradient(colors: [hexColor(0x5A6890), hexColor(0x1C2440)]), startPoint: Pt(x: 0, y: min(slopeL.y, slopeR.y)), endPoint: Pt(x: 0, y: cam.project(polar(fenceR(shot.dir) + 2, shot.dir, y: 0.4)).y)))
    var rng = LCG(23)
    var crowd = ctx; crowd.addFilter(.blur(radius: 1.1))
    var row = 0.0
    while row < 30 {
        var t = -60.0
        while t < 60 {
            let p = polar(fenceR(t) + 3 + row, t + rng.unit() * 0.2, y: 0.6 + row * 0.47)
            if cam.depth(p) > 3 { let sp = cam.project(p), d = cam.ppm(p) * 0.34; if sp.x > -10 && sp.x < size.width + 10 && sp.y > -10 { crowd.fill(ell(sp.x, sp.y, d / 2, d / 2), with: .color(hexColor(TC.crowd[Int(rng.next() % 10)], 0.9))) } }
            t += 0.5
        }
        row += 1.0
    }
    // ウォーニングトラック → フェンス（緑のパッド・黄線）→ ポール
    var track: [V3] = []; for i in 0...80 { let t = -60 + Double(i) * 1.5; track.append(polar(fenceR(t) - 3.2, t)) }; for i in 0...80 { let t = 60 - Double(i) * 1.5; track.append(polar(fenceR(t) + 0.3, t)) }
    ctx.fill(cam.poly(track), with: .color(hexColor(0xC28C58)))
    var i = -60.0
    while i < 60 {
        let q = cam.poly([polar(fenceR(i), i), polar(fenceR(i + 1.5), i + 1.5), polar(fenceR(i + 1.5), i + 1.5, y: 3.2), polar(fenceR(i), i, y: 3.2)])
        let shade = 0.5 + 0.5 * cos((i - shot.dir) * .pi / 60)
        ctx.fill(q, with: .color(hexColor(0x2E7A4C).opacity(1).mix(with: hexColor(0x1A4A2C), by: 1 - shade)))
        i += 1.5
    }
    var yl: [V3] = []; for k in 0...80 { let t = -60 + Double(k) * 1.5; yl.append(polar(fenceR(t), t, y: 3.2)) }
    ctx.stroke(cam.line(yl), with: .color(hexColor(0xF0C030)), lineWidth: max(2, cam.ppm(polar(fenceR(shot.dir), shot.dir)) * 0.25))
    for pole in [-45.0, 45.0] {
        let b = polar(fenceR(pole), pole), w = cam.ppm(b) * 0.35
        ctx.stroke(cam.line([b, polar(fenceR(pole), pole, y: 22)]), with: .color(hexColor(0xFFD84A)), lineWidth: max(2.5, w))
        ctx.stroke(cam.line([polar(fenceR(pole), pole, y: 22), polar(fenceR(pole) + 6, pole, y: 22)]), with: .color(hexColor(0xFFD84A)), lineWidth: max(2, w * 0.7))
    }
    // 打球の弧（画面に入る範囲だけ）とフェンス上のボール
    let tf = fenceR(shot.dir) / (shot.dist + 3), bp = shot.ball(tf), bsp = cam.project(bp), br = 6 + cam.ppm(bp) * 0.12
    var arc = Path(); var started = false
    var t = 0.0
    while t <= tf + 0.015 { let p = shot.ball(t); if cam.depth(p) > 4 { let sp = cam.project(p); if started { arc.addLine(to: sp) } else { arc.move(to: sp); started = true } }; t += 0.01 }
    ctx.stroke(arc, with: .color(.white.opacity(0.75)), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [7, 9]))
    for k in 1...3 { let q = cam.project(shot.ball(tf - Double(k) * 0.03)); drawBall(ctx, at: q, r: br * (1 - CGFloat(k) * 0.12), alpha: 0.3 - Double(k) * 0.08) }
    var glow = ctx; glow.addFilter(.blur(radius: 10)); glow.fill(ell(bsp.x, bsp.y, br * 2.2, br * 2.2), with: .color(.white.opacity(0.6)))
    drawBall(ctx, at: bsp, r: br)
}

// MARK: - 画面 21〜29（3D 方向）

struct HUD3D: View {
    var phase: Phase = .pitch; var banner: BannerPos = .none
    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 6) {
                HStack {
                    hud("3 / 10 球", icon: "baseball.fill")
                    Spacer()
                    VStack(spacing: 0) { Text("今回").font(T.f(11)).foregroundStyle(.white.opacity(0.85)); Text("246 m").font(T.f(28, .heavy).monospacedDigit()).foregroundStyle(.white) }
                    Spacer()
                    hud("柵越え 1", icon: "flag.checkered")
                }
                .padding(.horizontal, 16).padding(.top, banner == .top ? 112 : 60)
                HStack(spacing: 8) { Chip(text: "1 球目 118 m 左中", fill: .white.opacity(0.9)); Chip(text: "2 球目 128 m 中 柵越え", fill: T.yellow) }
            }
            if phase == .impact {
                VStack(spacing: 2) {
                    Text("ジャスト！").font(T.f(38, .heavy))
                    HStack(spacing: 4) { Image(systemName: "arrow.up.right"); Text("引っ張り・打ち上げ") }.font(T.f(16, .heavy))
                }
                .foregroundStyle(.white).shadow(color: .black.opacity(0.45), radius: 3, y: 2).position(x: 196, y: 300)
            }
            VStack { Spacer()
                HStack(spacing: 8) { Image(systemName: phase == .pitch ? "hand.draw.fill" : "hand.tap.fill"); Text(phase == .pitch ? "押したままずらし、輪が的に重なった瞬間に離す" : "カキーン！ 外野カメラへ") }
                    .font(T.f(14)).foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Capsule().fill(.black.opacity(0.4))).padding(.bottom, banner == .bottom ? 98 : 40)
            }
            HStack { Image(systemName: "pause.fill").font(T.f(15)).foregroundStyle(T.coral).frame(width: 36, height: 36).background(Circle().fill(.white)); Spacer() }
                .padding(.leading, 16).padding(.top, banner == .top ? 160 : 108)
            if banner == .top { adBanner.padding(.top, 54) }
            if banner == .bottom { VStack { Spacer(); adBanner.padding(.bottom, 34) } }
        }
    }
    var adBanner: some View {
        Rectangle().fill(hexColor(0x3A3A40)).frame(height: 50)
            .overlay(Text("バナー広告（打席中・変更案）").font(T.f(12, .medium)).foregroundStyle(.white.opacity(0.8)))
            .padding(.horizontal, 12)
    }
    func hud(_ t: String, icon: String) -> some View {
        HStack(spacing: 5) { Image(systemName: icon).font(T.f(12)); Text(t).font(T.f(14, .heavy).monospacedDigit()) }
            .foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 7).background(Capsule().fill(.black.opacity(0.4)))
    }
}

/// 的（白・固定）・縮む輪（コーラル）・ミート点（黄・指でずらす）。
struct Ring3D: View {
    var shrink: CGFloat = 86; var cursor: CGSize? = CGSize(width: 9, height: 7); var label = true
    var body: some View {
        let p = atBatCam.project(ringWorld)
        ZStack {
            Circle().fill(.white.opacity(0.16)).frame(width: 46, height: 46)
            Circle().stroke(.white, lineWidth: 1).frame(width: 46, height: 46)
            Circle().fill(T.coral.opacity(0.10)).frame(width: shrink, height: shrink)
            Circle().stroke(T.coral, lineWidth: 5).frame(width: shrink, height: shrink).shadow(color: T.coral.opacity(0.7), radius: 6)
            if let c = cursor {
                Ellipse().stroke(T.yellow, lineWidth: 3).frame(width: 30, height: 21).shadow(color: .black.opacity(0.45), radius: 2).offset(c)
                Circle().fill(T.yellow).frame(width: 5, height: 5).offset(c)
                if label {
                    Path { q in q.move(to: Pt(x: c.width - 14, y: 10 + c.height)); q.addLine(to: Pt(x: -58, y: 64)) }.stroke(T.yellow, lineWidth: 1.5).frame(width: 1, height: 1)
                    Text("ミート点（指でずらす）").font(T.f(11, .heavy)).foregroundStyle(T.onAccent).padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(T.yellow)).offset(x: -104, y: 74)
                }
            }
        }.position(p)
    }
}

struct AtBat3D: View {
    var phase: Phase = .pitch; var banner: BannerPos = .none
    var body: some View {
        ZStack(alignment: .top) {
            Canvas { ctx, size in drawAtBatScene(ctx, size: size, phase: phase) }
            if phase == .pitch { Ring3D(label: banner == .none) }
            HUD3D(phase: phase, banner: banner)
        }
    }
}

struct Outfield3D: View {
    let shot: Shot; let title: String; let dist: String; let chips: [(String, Color, String)]; let footer: String
    var body: some View {
        ZStack(alignment: .top) {
            Canvas { ctx, size in drawOutfieldScene(ctx, size: size, shot: shot) }
            // 距離表示（フェンスの位置に投影）
            ForEach([-45.0, -22.5, 0.0, 22.5, 45.0], id: \.self) { a in
                let p = polar(fenceR(a) - 0.3, a, y: 1.7)
                if shot.cam.depth(p) > 8 {
                    let sp = shot.cam.project(p), s = shot.cam.ppm(p)
                    if sp.x > 20 && sp.x < 373 { Text("\(Int(fenceR(a).rounded()))m").font(.system(size: max(9, s * 1.4), weight: .heavy)).foregroundStyle(.white.opacity(0.9)).position(sp) }
                }
            }
            VStack(spacing: 4) {
                Text(title).font(T.f(46, .black)).foregroundStyle(T.yellow).shadow(color: .black.opacity(0.4), radius: 3, y: 3)
                Text(dist).font(T.f(62, .black).monospacedDigit()).foregroundStyle(.white).shadow(color: .black.opacity(0.4), radius: 3, y: 3)
                HStack(spacing: 6) { ForEach(0..<chips.count, id: \.self) { i in Chip(text: chips[i].0, fill: chips[i].1, icon: chips[i].2) } }
            }.padding(.top, 78)
            ForEach(0..<28, id: \.self) { i in
                let x = CGFloat((i * 71) % 380) + 6, y = CGFloat((i * 137) % 300) + 250
                RoundedRectangle(cornerRadius: 1).fill([T.coral, T.teal, T.pink, T.yellow][i % 4]).frame(width: 6, height: 10).rotationEffect(.degrees(Double(i * 37))).position(x: x, y: y)
            }
            VStack { Spacer(); HStack(spacing: 6) { Image(systemName: "baseball.fill"); Text(footer) }.font(T.f(14, .heavy)).foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 8).background(Capsule().fill(.black.opacity(0.4))).padding(.bottom, 40) }
        }
    }
}

struct Batter3DView: View {
    var pose: Pose = .stance; var heads: CGFloat = 2.2; var w: CGFloat = 120; var h: CGFloat = 130
    var body: some View { Canvas { ctx, size in drawBatter(ctx, feet: Pt(x: size.width / 2, y: size.height - 6), s: (size.height - 8) / 176, pose: pose, heads: heads) }.frame(width: w, height: h) }
}

struct Lobby3D: View {
    var remaining = 2
    var body: some View {
        ZStack(alignment: .bottom) {
            T.bg.ignoresSafeArea()
            VStack(spacing: 12) {
                NavBar(title: "柵越えおじさん")
                VStack(spacing: 12) {
                    Card {
                        HStack(alignment: .center, spacing: 10) {
                            Batter3DView(w: 110, h: 122)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("1 挑戦 = 10 球").font(T.f(20, .heavy)).foregroundStyle(T.ink)
                                Text("タイミングとミート点で柵を越えろ。引っ張れば飛ぶ、切れればファウル。アウトは無い。10 球ぜんぶ振れる。").font(T.f(12, .medium)).foregroundStyle(T.inkSub)
                                Chip(text: "体験版", fill: T.fillPurple, icon: "sparkles")
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack { Text("今日の挑戦").font(T.f(15)).foregroundStyle(T.ink); Spacer(); Text("残り \(remaining) / 3").font(T.f(15, .heavy)).foregroundStyle(T.coral) }
                            Challenges(remaining: remaining, total: 3)
                            Text("0:00 に 3 回に戻ります").font(T.f(12, .medium)).foregroundStyle(T.inkSub)
                            HStack(spacing: 8) {
                                LobbyTrial().smallButton("広告を見て +1", sub: "1 本 30 秒・きょう あと 5 本", icon: "play.rectangle.fill", fill: T.fillCoral)
                                LobbyTrial().smallButton("アンケートで +1", sub: "3 問・30 秒・1 日 1 回", icon: "list.bullet.clipboard.fill", fill: T.fillPurple)
                            }
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("きろく").font(T.f(15)).foregroundStyle(T.ink)
                            HStack { LobbyTrial().stat("自己ベスト", "812 m"); Spacer(); LobbyTrial().stat("最長の 1 本", "131 m"); Spacer(); LobbyTrial().stat("通算 柵越え", "27 本") }
                            HStack(spacing: 6) { Image(systemName: "trophy.fill").foregroundStyle(T.coral); Text("順位表（Game Center）").font(T.f(13)).foregroundStyle(T.coral) }
                        }
                    }
                    BigButton(text: "打席に立つ", icon: "figure.baseball")
                    Text("挑戦回数は打席に立った時点で 1 つ減ります").font(T.f(11, .medium)).foregroundStyle(T.inkSub)
                }.padding(.horizontal, 16)
                Spacer(minLength: 0)
                Banner().padding(.bottom, 24)
            }
        }
    }
}

/// 10 球の内訳（方向・ファウル入り）と打球の散らばり。
struct Result3D: View {
    struct B { let d: Int; let kind: String; let dir: String; let deg: Double }
    let balls: [B] = [
        B(d: 118, kind: "hit", dir: "左中", deg: 24), B(d: 0, kind: "foul", dir: "ファウル", deg: 52), B(d: 131, kind: "hr", dir: "左中", deg: 26), B(d: 96, kind: "hit", dir: "中", deg: 2),
        B(d: 104, kind: "hr", dir: "右翼線", deg: -43), B(d: 0, kind: "miss", dir: "空振り", deg: 0), B(d: 88, kind: "hit", dir: "中", deg: -4), B(d: 47, kind: "hit", dir: "右中", deg: -18),
        B(d: 122, kind: "hr", dir: "中", deg: 4), B(d: 109, kind: "hit", dir: "右中", deg: -20),
    ]
    var body: some View {
        ZStack(alignment: .bottom) {
            T.bg.ignoresSafeArea()
            VStack(spacing: 10) {
                NavBar(title: "柵越えおじさん")
                VStack(spacing: 10) {
                    Card {
                        HStack(spacing: 10) {
                            Batter3DView(pose: .cheer, w: 110, h: 112)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("10 球の結果").font(T.f(13)).foregroundStyle(T.inkSub)
                                Text("815 m").font(T.f(40, .black).monospacedDigit()).foregroundStyle(T.ink)
                                HStack(spacing: 6) { Chip(text: "柵越え 3 本", fill: T.yellow, icon: "flag.checkered"); Chip(text: "ベスト更新！", fill: T.pink) }
                            }
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("1 球ずつ").font(T.f(15)).foregroundStyle(T.ink)
                                    ForEach(0..<10, id: \.self) { i in row(i) }
                                }
                                VStack(spacing: 4) {
                                    Text("打球の散らばり").font(T.f(12)).foregroundStyle(T.ink)
                                    spray.frame(width: 150, height: 132)
                                    Text("★ 柵越え ● 当たり ○ ファウル").font(T.f(9, .medium)).foregroundStyle(T.inkSub)
                                }
                            }
                            HStack { Text("最長 131 m（3 球目・ジャスト・左中間）").font(T.f(11, .medium)).foregroundStyle(T.inkSub); Spacer(); Text("順位表に送信済み").font(T.f(11, .medium)).foregroundStyle(T.inkSub) }
                        }
                    }
                    HStack(spacing: 10) {
                        BigButton(text: "もう一回（残り 1）", icon: "arrow.counterclockwise")
                        BigButton(text: "ホームへ", fill: hexColor(0xEFE7DC), fg: T.ink).frame(width: 120)
                    }
                }.padding(.horizontal, 16)
                Spacer(minLength: 0)
                Banner().padding(.bottom, 24)
            }
        }
    }
    func row(_ i: Int) -> some View {
        let b = balls[i]
        let (icon, tint): (String, Color) = b.kind == "hr" ? ("star.fill", T.yellow) : (b.kind == "hit" ? ("baseball.fill", T.teal) : (b.kind == "foul" ? ("circle", T.inkSub) : ("xmark", T.inkSub)))
        return HStack(spacing: 5) {
            Text("\(i + 1)").font(T.f(10, .heavy).monospacedDigit()).foregroundStyle(T.inkSub).frame(width: 18, alignment: .trailing)
            Image(systemName: icon).font(T.f(10)).foregroundStyle(tint).frame(width: 12)
            Text(b.d > 0 ? "\(b.d) m" : "—").font(T.f(12, .heavy).monospacedDigit()).foregroundStyle(T.ink).frame(width: 46, alignment: .trailing)
            Text(b.dir).font(T.f(10, .medium)).foregroundStyle(b.kind == "foul" || b.kind == "miss" ? T.coral : T.inkSub)
        }
        .padding(.horizontal, 6).padding(.vertical, 2).background(RoundedRectangle(cornerRadius: 6).fill(b.kind == "hr" ? T.yellow.opacity(0.25) : hexColor(0xF7F1E8)))
    }
    var spray: some View {
        Canvas { ctx, size in
            let home = Pt(x: size.width / 2, y: size.height - 8), k = (size.height - 16) / 125
            func at(_ r: Double, _ deg: Double) -> Pt { let t = deg * .pi / 180; return Pt(x: home.x + CGFloat(r * sin(t)) * k, y: home.y - CGFloat(r * cos(t)) * k) }
            var field = Path(); field.move(to: home)
            for i in 0...60 { let a = -45 + Double(i) * 1.5; field.addLine(to: at(fenceR(a), a)) }
            field.closeSubpath()
            ctx.fill(field, with: .color(hexColor(0x7CC46C, 0.55)))
            ctx.stroke(field, with: .color(hexColor(0x3E8E45)), lineWidth: 1.5)
            for (l, r) in [(10.0, 45.0), (-10.0, 10.0), (-45.0, -10.0)] {
                var cone = Path(); cone.move(to: home); cone.addLine(to: at(fenceR(l) + 14, l)); cone.addLine(to: at(fenceR(r) + 14, r)); cone.closeSubpath()
                ctx.fill(cone, with: .color((l == 10 ? T.coral : (l == -10 ? T.teal : T.purple)).opacity(0.10)))
            }
            for b in balls where b.kind != "miss" {
                let p = at(Double(b.kind == "foul" ? 60 : b.d), b.deg)
                if b.kind == "hr" { ctx.fill(ell(p.x, p.y, 5, 5), with: .color(T.yellow)); ctx.stroke(ell(p.x, p.y, 5, 5), with: .color(hexColor(0xC4901C)), lineWidth: 1) }
                else if b.kind == "hit" { ctx.fill(ell(p.x, p.y, 4, 4), with: .color(T.teal)) }
                else { ctx.stroke(ell(p.x, p.y, 4, 4), with: .color(T.inkSub), lineWidth: 1.5) }
            }
            ctx.fill(ell(home.x, home.y, 3, 3), with: .color(T.ink))
        }
    }
}

/// メカニクスの説明: 操作（押す→ずらす→離す）・ミート点の帯（方向 × 角度）・球場の柵距離。
struct Mechanics: View {
    let cols = ["ファウル", "流し\n×0.92", "センター\n×1.00", "引っ張り\n×1.10", "ファウル"]
    let rows = ["ゴロ ×0.30", "ライナー ×0.85", "打ち上げ ×1.00", "ポップ ×0.45"]
    let rowK: [Double] = [0.30, 0.85, 1.00, 0.45], colK: [Double] = [0, 0.92, 1.00, 1.10, 0]
    var body: some View {
        ZStack(alignment: .top) {
            T.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 10) {
                Text("打つ = タイミング × ミート点").font(T.f(24, .heavy)).foregroundStyle(T.ink).padding(.top, 62)
                Text("タイミング（縮む輪）が初速、ミート点（指でずらす）が方向と角度を決める。ミート点の初期位置はボールの真ん中（= センター・ライナー）。").font(T.f(12, .medium)).foregroundStyle(T.inkSub)
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("操作は 1 本の指で 3 拍").font(T.f(15)).foregroundStyle(T.ink)
                        HStack(spacing: 6) {
                            step("1", "押す", "画面のどこでも。投球が始まったら", "hand.tap.fill", T.teal)
                            step("2", "ずらす", "ミート点が指と同じだけ動く（トラックパッド式）", "hand.draw.fill", T.purple)
                            step("3", "離す", "輪が的に重なった瞬間 = タイミング", "hand.raised.fill", T.coral)
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text("ミート点の帯（右打者）").font(T.f(15)).foregroundStyle(T.ink); Spacer(); Text("← 外側　　内側 →").font(T.f(11, .medium)).foregroundStyle(T.inkSub) }
                        grid
                        Text("一番飛ぶのは「ボールの少し下・少し内側」。ずらしすぎると崖（ファウル / ポップ）に落ちるのが駆け引き。ゴロは柵越え不可。").font(T.f(11, .medium)).foregroundStyle(T.inkSub).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("柵までの距離は方向で変わる").font(T.f(15)).foregroundStyle(T.ink)
                        HStack(alignment: .top, spacing: 10) {
                            field.frame(width: 160, height: 118)
                            VStack(alignment: .leading, spacing: 4) {
                                legend(T.coral, "引っ張り: 柵 100〜114 m・×1.10。当たりでもポール際なら越えるが、切れればファウル")
                                legend(T.teal, "センター: 柵 114〜120 m・×1.00。安全だがジャスト以外は届きにくい")
                                legend(T.purple, "流し: 柵 100〜114 m・×0.92。帯が広く手堅い")
                            }
                        }
                        Text("最大飛距離 140 m（ジャスト・打ち上げ・センター）。ナイス 88%・当たり 72%。乱数なし。").font(T.f(11, .medium)).foregroundStyle(T.inkSub).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }.padding(.horizontal, 16)
        }
    }
    func step(_ n: String, _ t: String, _ sub: String, _ icon: String, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            ZStack { Circle().fill(tint.opacity(0.18)).frame(width: 44, height: 44); Image(systemName: icon).font(T.f(20)).foregroundStyle(tint) }
            Text("\(n). \(t)").font(T.f(13, .heavy)).foregroundStyle(T.ink)
            Text(sub).font(T.f(9.5, .medium)).foregroundStyle(T.inkSub).multilineTextAlignment(.center).frame(height: 36, alignment: .top)
        }.frame(maxWidth: .infinity)
    }
    func legend(_ c: Color, _ t: String) -> some View {
        HStack(alignment: .top, spacing: 5) { Circle().fill(c).frame(width: 8, height: 8).padding(.top, 3); Text(t).font(T.f(10, .medium)).foregroundStyle(T.inkSub).fixedSize(horizontal: false, vertical: true) }
    }
    var grid: some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Text("").frame(width: 70)
                ForEach(0..<5, id: \.self) { c in Text(cols[c]).font(T.f(9.5, .heavy)).foregroundStyle(c == 0 || c == 4 ? T.inkSub : T.ink).multilineTextAlignment(.center).frame(maxWidth: .infinity).frame(height: 26) }
            }
            ForEach(0..<4, id: \.self) { r in
                HStack(spacing: 3) {
                    Text(rows[r]).font(T.f(9, .heavy)).foregroundStyle(T.ink).frame(width: 70, alignment: .leading)
                    ForEach(0..<5, id: \.self) { c in cell(r, c) }
                }
            }
            HStack { Text("↑ ミート点を上に").font(T.f(9, .medium)); Spacer(); Text("ミート点を下に ↓").font(T.f(9, .medium)) }.foregroundStyle(T.inkSub).padding(.leading, 70)
        }
    }
    func cell(_ r: Int, _ c: Int) -> some View {
        let v = rowK[r] * colK[c]
        let foul = c == 0 || c == 4
        let fill: Color = foul ? hexColor(0xE6DED3) : (r == 0 ? hexColor(0xEFE7DC) : T.yellow.opacity(0.12 + v * 0.7))
        return ZStack {
            RoundedRectangle(cornerRadius: 6).fill(fill)
            if r == 2 && c == 3 { RoundedRectangle(cornerRadius: 6).stroke(T.coral, lineWidth: 2.5) }
            if r == 1 && c == 2 { Circle().fill(.white).frame(width: 16, height: 16).overlay(Circle().stroke(hexColor(0xD43C2C), lineWidth: 1.5)) }
            else if foul { Text("0").font(T.f(10, .heavy)).foregroundStyle(T.inkSub) }
            else { Text(String(format: "%.2f", v)).font(T.f(10, .heavy).monospacedDigit()).foregroundStyle(T.ink) }
        }.frame(maxWidth: .infinity).frame(height: 30)
    }
    var field: some View {
        Canvas { ctx, size in
            let home = Pt(x: size.width / 2, y: size.height - 6), k = (size.height - 14) / 124
            func at(_ r: Double, _ deg: Double) -> Pt { let t = deg * .pi / 180; return Pt(x: home.x + CGFloat(r * sin(t)) * k, y: home.y - CGFloat(r * cos(t)) * k) }
            for (l, r, c) in [(10.0, 45.0, T.coral), (-10.0, 10.0, T.teal), (-45.0, -10.0, T.purple)] {
                var cone = Path(); cone.move(to: home)
                for i in 0...20 { let a = l + (r - l) * Double(i) / 20; cone.addLine(to: at(fenceR(a), a)) }
                cone.closeSubpath(); ctx.fill(cone, with: .color(c.opacity(0.22))); ctx.stroke(cone, with: .color(c), lineWidth: 1)
            }
            for (a, t) in [(-45.0, "100"), (-22.5, "114"), (0.0, "120"), (22.5, "114"), (45.0, "100")] {
                let p = at(fenceR(a) + 9, a)
                ctx.draw(Text(t).font(T.f(9, .heavy)).foregroundStyle(T.ink), at: p)
            }
            ctx.fill(ell(home.x, home.y, 3, 3), with: .color(T.ink))
        }
    }
}

/// 3D トゥーンのキャラ案: 4 ポーズ・頭身 3 段・投手（背中）・捕手。
struct Character3D: View {
    var body: some View {
        ZStack(alignment: .top) {
            T.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 10) {
                Text("3D トゥーン: 柵越えおじさん").font(T.f(24, .heavy)).foregroundStyle(T.ink).padding(.top, 62)
                Text("セル 2 階調 + ハイライト・輪郭線なし（現行パワプロ系のトゥーン調シェーディングの見え方）。顔の特徴と黄・紺の配色は Core の OjisanPixel と同じ。本物の 3D モデルではなく、実装の目標の絵。").font(T.f(11.5, .medium)).foregroundStyle(T.inkSub)
                Card {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ユニフォーム姿・4 ポーズ（2.2 頭身）").font(T.f(15)).foregroundStyle(T.ink)
                        Canvas { ctx, _ in
                            for (i, pose) in [Pose.stance, .swing, .cheer, .frown].enumerated() {
                                drawBatter(ctx, feet: Pt(x: 45 + CGFloat(i) * 92, y: 138), s: 0.78, pose: pose)
                            }
                        }.frame(height: 148)
                        HStack { ForEach(["構え", "スイング", "柵越え", "空振り"], id: \.self) { Text($0).font(T.f(11)).foregroundStyle(T.inkSub).frame(maxWidth: .infinity) } }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("頭身の 3 案（3D 化で改めて比較）").font(T.f(15)).foregroundStyle(T.ink)
                        Canvas { ctx, _ in
                            for (i, h) in [2.0, 2.5, 3.0].enumerated() { drawBatter(ctx, feet: Pt(x: 60 + CGFloat(i) * 120, y: 126), s: 0.68, pose: .stance, heads: h) }
                        }.frame(height: 134)
                        HStack { ForEach(["2 頭身（パワプロ寄り）", "2.5 頭身", "3 頭身（写実寄り）"], id: \.self) { Text($0).font(T.f(11)).foregroundStyle(T.inkSub).frame(maxWidth: .infinity) } }
                    }
                }
                Card {
                    HStack(alignment: .top, spacing: 8) {
                        Canvas { ctx, _ in
                            drawPitcherBack(ctx, feet: Pt(x: 50, y: 118), s: 0.58)
                            drawCatcher(ctx, feet: Pt(x: 150, y: 118), s: 0.66)
                        }.frame(width: 200, height: 124)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("投手（背中越し）と捕手").font(T.f(13, .heavy)).foregroundStyle(T.ink)
                            Text("投手は名無し・背番号なし。捕手と審判は打席の一直線を埋める「野球らしさ」の部品で、判定には関わらない。").font(T.f(10.5, .medium)).foregroundStyle(T.inkSub)
                        }
                    }
                }
            }.padding(.horizontal, 16)
        }
    }
}

/// 打席中のバナー広告の 2 案（下部 / 上部）を並べる（会長発言「上部か下部にバナーを」の比較材料）。
struct BannerCompare: View {
    var body: some View {
        ZStack(alignment: .top) {
            T.bg.ignoresSafeArea()
            VStack(spacing: 8) {
                Text("打席中のバナー広告: 変更案 2 つ").font(T.f(22, .heavy)).foregroundStyle(T.ink).padding(.top, 62)
                Text("現行方針（バナー無し）は `22-at-bat-3d.jpg`。下部案は既存ゲームと同じ枠、上部案は HUD を 52pt 下げる。").font(T.f(11, .medium)).foregroundStyle(T.inkSub).multilineTextAlignment(.center).padding(.horizontal, 20)
                HStack(alignment: .top, spacing: 12) {
                    col("下部（既存ゲームと同じ）", .bottom)
                    col("上部（HUD を下げる）", .top)
                }
            }
        }
    }
    func col(_ t: String, _ b: BannerPos) -> some View {
        VStack(spacing: 6) {
            AtBat3D(banner: b).frame(width: screenW, height: screenH).clipShape(RoundedRectangle(cornerRadius: 40))
                .scaleEffect(0.44).frame(width: screenW * 0.44, height: screenH * 0.44)
            Text(t).font(T.f(12, .heavy)).foregroundStyle(T.ink)
        }
    }
}

// MARK: - 書き出し

@MainActor
func write<V: View>(_ v: V, _ name: String, dir: String, scale: CGFloat = 2) {
    let r = ImageRenderer(content: v)
    r.scale = scale
    guard let cg = r.cgImage else { print("no image: \(name)"); return }
    let rep = NSBitmapImageRep(cgImage: cg)
    let data = rep.representation(using: .png, properties: [:])!
    let url = URL(fileURLWithPath: dir).appendingPathComponent(name + ".png")
    try! data.write(to: url)
    print("wrote \(url.lastPathComponent) \(cg.width)x\(cg.height)")
}

MainActor.assumeIsolated {
    let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
    // 3D 方向（会長決裁 2026-09-24 夜）。`--3d` を付けるとこの系列だけ書き出す
    write(Phone { Lobby3D() }, "21-lobby-3d", dir: dir)
    write(Phone(dark: true) { AtBat3D() }, "22-at-bat-3d", dir: dir)
    write(Phone(dark: true) { AtBat3D(phase: .impact) }, "23-at-bat-3d-impact", dir: dir)
    write(Phone(dark: true) { Outfield3D(shot: Shot(dir: 25, dist: 131), title: "柵越え！", dist: "131 m", chips: [("ジャスト", T.yellow, "star.fill"), ("引っ張り・左中間", T.fillCoral, "arrow.up.right")], footer: "3 球目まで 249 m ／ 柵越え 2") }, "24-outfield-leftcenter", dir: dir)
    write(Phone(dark: true) { Outfield3D(shot: Shot(dir: -43, dist: 104, side: 18), title: "ポール際 柵越え！", dist: "104 m", chips: [("当たり", .white.opacity(0.9), "baseball.fill"), ("流し・右翼線", T.fillPurple, "arrow.up.left")], footer: "5 球目まで 449 m ／ 柵越え 2") }, "25-outfield-rightline", dir: dir)
    write(Phone { Result3D() }, "26-result-3d", dir: dir)
    write(Phone { Mechanics() }, "27-mechanics", dir: dir)
    write(Phone { Character3D() }, "28-character-3d", dir: dir)
    write(Phone { BannerCompare() }, "29-banner-compare", dir: dir)
    if CommandLine.arguments.contains("--3d") { return }
    write(Phone { LobbyTrial() }, "01-lobby-trial", dir: dir)
    write(Phone { LobbyFull() }, "02-lobby-full", dir: dir)
    write(Phone(dark: true) { AtBat() }, "03-at-bat", dir: dir)
    write(Phone(dark: true) { Outfield() }, "04-outfield", dir: dir)
    write(Phone { Result() }, "05-result", dir: dir)
    write(Phone { Recover() }, "06-recover", dir: dir)
    write(Phone { CharacterSheet() }, "07-character", dir: dir)
    write(Phone { Placement() }, "08-placement", dir: dir)
    // ドット絵だけの大きなシート（レビュー用・6 倍）
    var sheet = PixelCanvas(w: 3 * 64, h: 4 * 60)
    for (i, p) in proportions.enumerated() { for (j, pose) in [Pose.stance, .swing, .cheer, .frown].enumerated() {
        sheet.blit(ojisan(p, pose: pose), i * 64 + 4, j * 60 + 4)
    } }
    if let cg = sheet.cgImage(scale: 6) {
        let rep = NSBitmapImageRep(cgImage: cg)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: dir).appendingPathComponent("09-pixel-sheet.png"))
        print("wrote 09-pixel-sheet.png")
    }
    var pc = PixelCanvas(w: 80, h: 44); pc.blit(pitcher(), 2, 2); pc.blit(ball(), 50, 10)
    if let cg = pc.cgImage(scale: 6) {
        try! NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: dir).appendingPathComponent("10-pitcher-ball.png"))
    }
    // 方向A / 方向B（会長決裁 2026-09-24: 両方向のモックを作って比較する）
    write(Phone(dark: true) { AtBatA() }, "11-at-bat-A", dir: dir)
    write(Phone(dark: true) { AtBatB() }, "12-at-bat-B", dir: dir)
    write(Phone { CharacterA() }, "13-character-A", dir: dir)
    write(Phone { CharacterB() }, "14-character-B", dir: dir)
    write(Phone { CompareAB() }, "15-compare-AB", dir: dir)
    var hd = PixelCanvas(w: 4 * 80 + 70, h: 96)
    for (j, pose) in [Pose.stance, .swing, .cheer, .frown].enumerated() { hd.blit(ojisanHD(pose), j * 80 + 4, 4) }
    hd.blit(pitcherHD(), 4 * 80 + 8, 20)
    if let cg = hd.cgImage(scale: 6) {
        try! NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: dir).appendingPathComponent("16-pixel-sheet-A.png"))
        print("wrote 16-pixel-sheet-A.png")
    }
}
