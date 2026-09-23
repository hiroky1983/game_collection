// 柵越えおじさん（プレミアム枠・ホームラン案）のモック生成器（#1316）。
// macOS 上で `swiftc -O mock.swift -o mock && ./mock <出力ディレクトリ>` で
// iPhone 実寸（393×852pt・@2x）の PNG を書き出す。アプリのビルドには一切使わない使い捨て。
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
                            HStack { Text("今日の挑戦").font(T.f(15)).foregroundStyle(T.ink); Spacer(); Text("残り 2 / 3").font(T.f(15, .heavy)).foregroundStyle(T.coral) }
                            Challenges(remaining: 2, total: 3)
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
            LobbyTrial()
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
            // 脚
            ForEach([84.0, 116.0], id: \.self) { x in
                Capsule().fill(V.white).frame(width: 24, height: 48).position(x: x, y: 138)
                Capsule().fill(V.navy).frame(width: 24, height: 20).position(x: x, y: 150)
                RoundedRectangle(cornerRadius: 5).fill(V.dark).frame(width: 30, height: 12).position(x: x, y: 163)
                Capsule().fill(.white.opacity(0.35)).frame(width: 5, height: 26).position(x: x - 7, y: 132)
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
            .position(x: 100, y: 112)
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
                Text("グリッドを 2 倍（頭 18 → 30 ドット）にし、縁の陰影と服の描き込み（ピンストライプ・前立て・ベルト・耳当て）を足した。色はチャリンコおじさんと同じパレット + 3 色。")
                    .font(T.f(11, .medium)).foregroundStyle(T.inkSub).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ユニフォーム姿・4 ポーズ（2 倍）").font(T.f(15, .heavy)).foregroundStyle(T.ink)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .center, spacing: 6) {
                            ForEach([Pose.stance, .swing, .cheer, .frown], id: \.self) { pose in
                                VStack(spacing: 2) { Px(canvas: ojisanHD(pose), scale: 2).frame(height: 166, alignment: .bottom); Text(label(pose)).font(T.f(10)).foregroundStyle(T.inkSub) }
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
                            Text("ベクターなので 44pt に縮めても線がにじまない。逆にドット絵路線の他の 18 本と並ぶハブでは浮く").font(T.f(10, .medium)).foregroundStyle(T.inkSub).fixedSize(horizontal: false, vertical: true)
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
                Text("方向A と方向B（同じポーズ・同じ大きさ）").font(T.f(18, .heavy)).foregroundStyle(T.ink).padding(.top, 64).fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 10) {
                    Card {
                        VStack(spacing: 6) {
                            Text("A ドット絵・高密度").font(T.f(14, .heavy)).foregroundStyle(T.ink)
                            Px(canvas: ojisanHD(.swing), scale: 2).frame(height: 190)
                            Px(canvas: ojisanHD(.cheer), scale: 2).frame(height: 190)
                        }.frame(maxWidth: .infinity)
                    }
                    Card {
                        VStack(spacing: 6) {
                            Text("B 滑らかな塗り").font(T.f(14, .heavy)).foregroundStyle(T.ink)
                            VecOjisan(pose: .swing).scaleEffect(0.98).frame(width: 160, height: 190).offset(x: -12)
                            VecOjisan(pose: .cheer).scaleEffect(0.98).frame(width: 160, height: 190).offset(x: -4)
                        }.frame(maxWidth: .infinity)
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 5) {
                        row("描く基盤", "PixelSprite + SpriteKit（走者と同じ）", "SwiftUI の図形（今回のモック）か、描き出した PNG を SpriteKit へ")
                        row("動き", "コマ絵の差し替え（走者と同じ）", "部品ごとの回転・移動（コマ数は不要）")
                        row("新規の絵", "4 ポーズ + 投手 + 球場の部品", "同左 + 影・光の設計（球場側も塗り直し）")
                        row("ハブとの一貫性", "18 本と同じ路線", "1 本だけ絵柄が違う（プレミアムの印にもなる）")
                        row("パワプロとの距離", "遠い（2D のまま）", "近づくが 3D ではない。頭身と光沢で寄せる")
                    }
                }
            }.padding(.horizontal, 16)
        }
    }
    func row(_ k: String, _ a: String, _ b: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(k).font(T.f(11, .heavy)).foregroundStyle(T.ink).frame(width: 78, alignment: .leading)
            Text(a).font(T.f(10, .medium)).foregroundStyle(T.inkSub).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            Text(b).font(T.f(10, .medium)).foregroundStyle(T.inkSub).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
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
