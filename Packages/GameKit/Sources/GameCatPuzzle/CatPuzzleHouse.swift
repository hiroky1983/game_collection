import SwiftUI
import Core

/// 盤を「おじさんの家の間取り」に見せる表（#2250・会長決定 2026-10-21「区画は家の部屋」）。
///
/// 部屋の番号（`CatPuzzle.rooms` の値）に、名前・床の柄・色・クリアで猫がくつろぐ姿を当てる。
/// 家の見た目は会長がこだわる所なので、**色・柄・名前・姿はこの 1 か所で変えられる**ようにしてある
/// （盤の描画は `CatPuzzleBoardCanvas` がこの表を読むだけ）。
enum CatPuzzleHouse {
    /// 床の柄。描き方は `CatPuzzleFloorPainter`。
    enum Floor: CaseIterable, Sendable {
        /// 畳（横の細い筋）。
        case tatami
        /// フローリング（縦の板と、互い違いの継ぎ目）。
        case planks
        /// タイル（1 マスを 2×2 に割る目地）。
        case tile
        /// カーペット（点の織り目）。
        case carpet
        /// 土間・石（1 マスずつ角を丸めた石）。
        case stone
    }

    /// 部屋 1 つぶんの見た目。
    struct Room: Sendable {
        let name: String
        let floor: Floor
        /// 床の色（ライト / ダーク）。
        let tint: Color
        /// 床の柄の線の濃さ（0〜1。柄ごとの見え方の差をここで吸収する）。
        let patternStrength: Double
        /// クリアで猫がくつろぐ姿。
        let clearPose: CatPuzzleArt.Pose
    }

    /// 部屋の並び。盤の大きさが 6 なら先頭 6 部屋、8 なら 8 部屋全部を使う。
    /// 名前は表示のたびに引く（言語切り替えに追従）。
    static var rooms: [Room] {
        [
            Room(name: tr("居間"), floor: .tatami,
                 tint: Color(light: 0xF2E6BC, dark: 0x4B4529), patternStrength: 0.9, clearPose: .sleep),
            Room(name: tr("押し入れ"), floor: .planks,
                 tint: Color(light: 0xF1ECE2, dark: 0x3E3A35), patternStrength: 0.8, clearPose: .sitUp),
            Room(name: tr("寝室"), floor: .carpet,
                 tint: Color(light: 0xF8DEDD, dark: 0x4D3639), patternStrength: 1.0, clearPose: .belly),
            Room(name: tr("書斎"), floor: .planks,
                 tint: Color(light: 0xDED6F4, dark: 0x3C3553), patternStrength: 0.9, clearPose: .sitSide),
            Room(name: tr("お風呂"), floor: .tile,
                 tint: Color(light: 0xD7F0F4, dark: 0x2E474C), patternStrength: 1.0, clearPose: .faceWow),
            Room(name: tr("台所"), floor: .tile,
                 tint: Color(light: 0xFBE4CA, dark: 0x4E3D2B), patternStrength: 0.9, clearPose: .pounce),
            Room(name: tr("玄関"), floor: .stone,
                 tint: Color(light: 0xE3DED6, dark: 0x3A3734), patternStrength: 1.0, clearPose: .stretch),
            Room(name: tr("縁側"), floor: .planks,
                 tint: Color(light: 0xEBD0A6, dark: 0x4B3B27), patternStrength: 1.0, clearPose: .sitFront),
        ]
    }

    /// 部屋の番号から見た目を引く（番号が表より大きければ折り返す）。
    static func room(_ index: Int) -> Room {
        let table = rooms
        return table[((index % table.count) + table.count) % table.count]
    }

    /// 壁の線の太さ（部屋どうしの境目）。外周はこの 1.5 倍。
    static let wallWidth: CGFloat = 3
    /// 部屋の中のマス目の線の太さ。
    static let gridWidth: CGFloat = 0.6
}

/// 床の柄の描き方。1 マスずつ描いても隣のマスとつながって見えるよう、マスの格子に揃えた柄にする。
enum CatPuzzleFloorPainter {
    static func draw(_ floor: CatPuzzleHouse.Floor, in rect: CGRect, strength: Double, context: inout GraphicsContext, ink: Color) {
        let s = rect.width
        var path = Path()
        var width: CGFloat = 1
        var alpha = 0.10 * strength
        switch floor {
        case .tatami:
            // 横の細い筋（畳の目）。
            let step = s / 6
            var y = rect.minY + step
            while y < rect.maxY - step / 2 {
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
                y += step
            }
            alpha = 0.09 * strength
        case .planks:
            // 縦の板 3 枚と、互い違いの継ぎ目。
            for i in 1..<3 {
                let x = rect.minX + s * CGFloat(i) / 3
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
            let col = Int((rect.minX / max(s, 1)).rounded())
            for i in 0..<3 {
                let x0 = rect.minX + s * CGFloat(i) / 3
                let y = rect.minY + s * ((i + col) % 2 == 0 ? 0.3 : 0.7)
                path.move(to: CGPoint(x: x0, y: y))
                path.addLine(to: CGPoint(x: x0 + s / 3, y: y))
            }
            alpha = 0.13 * strength
        case .tile:
            // 2×2 の目地。
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            width = 1.2
            alpha = 0.14 * strength
        case .carpet:
            // 点の織り目。
            let step = s / 4
            let r = max(0.8, s * 0.025)
            for i in 0..<4 {
                for j in 0..<4 {
                    let c = CGPoint(x: rect.minX + step * (CGFloat(i) + 0.5), y: rect.minY + step * (CGFloat(j) + 0.5))
                    path.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                }
            }
            context.fill(path, with: .color(ink.opacity(0.12 * strength)))
            return
        case .stone:
            // 角を丸めた石を 1 マスに 1 つ。
            let inset = s * 0.09
            path.addRoundedRect(in: rect.insetBy(dx: inset, dy: inset), cornerSize: CGSize(width: s * 0.18, height: s * 0.18))
            width = 1.2
            alpha = 0.12 * strength
        }
        context.stroke(path, with: .color(ink.opacity(alpha)), lineWidth: width)
    }
}
