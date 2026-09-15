import SwiftUI
import Core

/// 盤の配色（明るい木目調）。#366 の会長コンペで確定した「明るい飴色 × 無地アンバー」。
enum BoardStyle {
    static let frame = Color(hex: 0xE7B96A)
    /// 盤地と枠。単色をやめて上→下の木のグラデーションにする（#366）。
    /// マスは透明なハイライト層になったので、この2色が盤全体の地の色でもある。
    static let frameTop = Color(hex: 0xEDC178)
    static let frameBottom = Color(hex: 0xD3A04D)
    static let cell = Color(hex: 0xFBE6B6)
    static let line = Color(hex: 0xCDA15B)
    /// 駒は実物と同じくツゲ材（黄楊）のような単色。先手・後手は色ではなく向き（180度回転）で見分ける。
    static let komaWoodLight = Color(hex: 0xF3DFAE)
    /// 駒の面（#366）: 明るい飴色の縦グラデーション。
    static let komaFaceTop = Color(hex: 0xEFC98A)
    static let komaFaceBottom = Color(hex: 0xD9A85C)
    /// 駒の側面（#366）: 本体を下へずらした同じ駒形をこの色で敷き、木駒の厚みを見せる。
    static let komaSideTop = Color(hex: 0x9A6F33)
    static let komaSideBottom = Color(hex: 0x63431A)
    /// 王手の合図（#377）。玉のマスの枠と「王手」の札に使う。
    ///
    /// 実体は盤ゲーム共通の `BoardGameCheckColor`（#530）。チェスと同じ値・同じ理由で、
    /// 片方だけ差し替えると盤ゲーム間で危急の合図の色が食い違う。
    /// 盤の飴色（`frameTop` 0xEDC178）に対しても十分に沈んで見える。
    static let checkHex: UInt32 = BoardGameCheckColor.hex
    static let check = BoardGameCheckColor.color
    /// 駒の輪郭・面取り・文字（#366）。
    static let komaOutline = Color(hex: 0x6B4A1C)
    static let komaChamfer = Color(hex: 0xFFEFC2)
    static let komaText = Color(hex: 0x241708)
}

/// 将棋の駒（木製の実物に寄せた見た目・五角形）。先手・後手は色ではなく
/// 向き（pointsUp=false＝相手の駒は180度回転）だけで見分ける（実物と同じ規則）。
///
/// 見た目は #366 の会長コンペで確定した「明るい飴色 × なめらかな面」:
/// 木目の筋は**描かない**（試したが小さい駒ではノイズにしかならず不採用）。
/// 立体感は「厚い側面 + 稜線 + 面取り + 落ち影」で出す。
struct KomaView: View {
    let piece: Piece
    let size: CGFloat
    let pointsUp: Bool

