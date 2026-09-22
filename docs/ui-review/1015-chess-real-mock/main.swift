import AppKit
import SwiftUI

// 使い方: mock <出力ディレクトリ>
// 「現行の立体」「A′」「C」を同じ盤・同じマスで並べた比較画像と、C を焼き画像にしたときの容量を出す。

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

enum Kind: String, CaseIterable { case current = "現行の立体", a2d = "A′（2D の限界）", c3d = "C（3D・焼き画像）" }

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
func png(_ img: CGImage, _ path: String) {
    let rep = NSBitmapImageRep(cgImage: img)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

@MainActor func swiftUIPiece(_ kind: Kind, _ p: ChessPiece, px: Int) -> CGImage {
    let size = CGFloat(px)
    let view: AnyView
    switch kind {
    case .current: view = AnyView(ChessPieceView(piece: p, size: size / 0.88 * 0.98, style: .sculpted).frame(width: size, height: size))
    case .a2d: view = AnyView(RealPiece2DView(piece: p, size: size))
    case .c3d: fatalError()
    }
    let r = ImageRenderer(content: view)
    r.scale = 1
    r.isOpaque = false
    return r.cgImage!
}

var c3dCache: [String: CGImage] = [:]
@MainActor func pieceImage(_ kind: Kind, _ p: ChessPiece, px: Int) -> CGImage {
    if kind == .c3d {
        let key = "\(p.type)-\(p.color)-\(px)"
        if let i = c3dCache[key] { return i }
        let i = RealScene.bake(p, px: px)
        c3dCache[key] = i
        return i
    }
    return swiftUIPiece(kind, p, px: px)
}

func hex(_ c: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((c >> 16) & 0xFF) / 255, green: CGFloat((c >> 8) & 0xFF) / 255, blue: CGFloat(c & 0xFF) / 255, alpha: 1)
}
let lightSq = hex(0xF2DFBB), darkSq = hex(0xB2884F)

func newCtx(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func label(_ ctx: CGContext, _ text: String, x: CGFloat, y: CGFloat, size: CGFloat) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
        .font: NSFont.boldSystemFont(ofSize: size), .foregroundColor: NSColor(white: 0.1, alpha: 1)])
    NSGraphicsContext.restoreGraphicsState()
}

/// 1 方式ぶんのパネル: 6 種 × 4 行（白/明, 白/暗, 黒/明, 黒/暗）。
@MainActor func panel(_ kind: Kind, cell px: Int) -> CGImage {
    let types: [ChessPieceType] = [.pawn, .knight, .bishop, .rook, .queen, .king]
    let rows: [(ChessColor, Bool)] = [(.white, true), (.white, false), (.black, true), (.black, false)]
    let ctx = newCtx(px * 6, px * 4)
    for (ri, row) in rows.enumerated() {
        for (ci, t) in types.enumerated() {
            let rect = CGRect(x: ci * px, y: (3 - ri) * px, width: px, height: px)
            ctx.setFillColor(row.1 ? lightSq : darkSq)
            ctx.fill(rect)
            ctx.draw(pieceImage(kind, ChessPiece(type: t, color: row.0), px: px), in: rect)
        }
    }
    return ctx.makeImage()!
}

@MainActor func compare(cell px: Int) -> CGImage {
    let gap = px / 3
    let panels = Kind.allCases.map { panel($0, cell: px) }
    let W = px * 6, H = (px * 4 + gap) * 3
    let ctx = newCtx(W, H)
    ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    for (i, k) in Kind.allCases.enumerated() {
        let y = H - (i + 1) * (px * 4 + gap)
        ctx.draw(panels[i], in: CGRect(x: 0, y: y, width: W, height: px * 4))
        label(ctx, k.rawValue, x: 8, y: CGFloat(y + px * 4 + gap / 5), size: CGFloat(gap) * 0.5)
    }
    return ctx.makeImage()!
}

@MainActor func board(_ kind: Kind, cell px: Int) -> CGImage {
    let order: [ChessPieceType] = [.rook, .knight, .bishop, .queen, .king, .bishop, .knight, .rook]
    let ctx = newCtx(px * 8, px * 8)
    for r in 0..<8 { for c in 0..<8 {
        let rect = CGRect(x: c * px, y: (7 - r) * px, width: px, height: px)
        ctx.setFillColor((r + c) % 2 == 0 ? lightSq : darkSq); ctx.fill(rect)
        var piece: ChessPiece?
        switch r {
        case 0: piece = ChessPiece(type: order[c], color: .black)
        case 1: piece = ChessPiece(type: .pawn, color: .black)
        case 6: piece = ChessPiece(type: .pawn, color: .white)
        case 7: piece = ChessPiece(type: order[c], color: .white)
        default: break
        }
        if let piece { ctx.draw(pieceImage(kind, piece, px: px), in: rect) }
    } }
    return ctx.makeImage()!
}

MainActor.assumeIsolated {
    let only = ProcessInfo.processInfo.environment["MOCK_ONLY"]
    for px in [150, 340] {
        png(compare(cell: px), "\(outDir)/compare-\(px == 150 ? "actual" : "zoom").png")
    }
    if only == nil {
        for (k, name) in [(Kind.current, "current"), (.a2d, "a2d"), (.c3d, "c3d")] {
            png(board(k, cell: 150), "\(outDir)/board-\(name).png")
        }
    }
    // 容量: C を焼き画像にしたときの 12 枚ぶん（@2x=100px / @3x=150px / 参考 256px）
    var report = ""
    for px in [100, 150, 256] {
        var total = 0
        for c in ChessColor.allCases { for t in ChessPieceType.allCases {
            let img = RealScene.bake(ChessPiece(type: t, color: c), px: px)
            let d = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!
            total += d.count
        } }
        report += "PNG 12 枚 \(px)px: \(total) bytes (\(String(format: "%.1f", Double(total) / 1024)) KiB)\n"
    }
    try! report.write(toFile: "\(outDir)/bake-size.txt", atomically: true, encoding: .utf8)
    print(report)
}
