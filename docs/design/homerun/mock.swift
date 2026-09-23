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
                            Px(canvas: ojisan(p, pose: .stance), scale: 3)
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
                            HStack { Text("今日の挑戦").font(T.f(15)).foregroundStyle(T.ink); Spacer(); Text("残り 3 / 5").font(T.f(15, .heavy)).foregroundStyle(T.coral) }
                            Challenges(remaining: 3, total: 5)
                            Text("0:00 に 5 回に戻ります").font(T.f(12, .medium)).foregroundStyle(T.inkSub)
                            HStack(spacing: 8) {
                                smallButton("広告を見て +3", sub: "きょう あと 2 回", icon: "play.rectangle.fill", fill: T.fillCoral)
                                smallButton("アンケートで +3", sub: "3 問・30 秒・1 日 1 回", icon: "list.bullet.clipboard.fill", fill: T.fillPurple)
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
                            Px(canvas: ojisan(p, pose: .stance), scale: 3)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack { Text("今日の挑戦").font(T.f(13)).foregroundStyle(T.inkSub); Spacer(); Text("残り 3 / 5").font(T.f(13, .heavy)).foregroundStyle(T.coral) }
                                Challenges(remaining: 3, total: 5)
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
    var body: some View {
        Canvas { ctx, size in
            let cols = Int(size.width / 6)
            let cs: [Color] = [T.coral, T.teal, T.purple, T.yellow, T.pink, .white, hexColor(0x4A3B33)]
            var seed = 7
            for r in 0..<rows { for c in 0..<cols {
                seed = (seed * 1103515245 + 12345) & 0x7fffffff
                let col = cs[seed % cs.count]
                ctx.fill(Path(ellipseIn: CGRect(x: CGFloat(c) * 6 + (r % 2 == 0 ? 0 : 3), y: CGFloat(r) * (size.height / CGFloat(rows)), width: 5, height: 5)), with: .color(col.opacity(0.85)))
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
            // 判定リング: 白い的（固定）と、収縮してくるコーラルの輪
            Circle().stroke(.white, lineWidth: 3).frame(width: 46, height: 46).position(x: 196, y: 662)
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
            Text("ナイス！").font(T.f(34, .heavy)).foregroundStyle(T.yellow)
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
                Chip(text: "ジャスト ±25ms", fill: T.yellow, icon: "star.fill")
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
                            Px(canvas: ojisan(p, pose: .cheer), scale: 3)
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
                        HStack { Text("今日の挑戦").font(T.f(15)).foregroundStyle(T.ink); Spacer(); Challenges(remaining: 2, total: 5); Text("残り 2").font(T.f(13, .heavy)).foregroundStyle(T.coral) }
                    }
                    BigButton(text: "もう一回（残り 2）", icon: "arrow.counterclockwise")
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
                    Px(canvas: ojisan(p, pose: .frown), scale: 3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("今日の挑戦を使い切りました").font(T.f(19, .heavy)).foregroundStyle(T.ink)
                        Text("残り 0 / 5 ・ 0:00 に 5 回に戻ります").font(T.f(13, .medium)).foregroundStyle(T.inkSub)
                    }
                }
                option("広告を見て +3 回", sub: "30 秒ほどの動画。きょう あと 2 回", icon: "play.rectangle.fill", fill: T.fillCoral)
                option("アンケートに答えて +3 回", sub: "3 問・30 秒。1 日 1 回。答えは開発の参考にします", icon: "list.bullet.clipboard.fill", fill: T.fillPurple)
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
                        Px(canvas: ojisan(p, pose: .swing), scale: 2).offset(x: -6, y: 6)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("柵越えおじさん").font(T.f(20, .heavy)).foregroundStyle(T.ink)
                        Text("1 日 5 回の柵越え勝負").font(T.f(13, .medium)).foregroundStyle(T.inkSub)
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
                ZStack { RoundedRectangle(cornerRadius: 14).fill(T.yellow).frame(width: 52, height: 52); Px(canvas: ojisan(p, pose: .stance), scale: 1) }
                Spacer()
                if premium { Chip(text: "残り 3 回", fill: T.fillPurple) } else { Chip(text: "きょう 1 回", fill: hexColor(0xEFE7DC)) }
            }
            Text("柵越えおじさん").font(T.f(17, .heavy)).foregroundStyle(T.ink)
            Text(premium ? "1 日 5 回。10 球で柵を越えろ" : "1 日 1 回のおためし").font(T.f(11, .medium)).foregroundStyle(T.inkSub)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(T.surface).shadow(color: .black.opacity(0.08), radius: 8, y: 3))
        .overlay(alignment: .topTrailing) {
            if premium { Text("プレミアム").font(T.f(10, .heavy)).foregroundStyle(T.onAccent).padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(T.fillCoral)).offset(x: -8, y: -8) }
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
    // ドット絵だけの大きなシート（レビュー用・8 倍）
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
}