    var body: some View {
        ZStack {
            // 側面: 本体を下へずらした同じ駒形を濃い木色で敷き、木駒の厚みを見せる。
            // 落ち影はいちばん下のこの層に掛ける（本体に掛けると影が自分の側面に落ちて濁る）。
            //
            // 向きの回転はこの層と本体に**別々に**掛ける。外側の ZStack ごと回すと
            // 下方向のオフセットまで回って、後手の駒だけ厚みが上端に出てしまう
            // （厚みと影は駒の向きに関係なく、机に置かれた実物として常に下端が正しい）。
            // 回転 → オフセットの順なので、ずれは常に画面座標の下向きになる。
            KomaShape()
                .fill(
                    LinearGradient(
                        colors: [BoardStyle.komaSideTop, BoardStyle.komaSideBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .rotationEffect(.degrees(pointsUp ? 0 : 180))
                .offset(y: size * 0.075)
                .shadow(color: .black.opacity(0.30), radius: 2.5, y: 2)
            // 木地: 上が明るく下がやや濃い縦グラデーション + 控えめな照りで、
            // 削り出した木の丸みを表現。
            ZStack {
                KomaShape()
                    .fill(
                        LinearGradient(
                            colors: [BoardStyle.komaFaceTop, BoardStyle.komaFaceBottom],
                            startPoint: .top, endPoint: .bottom)
                    )
                    .overlay(
                        KomaShape().fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.10),
                                         .clear,
                                         Color.black.opacity(0.10)],
                                startPoint: .top, endPoint: .bottom))
                    )
                    .overlay(KomaShape().stroke(
                        BoardStyle.komaOutline.opacity(0.75), lineWidth: 1))
                    // 面取り: 縁の内側に明→暗のグラデーション線を重ね、断面の厚みを疑似表現。
                    // 上辺は真っ白だと灰色に沈むため、木の明色で照らす。
                    .overlay(
                        KomaShape()
                            .stroke(
                                LinearGradient(
                                    colors: [BoardStyle.komaChamfer.opacity(0.9),
                                             .clear,
                                             Color.black.opacity(0.25)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: max(1, size * 0.05)
                            )
                    )
                    // 稜線: 面と側面の境目に1本のエッジを立て、五角柱の折り目に見せる。
                    .overlay(
                        KomaBaseEdgeShape()
                            .stroke(BoardStyle.komaSideBottom.opacity(0.55),
                                    lineWidth: max(1, size * 0.02))
                    )
                Text(Glyph.kanji(for: piece))
                    .font(.system(size: size * 0.46, weight: .black, design: .serif))
                    .foregroundStyle(piece.promoted ? Theme.coral : BoardStyle.komaText)
                    // 彫り込まれた文字に見えるよう、上に淡いハイライト・下に淡い影を重ねる。
                    .shadow(color: .white.opacity(0.4), radius: 0, x: 0, y: -0.5)
                    .shadow(color: .black.opacity(0.3), radius: 0.5, x: 0, y: 0.8)
            }
            .rotationEffect(.degrees(pointsUp ? 0 : 180))
        }
        .frame(width: size * 0.86, height: size * 0.86)
    }
}

/// 将棋の駒形（五角形）。上が尖り、下が平ら。
///
/// 会長フィードバック（#366）: 尖りすぎ → 実物の駒と同じく**天（てっぺん）に短い平らな辺**を
/// 持たせ、肩も少し上げて先端の角度を鈍くした。
struct KomaShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let shoulder = h * 0.30
        var p = Path()
        p.move(to: CGPoint(x: w * 0.455, y: h * 0.045))
        p.addLine(to: CGPoint(x: w * 0.545, y: h * 0.045))
        p.addLine(to: CGPoint(x: w * 0.845, y: shoulder))
        p.addLine(to: CGPoint(x: w * 0.90, y: h * 0.96))
        p.addLine(to: CGPoint(x: w * 0.10, y: h * 0.96))
        p.addLine(to: CGPoint(x: w * 0.155, y: shoulder))
        p.closeSubpath()
        return p
    }
}

/// 面と側面の境目（駒の底辺）。エッジを1本立てて五角柱の稜線に見せる（#366）。
struct KomaBaseEdgeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.10, y: h * 0.96))
        p.addLine(to: CGPoint(x: w * 0.90, y: h * 0.96))
        return p
    }
}

/// 駒の漢字表記。
enum Glyph {
    static func kanji(for p: Piece) -> String {
        if p.promoted {
            switch p.type {
            case .pawn: return "と"
            case .lance: return "杏"
            case .knight: return "圭"
            case .silver: return "全"
            case .bishop: return "馬"
            case .rook: return "龍"
            default: break
            }
        }
        switch p.type {
        case .pawn: return "歩"
        case .lance: return "香"
        case .knight: return "桂"
        case .silver: return "銀"
        case .gold: return "金"
        case .bishop: return "角"
        case .rook: return "飛"
        case .king: return p.color == .black ? "玉" : "王"
        }
    }
}
